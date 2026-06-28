import XCTest
@testable import FCPXLite

@MainActor
final class SetEffectsTests: XCTestCase {
    private func store1Clip() -> (DocumentStore, ClipID) {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v.mov"), kind: .video,
                      duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(10))
        let s = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                 assetLibrary: [a], sequence: Sequence(spine: [.clip(clip)])))
        return (s, clip.id)
    }

    func testSetEffectsOnSpineClip() {
        let (store, id) = store1Clip()
        store.dispatch(.setEffects(id, [Effect.make(.color)]))
        guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.effects.count, 1)
        XCTAssertEqual(c.effects[0].kind, .color)
    }

    func testSetEffectsUndoable() {
        let (store, id) = store1Clip()
        store.dispatch(.setEffects(id, [Effect.make(.blur)]))
        store.undo()
        guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.effects.count, 0)
    }

    func testToggleEnabledFlipsAndUndoes() {
        let (store, id) = store1Clip()
        store.dispatch(.selectClip(id))
        XCTAssertTrue(store.selectedClip()?.enabled ?? false)
        store.toggleSelectedEnabled()
        XCTAssertEqual(store.selectedClip()?.enabled, false)
        store.toggleSelectedEnabled()
        XCTAssertEqual(store.selectedClip()?.enabled, true)
        store.undo()
        XCTAssertEqual(store.selectedClip()?.enabled, false)
    }

    func testUpdateSelectedEffectsAddsAndPersists() {
        let (store, id) = store1Clip()
        store.dispatch(.selectClip(id))
        store.updateSelectedEffects { $0.append(Effect.make(.color)) }
        guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.effects.count, 1)
    }
}
