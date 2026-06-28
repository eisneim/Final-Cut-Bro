import XCTest
@testable import FCPXLite

final class UIStateTests: XCTestCase {

    // MARK: - Helpers

    private func emptyStore() -> DocumentStore {
        DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
    }

    // MARK: - Tests

    func testDispatchSetInspector() {
        let store = emptyStore()
        store.dispatch(.setInspector(true))
        XCTAssertTrue(store.ui.showInspector)
        store.dispatch(.setInspector(false))
        XCTAssertFalse(store.ui.showInspector)
    }

    func testDispatchSetEffects() {
        let store = emptyStore()
        store.dispatch(.setShowEffects(true))
        XCTAssertTrue(store.ui.showEffects)
        store.dispatch(.setShowEffects(false))
        XCTAssertFalse(store.ui.showEffects)
    }

    func testUIActionsCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let action1 = EditorAction.setInspector(true)
        let data1 = try encoder.encode(action1)
        let decoded1 = try decoder.decode(EditorAction.self, from: data1)
        XCTAssertEqual(decoded1, action1)

        let action2 = EditorAction.setShowEffects(false)
        let data2 = try encoder.encode(action2)
        let decoded2 = try decoder.decode(EditorAction.self, from: data2)
        XCTAssertEqual(decoded2, action2)
    }

    func testUIStateCodableRoundTrip() throws {
        let original = UIState(showInspector: true, showEffects: true)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UIState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
