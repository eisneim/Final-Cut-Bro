import XCTest
import AppKit
@testable import FCPXLite

/// 性能基准(对照实验):跨时间轴规模 N∈{1,10,50,200} 测量四个热点的真实耗时,
/// 数据驱动定位瓶颈。不依赖 GUI/server —— 纯 headless,可重复。
/// 运行:swift test --filter PerfBenchmarkTests  然后看 stdout 打印的表格。
@MainActor
final class PerfBenchmarkTests: XCTestCase {

    private func vAsset(_ dur: Double) -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v\(UUID().uuidString).mov"), kind: .video,
              duration: .seconds(dur), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }

    /// 造 N 个主轴片段,每隔一个挂一条连接字幕(模拟真实成片:视频 + 字幕叠加)。
    private func makeSequence(_ n: Int) -> (Sequence, [Asset]) {
        var spine: [Element] = []; var assets: [Asset] = []
        for i in 0..<n {
            let a = vAsset(3); assets.append(a)
            var conn: [Clip] = []
            if i % 2 == 0 {
                var spec = TitleSpec(); spec.text = "字幕\(i)"
                conn = [Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(1.5),
                             lane: 1, offset: .seconds(0.5), title: spec)]
            }
            spine.append(.clip(Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(3), connected: conn)))
        }
        return (Sequence(spine: spine), assets)
    }

    /// 手动计时(毫秒):跑 iters 次取平均,避免单次抖动。
    private func timeMS(_ iters: Int, _ body: () -> Void) -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iters { body() }
        let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000.0
        return dt / Double(iters)
    }

    private let sizes = [1, 10, 50, 200]

    /// 基准 1:Layout.compute 单次调用耗时 vs N(基础成本,含 sort)。
    func testLayoutComputeScaling() {
        PerfProbe.shared.enabled = false   // 用手动计时,避免探针自身开销
        print("\n=== 基准1: Layout.compute 单次耗时 (ms) ===")
        print("N\tclips+titles\tms/call")
        for n in sizes {
            let (seq, _) = makeSequence(n)
            let placedCount = Layout.compute(seq).count
            let ms = timeMS(200) { _ = Layout.compute(seq) }
            print("\(n)\t\(placedCount)\t\t\(String(format: "%.4f", ms))")
        }
    }

    /// 基准 2:一次「apply + 真实 draw」触发多少次 Layout.compute(视图内的冗余倍数)。
    func testLayoutCallsPerRedraw() {
        for n in sizes {
            let (seq, assets) = makeSequence(n)
            let content = TimelineContentView(frame: NSRect(x: 0, y: 0, width: 2000, height: 600))
            let state = TimelineContentView.State(
                sequence: seq, assetLibrary: assets, pxPerSecond: 60, playheadSeconds: 1,
                selectedClipID: nil, selectedClipIDs: [], selectedGapID: nil,
                selectedTransitionClipID: nil, currentTool: .select,
                snappingEnabled: true, clipHeight: 72, vaRatio: 0.6)

            PerfProbe.shared.enabled = true
            PerfProbe.shared.reset()
            content.apply(state: state)
            // 真实绘制到 bitmap(触发 draw(_:),无需窗口)
            if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
            }
            let calls = PerfProbe.shared.snapshot()["Layout.compute"]?.count ?? 0
            let totalMS = PerfProbe.shared.snapshot()["Layout.compute"]?.totalMS ?? 0
            PerfProbe.shared.enabled = false
            print("=== 基准2: N=\(n) 一次 apply+draw → Layout.compute 调用 \(calls) 次, 累计 \(String(format: "%.3f", totalMS))ms ===")
        }
    }

    /// 基准 3:一次 dispatch 编辑(blade)耗时 vs N。
    func testDispatchScaling() {
        PerfProbe.shared.enabled = false
        print("\n=== 基准3: dispatch(blade at playhead) 单次耗时 (ms) ===")
        print("N\tms/dispatch")
        for n in sizes {
            let (seq, assets) = makeSequence(n)
            let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                               assetLibrary: assets, sequence: seq)
            let store = DocumentStore(document: doc)
            store.dispatch(.setPlayhead(.seconds(1.5)))   // 落在第一个片段内
            let ms = timeMS(100) {
                store.dispatch(.blade(at: 0, localTime: .seconds(1.5)))
                store.undo()   // 还原,保证每次同规模
            }
            print("\(n)\t\(String(format: "%.4f", ms))")
        }
    }

    /// 基准 4:一次真实 draw(cacheDisplay)耗时 vs N。
    func testDrawScaling() {
        PerfProbe.shared.enabled = false
        print("\n=== 基准4: 一次真实 draw 耗时 (ms) ===")
        print("N\tms/draw")
        for n in sizes {
            let (seq, assets) = makeSequence(n)
            let content = TimelineContentView(frame: NSRect(x: 0, y: 0, width: 2000, height: 600))
            content.apply(state: TimelineContentView.State(
                sequence: seq, assetLibrary: assets, pxPerSecond: 60, playheadSeconds: 1,
                selectedClipID: nil, selectedClipIDs: [], selectedGapID: nil,
                selectedTransitionClipID: nil, currentTool: .select,
                snappingEnabled: true, clipHeight: 72, vaRatio: 0.6))
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                print("\(n)\t(no rep)"); continue
            }
            let ms = timeMS(30) { content.cacheDisplay(in: content.bounds, to: rep) }
            print("\(n)\t\(String(format: "%.4f", ms))")
        }
    }

    /// 修复验证:窄 dirtyRect 只重画相交片段(Task 2 裁剪)。N=200 全画 200 个,窄条只画个位数。
    func testDrawCullingByDirtyRect() {
        let (seq, assets) = makeSequence(200)
        // frame 要够宽容纳全部 200 片段(200×3s×60px=36000),否则"全画"也只覆盖视口内的。
        let content = TimelineContentView(frame: NSRect(x: 0, y: 0, width: 37000, height: 600))
        content.apply(state: TimelineContentView.State(
            sequence: seq, assetLibrary: assets, pxPerSecond: 60, playheadSeconds: 1,
            selectedClipID: nil, selectedClipIDs: [], selectedGapID: nil,
            selectedTransitionClipID: nil, currentTool: .select,
            snappingEnabled: true, clipHeight: 72, vaRatio: 0.6))
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return XCTFail("no ctx") }

        func drawClipCount(dirtyRect: NSRect) -> Int {
            PerfProbe.shared.enabled = true
            PerfProbe.shared.reset()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            content.draw(dirtyRect)
            NSGraphicsContext.restoreGraphicsState()
            let n = PerfProbe.shared.snapshot()["drawClip"]?.count ?? 0
            PerfProbe.shared.enabled = false
            return n
        }
        // 全画:画全部片段(200 主轴 + 100 连接字幕 = placed.count)
        let expectedFull = content.placed.count
        let full = drawClipCount(dirtyRect: content.bounds)
        // 窄条(播放头附近 40pt):只画个位数
        let stripRect = NSRect(x: 100, y: 0, width: 40, height: content.bounds.height)
        let strip = drawClipCount(dirtyRect: stripRect)
        // 耗时对比(修复的核心收益:播放头移动=窄条重画)
        func drawMS(_ r: NSRect) -> Double {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
            let ms = timeMS(20) { content.draw(r) }
            NSGraphicsContext.restoreGraphicsState(); return ms
        }
        let fullMS = drawMS(content.bounds), stripMS = drawMS(stripRect)
        print("\n=== 修复验证 Task2: drawClip 全画=\(full) vs 窄条=\(strip);耗时 全画=\(String(format: "%.1f", fullMS))ms vs 窄条=\(String(format: "%.2f", stripMS))ms ===")
        XCTAssertEqual(full, expectedFull, "全画应画全部片段")
        XCTAssertLessThan(strip, 10, "窄 dirtyRect 只重画相交片段(应个位数)")
    }

    /// 修复验证:一次 apply+draw 的 Layout.compute 从 2 降到 1(Task 4 缓存)。
    func testLayoutMemoized() {
        let (seq, assets) = makeSequence(50)
        let content = TimelineContentView(frame: NSRect(x: 0, y: 0, width: 2000, height: 600))
        PerfProbe.shared.enabled = true
        PerfProbe.shared.reset()
        content.apply(state: TimelineContentView.State(
            sequence: seq, assetLibrary: assets, pxPerSecond: 60, playheadSeconds: 1,
            selectedClipID: nil, selectedClipIDs: [], selectedGapID: nil,
            selectedTransitionClipID: nil, currentTool: .select,
            snappingEnabled: true, clipHeight: 72, vaRatio: 0.6))
        // 模拟一次重画 + 多次命中测试(拖拽 tick 会反复命中)
        _ = content.placed
        for _ in 0..<10 { _ = content.hitTestClip(at: NSPoint(x: 300, y: 100)) }
        let calls = PerfProbe.shared.snapshot()["Layout.compute"]?.count ?? 0
        PerfProbe.shared.enabled = false
        print("\n=== 修复验证 Task4: apply+placed+10次命中 → Layout.compute 调用 \(calls) 次(缓存前会是 12+)===")
        XCTAssertEqual(calls, 1, "同一 sequence 版本内 Layout.compute 只算一次")
    }
}
