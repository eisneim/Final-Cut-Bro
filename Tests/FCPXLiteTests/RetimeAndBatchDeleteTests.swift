import XCTest
import CoreGraphics
@testable import FCPXLite

/// 两个 bug 的回归:
/// 1. 字幕/连接片段【改时间】—— set_title 的 startSeconds/durationSeconds 改 offset/duration。
/// 2. 时间轴【多选批量删除】—— deleteSelected 删掉全部选中项(单次 undo);素材池批量删。
@MainActor
final class RetimeAndBatchDeleteTests: XCTestCase {

    private func vAsset(_ dur: Double = 10) -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v\(UUID().uuidString).mov"), kind: .video,
              duration: .seconds(dur), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }
    private func run(_ s: DocumentStore, _ type: String, _ args: [String: Any]) -> String {
        AgentActionCatalog.find(type)!.apply(s, args.merging(["type": type]) { x, _ in x })
    }

    /// 宿主视频(10s,起点0)+ 连接字幕(offset 2, 时长 3)。
    private func storeWithConnectedTitle() -> (DocumentStore, ClipID) {
        let a = vAsset(10)
        var spec = TitleSpec(); spec.text = "字幕"
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3),
                         lane: 1, offset: .seconds(2), title: spec)
        let v = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(10), connected: [title])
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [a], sequence: Sequence(spine: [.clip(v)]))
        return (DocumentStore(document: doc), title.id)
    }

    // MARK: Bug 1 — 字幕改时间

    /// set_title startSeconds/durationSeconds → 连接字幕 offset/duration 改变(宿主起点0 → offset=start)。
    func testSetTitleRetimeViaAgent() {
        let (s, tid) = storeWithConnectedTitle()
        let out = run(s, "set_title", ["titleIndex": 0, "startSeconds": 5.0, "durationSeconds": 4.0])
        XCTAssertFalse(out.contains("错误"), out)
        let t = s.clipsByIDs([tid]).first!.clip
        XCTAssertEqual(t.offset.seconds, 5.0, accuracy: 1e-6, "起点5s,宿主起点0 → offset=5")
        XCTAssertEqual(t.duration.seconds, 4.0, accuracy: 1e-6)
    }

    /// 只改时长,起点不动。
    func testSetTitleDurationOnly() {
        let (s, tid) = storeWithConnectedTitle()
        _ = run(s, "set_title", ["titleIndex": 0, "durationSeconds": 6.0])
        let t = s.clipsByIDs([tid]).first!.clip
        XCTAssertEqual(t.offset.seconds, 2.0, accuracy: 1e-6, "只改时长时 offset 不变")
        XCTAssertEqual(t.duration.seconds, 6.0, accuracy: 1e-6)
    }

    /// 起点被 clamp 到 >=0(不能为负)。
    func testSetTitleStartClampedNonNegative() {
        let (s, tid) = storeWithConnectedTitle()
        _ = run(s, "set_title", ["titleIndex": 0, "startSeconds": -3.0])
        XCTAssertEqual(s.clipsByIDs([tid]).first!.clip.offset.seconds, 0.0, accuracy: 1e-6)
    }

    /// dispatch 层直接改连接片段定位,可单次 undo 还原。
    func testSetConnectedTimingUndo() {
        let (s, tid) = storeWithConnectedTitle()
        s.dispatch(.setConnectedTiming(tid, offset: .seconds(7), sourceIn: nil, duration: .seconds(1)))
        XCTAssertEqual(s.clipsByIDs([tid]).first!.clip.offset.seconds, 7.0, accuracy: 1e-6)
        s.undo()
        XCTAssertEqual(s.clipsByIDs([tid]).first!.clip.offset.seconds, 2.0, accuracy: 1e-6)
    }

    // MARK: Bug 2 — 多选批量删除

    private func spineStore(_ n: Int) -> (DocumentStore, [ClipID]) {
        var clips: [Clip] = []; var assets: [Asset] = []
        for _ in 0..<n {
            let a = vAsset(3); assets.append(a)
            clips.append(Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(3)))
        }
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: assets, sequence: Sequence(spine: clips.map { .clip($0) }))
        return (DocumentStore(document: doc), clips.map(\.id))
    }

    /// 框选多个主轴片段 → Delete 全删,单次 undo 还原。
    func testBatchDeleteSpineClips() {
        let (s, ids) = spineStore(3)
        s.dispatch(.selectClips([ids[0], ids[2]], anchor: ids[0]))   // 删首尾,留中间
        s.deleteSelected()
        XCTAssertEqual(s.document.sequence.spine.filter { if case .clip = $0 { return true }; return false }.count, 1)
        s.undo()
        XCTAssertEqual(s.document.sequence.spine.count, 3, "一次 undo 还原全部")
    }

    /// 连接片段 + 主轴片段混合多选 → 一起删。
    func testBatchDeleteMixedConnectedAndSpine() {
        let a = vAsset(10)
        var spec = TitleSpec(); spec.text = "字幕"
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2), lane: 1, offset: .seconds(1), title: spec)
        let v0 = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5), connected: [title])
        let a1 = vAsset(4)
        let v1 = Clip(assetID: a1.id, sourceIn: .zero, duration: .seconds(4))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [a, a1], sequence: Sequence(spine: [.clip(v0), .clip(v1)]))
        let s = DocumentStore(document: doc)
        s.dispatch(.selectClips([title.id, v1.id], anchor: v1.id))
        s.deleteSelected()
        // v1 删掉 → 主轴只剩 v0;v0 的连接字幕删掉 → connected 为空
        XCTAssertEqual(s.clipsByIDs([v1.id]).count, 0, "v1 已删")
        XCTAssertEqual(s.clipsByIDs([title.id]).count, 0, "连接字幕已删")
        XCTAssertEqual(s.clipsByIDs([v0.id]).first?.clip.connected.count, 0)
    }

    /// 单选删除仍正常(不回归)。
    func testSingleDeleteStillWorks() {
        let (s, ids) = spineStore(2)
        s.dispatch(.selectClip(ids[0]))
        s.deleteSelected()
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }

    /// 素材池批量删除:removeAssets 删掉全部选中素材,单次 undo。
    func testRemoveAssetsBatch() {
        let (s, _) = spineStore(3)
        let all = Set(s.document.assetLibrary.map(\.id))
        s.removeAssets(all)
        XCTAssertEqual(s.document.assetLibrary.count, 0)
        s.undo()
        XCTAssertEqual(s.document.assetLibrary.count, 3, "一次 undo 还原全部素材")
    }
}
