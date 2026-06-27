import XCTest
@testable import FCPXLite

final class PlayStateTests: XCTestCase {
    private func makeStore() -> DocumentStore {
        DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
    }

    func testTogglePlayFlips() {
        let s = makeStore()
        XCTAssertFalse(s.ui.isPlaying)
        s.dispatch(.togglePlay); XCTAssertTrue(s.ui.isPlaying)
        s.dispatch(.togglePlay); XCTAssertFalse(s.ui.isPlaying)
    }

    func testSetPlaying() {
        let s = makeStore()
        s.dispatch(.setPlaying(true)); XCTAssertTrue(s.ui.isPlaying)
        s.dispatch(.setPlaying(false)); XCTAssertFalse(s.ui.isPlaying)
    }

    func testUIStateCodableWithIsPlaying() throws {
        var ui = UIState(); ui.isPlaying = true
        let data = try JSONEncoder().encode(ui)
        let back = try JSONDecoder().decode(UIState.self, from: data)
        XCTAssertEqual(ui, back)
        XCTAssertTrue(back.isPlaying)
    }

    func testAppendSelectedUsesFirstAssetWhenNoneSelected() {
        let s = makeStore()
        let asset = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"),
                          kind: .video, duration: .seconds(3),
                          naturalSize: CGSize(width: 1920, height: 1080),
                          frameRate: 25, hasAudio: true)
        s.dispatch(.importAsset(asset))
        s.appendSelected()
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }
}
