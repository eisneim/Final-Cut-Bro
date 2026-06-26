import XCTest
@testable import FCPXLite

final class DispatchTests: XCTestCase {

    // MARK: - Helpers

    private func emptyStore() -> DocumentStore {
        DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
    }

    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    // MARK: - Tests

    func testDispatchInsertMutatesDocument() {
        let store = emptyStore()
        let c = clip(2)
        store.dispatch(.insertClip(c, at: 0))
        XCTAssertEqual(store.document.sequence.spine.count, 1)
    }

    func testDispatchRippleDeleteCollapses() {
        // doc with [A(2s), B(3s), C(1s)]; delete B at index 1
        let store = emptyStore()
        store.dispatch(.insertClip(clip(2), at: 0))  // A at 0
        store.dispatch(.insertClip(clip(3), at: 1))  // B at 1
        store.dispatch(.insertClip(clip(1), at: 2))  // C at 2
        store.dispatch(.rippleDelete(at: 1))          // remove B

        let placed = Layout.compute(store.document.sequence)
        XCTAssertEqual(placed.count, 2)
        // A starts at 0, C ripples to 2 (right after A)
        XCTAssertEqual(placed.map(\.absStart), [.seconds(0), .seconds(2)])
    }

    func testDispatchSequenceOfActions() {
        // insert clip(4s) at 0, trimRight to 3s, then blade at localTime=1s
        // expected: spine has 2 clips after blade → [0s..1s, 1s..2s] (left=1s, right=2s)
        let store = emptyStore()
        let assetDur = Time.seconds(10)
        store.dispatch(.insertClip(clip(4), at: 0))
        store.dispatch(.trimRight(at: 0, newDuration: .seconds(3), assetDuration: assetDur))
        store.dispatch(.blade(at: 0, localTime: .seconds(1)))

        XCTAssertEqual(store.document.sequence.spine.count, 2)
        let placed = Layout.compute(store.document.sequence)
        XCTAssertEqual(placed[0].absStart, .seconds(0))
        XCTAssertEqual(placed[0].duration, .seconds(1))
        XCTAssertEqual(placed[1].absStart, .seconds(1))
        XCTAssertEqual(placed[1].duration, .seconds(2))
    }

    func testEditorActionCodableRoundTrip() throws {
        let c = clip(5)
        let action1 = EditorAction.insertClip(c, at: 2)
        let action2 = EditorAction.trimRight(at: 1, newDuration: Time.seconds(3), assetDuration: Time.seconds(10))

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data1 = try encoder.encode(action1)
        let decoded1 = try decoder.decode(EditorAction.self, from: data1)
        XCTAssertEqual(decoded1, action1)

        let data2 = try encoder.encode(action2)
        let decoded2 = try decoder.decode(EditorAction.self, from: data2)
        XCTAssertEqual(decoded2, action2)
    }
}
