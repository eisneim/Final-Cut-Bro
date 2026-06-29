import XCTest
@testable import FCPXLite

/// T6:时间轴 clip 复制/粘贴(⌘C/⌘V → 复制选中片段到播放头)。
@MainActor
final class ClipCopyPasteTests: XCTestCase {
    private func storeWithClips(_ durs: [Double]) -> (DocumentStore, [ClipID]) {
        let clips = durs.map { Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds($0)) }
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: clips.map { .clip($0) }))
        return (DocumentStore(document: doc), clips.map { $0.id })
    }

    func testCopyPasteInsertsDuplicateWithNewID() {
        let (s, ids) = storeWithClips([5, 5])
        s.dispatch(.selectClip(ids[0]))
        s.copySelected()
        s.dispatch(.setPlayhead(.seconds(10)))   // 末尾
        s.pasteAtPlayhead()
        XCTAssertEqual(s.document.sequence.spine.count, 3, "粘贴新增一个片段")
        // 新片段 id 与原片段不同
        guard case .clip(let pasted) = s.document.sequence.spine[2] else { return XCTFail() }
        XCTAssertNotEqual(pasted.id, ids[0])
        XCTAssertEqual(pasted.duration.seconds, 5, accuracy: 0.001, "时长与原片段一致")
    }

    func testPasteAtPlayheadInsertsAtNearestBoundary() {
        let (s, ids) = storeWithClips([5, 5])  // 边界:0,5,10
        s.dispatch(.selectClip(ids[1]))
        s.copySelected()
        s.dispatch(.setPlayhead(.seconds(5)))  // 第二片段起点 → 插在 index 1
        s.pasteAtPlayhead()
        XCTAssertEqual(s.document.sequence.spine.count, 3)
        // 插入在 index 1(在第一片段之后,原第二片段之前)
        guard case .clip(let c0) = s.document.sequence.spine[0],
              case .clip(let c1) = s.document.sequence.spine[1] else { return XCTFail() }
        XCTAssertEqual(c0.id, ids[0], "第一片段不动")
        XCTAssertNotEqual(c1.id, ids[1], "index 1 是粘贴的新片段")
    }

    func testPasteSelectsNewClip() {
        let (s, ids) = storeWithClips([4])
        s.dispatch(.selectClip(ids[0]))
        s.copySelected()
        s.dispatch(.setPlayhead(.seconds(4)))
        s.pasteAtPlayhead()
        guard case .clip(let pasted) = s.document.sequence.spine[1] else { return XCTFail() }
        XCTAssertEqual(s.ui.selectedClipID, pasted.id, "粘贴后选中新片段")
    }

    func testPasteWithoutCopyIsNoOp() {
        let (s, _) = storeWithClips([3])
        s.pasteAtPlayhead()   // 没复制过
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }

    func testPasteIsUndoable() {
        let (s, ids) = storeWithClips([5])
        s.dispatch(.selectClip(ids[0]))
        s.copySelected()
        s.dispatch(.setPlayhead(.seconds(5)))
        s.pasteAtPlayhead()
        XCTAssertEqual(s.document.sequence.spine.count, 2)
        s.undo()
        XCTAssertEqual(s.document.sequence.spine.count, 1, "粘贴可撤销")
    }

    func testDuplicateGivesConnectedChildrenNewIDs() {
        // 带连接子项的片段复制 → 子项也换新 id
        let child = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2), lane: 1)
        let host = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5), connected: [child])
        let dup = host.duplicatedWithNewIDs()
        XCTAssertNotEqual(dup.id, host.id)
        XCTAssertEqual(dup.connected.count, 1)
        XCTAssertNotEqual(dup.connected[0].id, child.id)
        XCTAssertEqual(dup.connected[0].duration.seconds, 2, accuracy: 0.001)
    }

    func testCopyPreservesAdjustAndKeyframes() {
        var clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5))
        clip.adjust.opacity = 0.5
        clip.transformKeyframes = [TransformKeyframe(time: .seconds(0), opacity: 1),
                                   TransformKeyframe(time: .seconds(5), opacity: 0)]
        let dup = clip.duplicatedWithNewIDs()
        XCTAssertEqual(dup.adjust.opacity, 0.5)
        XCTAssertEqual(dup.transformKeyframes.count, 2)
    }
}
