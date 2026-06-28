import XCTest
@testable import FCPXLite

/// 快捷键映射到的 store 操作(播放头步进/头尾/切割/删除)。
final class ShortcutOpsTests: XCTestCase {
    private func videoAsset(_ secs: Double) -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"),
              kind: .video, duration: .seconds(secs),
              naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }

    private func storeWith(spine: [Element], frameRate: Double = 25) -> DocumentStore {
        DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080,
                                         frameRate: frameRate, assetLibrary: [],
                                         sequence: Sequence(spine: spine)))
    }

    func testNudgePlayheadByFrames() {
        let s = storeWith(spine: [], frameRate: 25) // 1 帧 = 0.04s
        s.nudgePlayhead(frames: 1)
        XCTAssertEqual(s.ui.playhead.seconds, 0.04, accuracy: 1e-6)
        s.nudgePlayhead(frames: 10)
        XCTAssertEqual(s.ui.playhead.seconds, 0.44, accuracy: 1e-6)
        s.nudgePlayhead(frames: -100) // 不能为负 → 夹到 0
        XCTAssertEqual(s.ui.playhead.seconds, 0, accuracy: 1e-6)
    }

    func testPlayheadToEnd() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let b = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let s = storeWith(spine: [.clip(a), .clip(b)])
        s.playheadToEnd()
        XCTAssertEqual(s.ui.playhead.seconds, 5, accuracy: 1e-6)
        s.playheadToStart()
        XCTAssertEqual(s.ui.playhead.seconds, 0, accuracy: 1e-6)
    }

    func testBladeAtPlayheadSplits() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(6))
        let s = storeWith(spine: [.clip(a)])
        s.dispatch(.setPlayhead(.seconds(2)))
        s.bladeAtPlayhead()
        XCTAssertEqual(s.document.sequence.spine.count, 2) // 切成两段
    }

    func testDeleteSelectedRippleDeletes() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let b = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let s = storeWith(spine: [.clip(a), .clip(b)])
        s.dispatch(.selectClip(a.id))
        s.deleteSelected()
        XCTAssertEqual(s.document.sequence.spine.count, 1)
        XCTAssertNil(s.ui.selectedClipID)
        // 删了第一个,b 合拢到 0
        XCTAssertEqual(Layout.compute(s.document.sequence).first?.absStart, .seconds(0))
    }

    @MainActor
    func testTrimRightOnlyTrimsCurrentClip() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(4))
        let b = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(4))
        let s = storeWith(spine: [.clip(a), .clip(b)])  // 0..4, 4..8
        s.dispatch(.setPlayhead(.seconds(2)))           // 光标在第一段里
        s.trimRightOfPlayhead()
        let clips = s.document.sequence.spine.compactMap { e -> Clip? in if case .clip(let c) = e { return c }; return nil }
        XCTAssertEqual(clips.count, 2, "只裁当前片段,不删其它")
        XCTAssertEqual(clips[0].duration.seconds, 2, accuracy: 1e-6, "第一段尾被裁到光标")
        XCTAssertEqual(clips[1].duration.seconds, 4, accuracy: 1e-6, "第二段不变")
    }

    @MainActor
    func testTrimLeftOnlyTrimsCurrentClip() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(4))
        let b = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(4))
        let s = storeWith(spine: [.clip(a), .clip(b)])  // 0..4, 4..8
        s.dispatch(.setPlayhead(.seconds(6)))           // 光标在第二段里(4..8 的 6)
        s.trimLeftOfPlayhead()
        let clips = s.document.sequence.spine.compactMap { e -> Clip? in if case .clip(let c) = e { return c }; return nil }
        XCTAssertEqual(clips.count, 2, "只裁当前片段,不删其它")
        XCTAssertEqual(clips[0].duration.seconds, 4, accuracy: 1e-6, "第一段不变")
        XCTAssertEqual(clips[1].duration.seconds, 2, accuracy: 1e-6, "第二段头被裁(6-4=2 去掉,剩 2)")
    }

}
