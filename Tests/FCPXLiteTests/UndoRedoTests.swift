import XCTest
@testable import FCPXLite

final class UndoRedoTests: XCTestCase {
    private func store() -> DocumentStore {
        DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                         assetLibrary: [], sequence: Sequence(spine: [])))
    }
    private func clip(_ s: Double) -> Clip { Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(s)) }

    func testUndoInsert() {
        let s = store()
        s.dispatch(.insertClip(clip(2), at: 0))
        XCTAssertEqual(s.document.sequence.spine.count, 1)
        s.undo()
        XCTAssertEqual(s.document.sequence.spine.count, 0)
        s.redo()
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }

    func testUndoMultiple() {
        let s = store()
        s.dispatch(.insertClip(clip(2), at: 0))
        s.dispatch(.insertClip(clip(3), at: 1))
        XCTAssertEqual(s.document.sequence.spine.count, 2)
        s.undo(); XCTAssertEqual(s.document.sequence.spine.count, 1)
        s.undo(); XCTAssertEqual(s.document.sequence.spine.count, 0)
        XCTAssertFalse(s.canUndo)
    }

    func testNewEditClearsRedo() {
        let s = store()
        s.dispatch(.insertClip(clip(2), at: 0))
        s.undo()
        XCTAssertTrue(s.canRedo)
        s.dispatch(.insertClip(clip(1), at: 0))   // 新编辑清空重做栈
        XCTAssertFalse(s.canRedo)
    }
}
