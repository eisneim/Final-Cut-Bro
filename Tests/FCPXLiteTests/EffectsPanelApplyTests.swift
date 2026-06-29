import XCTest
@testable import FCPXLite

/// T12:效果/转场面板的"应用到选中片段"逻辑(addEffectToSelected / addCrossfadeToSelected)。
@MainActor
final class EffectsPanelApplyTests: XCTestCase {
    private func store2() -> DocumentStore {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                      duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let s = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                 assetLibrary: [a], sequence: Sequence(spine: [])))
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        return s
    }
    private func clip(_ s: DocumentStore, _ i: Int) -> Clip? {
        guard case .clip(let c) = s.document.sequence.spine[i] else { return nil }
        return c
    }

    func testAddEffectToSelectedAppendsEffect() {
        let s = store2()
        s.dispatch(.selectClip(clip(s, 0)!.id))
        s.addEffectToSelected(.blur)
        XCTAssertEqual(clip(s, 0)?.effects.count, 1)
        XCTAssertEqual(clip(s, 0)?.effects.first?.kind, .blur)
    }

    func testAddEffectStacks() {
        let s = store2()
        s.dispatch(.selectClip(clip(s, 0)!.id))
        s.addEffectToSelected(.color)
        s.addEffectToSelected(.blur)
        XCTAssertEqual(clip(s, 0)?.effects.count, 2, "特效可堆叠")
    }

    func testAddEffectNoSelectionIsNoOp() {
        let s = store2()
        s.addEffectToSelected(.blur)   // 未选中
        XCTAssertEqual(clip(s, 0)?.effects.count, 0)
        XCTAssertEqual(clip(s, 1)?.effects.count, 0)
    }

    func testAddCrossfadeToSelectedSecondClip() {
        let s = store2()
        s.dispatch(.selectClip(clip(s, 1)!.id))
        XCTAssertTrue(s.addCrossfadeToSelected(seconds: 1.0))
        XCTAssertEqual(clip(s, 1)?.crossfadeIn.seconds ?? -1, 1.0, accuracy: 0.001)
    }

    func testAddCrossfadeToFirstClipFails() {
        let s = store2()
        s.dispatch(.selectClip(clip(s, 0)!.id))
        XCTAssertFalse(s.addCrossfadeToSelected(seconds: 1.0), "首片段无前邻,加转场失败")
        XCTAssertEqual(clip(s, 0)?.crossfadeIn.seconds, 0)
    }

    func testAddCrossfadeNoSelectionFails() {
        let s = store2()
        XCTAssertFalse(s.addCrossfadeToSelected(seconds: 1.0))
    }
}
