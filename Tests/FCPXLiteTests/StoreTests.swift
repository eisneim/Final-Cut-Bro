import XCTest
@testable import FCPXLite

final class StoreTests: XCTestCase {
    func testApplyMutatesDocument() {
        let store = DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        store.apply { Mutations.insertClip(clip, at: 0, in: $0) }
        XCTAssertEqual(store.document.sequence.spine.count, 1)
    }
}
