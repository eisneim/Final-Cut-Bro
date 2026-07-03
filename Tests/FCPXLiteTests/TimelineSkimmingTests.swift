import XCTest
@testable import FCPXLite

/// 主时间轴 skimming 的 store 行为:
/// - 播放优先:skimming 中 togglePlay → 从 skimmer 位置起播 + 清 skim。
/// - ⌘B 切割在 skimmer 位置(而非红色播放头)。
@MainActor
final class TimelineSkimmingTests: XCTestCase {

    private func storeWithOneClip() -> DocumentStore {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                      duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080),
                      frameRate: 25, hasAudio: true)
        let store = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                     assetLibrary: [a], sequence: Sequence(spine: [])))
        store.dispatch(.insertClip(Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(10)), at: 0))
        return store
    }
    private func clipCount(_ s: DocumentStore) -> Int {
        s.document.sequence.spine.reduce(0) { if case .clip = $1 { return $0 + 1 }; return $0 }
    }

    func testTogglePlayOverridesSkimming() {
        let store = storeWithOneClip()
        store.dispatch(.toggleTimelineSkimming)
        store.dispatch(.setTimelineSkim(4.0))       // 鼠标划到 4s
        XCTAssertEqual(store.ui.playhead.seconds, 0, accuracy: 0.001)

        store.dispatch(.togglePlay)                 // 空格
        XCTAssertTrue(store.ui.isPlaying, "应开始播放")
        XCTAssertNil(store.ui.timelineSkimSeconds, "播放优先 → skim 被取消")
        XCTAssertEqual(store.ui.playhead.seconds, 4.0, accuracy: 0.001, "从 skimmer 位置起播")
    }

    func testBladeCutsAtSkimmerNotPlayhead() {
        let store = storeWithOneClip()
        store.dispatch(.setPlayhead(.seconds(2.0)))       // 播放头在 2s
        store.dispatch(.toggleTimelineSkimming)
        store.dispatch(.setTimelineSkim(6.0))             // skimmer 在 6s
        XCTAssertEqual(clipCount(store), 1)

        store.bladeAtPlayhead()                            // ⌘B
        XCTAssertEqual(clipCount(store), 2, "应切成两段")
        // 第一段时长应为 6s(切在 skimmer 处),而非 2s(播放头处)。
        guard case .clip(let first) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(first.duration.seconds, 6.0, accuracy: 0.05, "切点在 skimmer(6s)而非播放头(2s)")
    }

    func testBladeUsesPlayheadWhenNotSkimming() {
        let store = storeWithOneClip()
        store.dispatch(.setPlayhead(.seconds(2.0)))
        store.bladeAtPlayhead()
        XCTAssertEqual(clipCount(store), 2)
        guard case .clip(let first) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(first.duration.seconds, 2.0, accuracy: 0.05, "无 skimming → 切在播放头")
    }
}
