import XCTest
@testable import FCPXLite

final class ImportActionTests: XCTestCase {

    private func emptyStore() -> DocumentStore {
        DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
    }

    private func sampleAsset() -> Asset {
        Asset(
            id: AssetID(),
            url: URL(fileURLWithPath: "/tmp/sample.mp4"),
            kind: .video,
            duration: .seconds(10),
            naturalSize: CGSize(width: 1920, height: 1080),
            frameRate: 25.0,
            hasAudio: true
        )
    }

    func testImportAssetAppendsToLibrary() {
        let store = emptyStore()
        XCTAssertEqual(store.document.assetLibrary.count, 0)

        let asset = sampleAsset()
        store.dispatch(.importAsset(asset))
        XCTAssertEqual(store.document.assetLibrary.count, 1)
        XCTAssertEqual(store.document.assetLibrary[0].id, asset.id)
    }

    func testImportAssetMultipleTimes() {
        let store = emptyStore()
        let a1 = sampleAsset()
        let a2 = sampleAsset()
        store.dispatch(.importAsset(a1))
        store.dispatch(.importAsset(a2))
        XCTAssertEqual(store.document.assetLibrary.count, 2)
    }

    func testSelectClipSetsSelectedClipID() {
        let store = emptyStore()
        let clipID = ClipID()
        XCTAssertNil(store.ui.selectedClipID)

        store.dispatch(.selectClip(clipID))
        XCTAssertEqual(store.ui.selectedClipID, clipID)
    }

    func testSelectClipNilClearsSelection() {
        let store = emptyStore()
        let clipID = ClipID()
        store.dispatch(.selectClip(clipID))
        XCTAssertNotNil(store.ui.selectedClipID)

        store.dispatch(.selectClip(nil))
        XCTAssertNil(store.ui.selectedClipID)
    }

    func testImportAssetCodableRoundTrip() throws {
        let asset = sampleAsset()
        let action = EditorAction.importAsset(asset)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(EditorAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    func testSelectClipCodableRoundTrip() throws {
        let clipID = ClipID()
        let action = EditorAction.selectClip(clipID)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(EditorAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }

    func testSelectClipNilCodableRoundTrip() throws {
        let action = EditorAction.selectClip(nil)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(EditorAction.self, from: data)
        XCTAssertEqual(decoded, action)
    }
}
