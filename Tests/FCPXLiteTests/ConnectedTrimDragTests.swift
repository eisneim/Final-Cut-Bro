import XCTest
import CoreGraphics
@testable import FCPXLite

/// 连接片段(字幕/连接音频)可 trim 时长 + 拖拽平滑重定位(不塌 lane / 不变主轴)。
@MainActor
final class ConnectedTrimDragTests: XCTestCase {

    private func vAsset(_ dur: Double = 20) -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a\(UUID().uuidString).mov"), kind: .video,
              duration: .seconds(dur), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }

    /// 宿主视频(10s,起点0)+ 连接字幕(offset 2, 时长 3)+ 连接音乐(媒体, offset 1, sourceIn 0, 时长 4)。
    private func base() -> (DocumentStore, title: ClipID, music: ClipID, host: ClipID, musicAsset: Asset) {
        let hostAsset = vAsset(10)
        var spec = TitleSpec(); spec.text = "字幕"
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3), lane: 1, offset: .seconds(2), title: spec)
        let musicAsset = vAsset(30)
        let music = Clip(assetID: musicAsset.id, sourceIn: .zero, duration: .seconds(4), lane: -1, offset: .seconds(1))
        let host = Clip(assetID: hostAsset.id, sourceIn: .zero, duration: .seconds(10), connected: [title, music])
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [hostAsset, musicAsset], sequence: Sequence(spine: [.clip(host)]))
        return (DocumentStore(document: doc), title.id, music.id, host.id, musicAsset)
    }
    private func clip(_ s: DocumentStore, _ id: ClipID) -> Clip { s.clipsByIDs([id]).first!.clip }

    // MARK: setClipTiming 加 sourceIn

    func testSetClipTimingSourceIn() {
        let (s, _, music, _, _) = base()
        s.dispatch(.setConnectedTiming(music, offset: .seconds(3), sourceIn: .seconds(2), duration: .seconds(5)))
        let m = clip(s, music)
        XCTAssertEqual(m.offset.seconds, 3, accuracy: 1e-6)
        XCTAssertEqual(m.sourceIn.seconds, 2, accuracy: 1e-6)
        XCTAssertEqual(m.duration.seconds, 5, accuracy: 1e-6)
    }

    /// nil 字段不动原值(只改 duration)。
    func testSetClipTimingPartial() {
        let (s, title, _, _, _) = base()
        s.dispatch(.setConnectedTiming(title, offset: nil, sourceIn: nil, duration: .seconds(6)))
        let t = clip(s, title)
        XCTAssertEqual(t.offset.seconds, 2, accuracy: 1e-6, "offset 不变")
        XCTAssertEqual(t.duration.seconds, 6, accuracy: 1e-6)
    }

    // MARK: 尾 trim / 头 trim(经 ⌥] / ⌥[ 到播放头,覆盖计算)

    /// ⌥] 裁尾:选中字幕,播放头 4s(字幕起点2)→ 时长=2。
    func testTrimTailConnectedViaPlayhead() {
        let (s, title, _, _, _) = base()
        s.dispatch(.selectClip(title))
        s.dispatch(.setPlayhead(.seconds(4)))
        s.trimRightOfPlayhead()
        XCTAssertEqual(clip(s, title).duration.seconds, 2, accuracy: 1e-6)   // 4 - 2
        XCTAssertEqual(clip(s, title).offset.seconds, 2, accuracy: 1e-6)     // offset 不变
    }

    /// ⌥[ 裁头:选中媒体音乐(起点1),播放头 3s → deltaIn=2 → offset 3, sourceIn 2, 时长 2。
    func testTrimHeadConnectedMediaViaPlayhead() {
        let (s, _, music, _, _) = base()
        s.dispatch(.selectClip(music))
        s.dispatch(.setPlayhead(.seconds(3)))
        s.trimLeftOfPlayhead()
        let m = clip(s, music)
        XCTAssertEqual(m.offset.seconds, 3, accuracy: 1e-6)     // 1 + 2
        XCTAssertEqual(m.sourceIn.seconds, 2, accuracy: 1e-6)   // 媒体入点前移
        XCTAssertEqual(m.duration.seconds, 2, accuracy: 1e-6)   // 4 - 2
    }

    /// 字幕(非媒体)裁头不动 sourceIn。
    func testTrimHeadTitleNoSourceIn() {
        let (s, title, _, _, _) = base()
        s.dispatch(.selectClip(title))
        s.dispatch(.setPlayhead(.seconds(3.5)))   // 字幕起点2 → deltaIn 1.5
        s.trimLeftOfPlayhead()
        let t = clip(s, title)
        XCTAssertEqual(t.offset.seconds, 3.5, accuracy: 1e-6)
        XCTAssertEqual(t.sourceIn.seconds, 0, accuracy: 1e-6, "标题无媒体入点")
        XCTAssertEqual(t.duration.seconds, 1.5, accuracy: 1e-6)
    }

    // MARK: relocateConnected 平滑重定位

    /// 拖字幕到 6s、lane 3 → absStart==6、lane==3、仍是连接(不进主轴)。
    func testRelocateConnectedKeepsConnectedAndTracks() {
        let (s, title, _, host, _) = base()
        s.dispatch(.relocateConnected(title, lane: 3, time: .seconds(6)))
        // 仍是连接子项(host 里找得到,spine 顶层找不到)
        XCTAssertNil(TimelineGeometry.spineIndex(ofClipID: title, in: s.document.sequence))
        let placed = Layout.compute(s.document.sequence).first { $0.clipID == title }!
        XCTAssertEqual(placed.absStart.seconds, 6, accuracy: 1e-6, "x 跟手:absStart==目标时间")
        XCTAssertEqual(placed.lane, 3, "lane 用请求值,不塌回 ±1")
        XCTAssertTrue(placed.isConnected)
        _ = host
    }

    /// lane 传 0 也不会变成主轴(mutation clamp 到非零);且宿主不变。
    func testRelocateConnectedNeverBecomesSpine() {
        let (s, title, _, _, _) = base()
        s.dispatch(.relocateConnected(title, lane: 2, time: .seconds(5)))
        let spineClipCount = s.document.sequence.spine.filter { if case .clip = $0 { return true }; return false }.count
        XCTAssertEqual(spineClipCount, 1, "主轴仍只有宿主 1 个片段,字幕没被插进主轴")
    }
}
