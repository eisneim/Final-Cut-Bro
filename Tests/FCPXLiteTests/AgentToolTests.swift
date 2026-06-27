import XCTest
@testable import FCPXLite

@MainActor
final class AgentToolTests: XCTestCase {
    private func store() -> DocumentStore {
        DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                         assetLibrary: [], sequence: Sequence(spine: [])))
    }
    private func videoAsset(_ s: Double, _ name: String = "a.mov") -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/\(name)"), kind: .video,
              duration: .seconds(s), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }

    func testAppendAndCount() {
        let s = store(); s.dispatch(.importAsset(videoAsset(3)))
        let r = AgentToolRegistry(store: s)
        let out = r.execute(name: "append_clip", args: ["assetIndex": 0])
        XCTAssertEqual(s.document.sequence.spine.count, 1)
        XCTAssertTrue(out.contains("1 个片段"))
    }

    func testInsertAtSeconds() {
        let s = store()
        s.dispatch(.importAsset(videoAsset(2))); s.dispatch(.importAsset(videoAsset(3)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "append_clip", args: ["assetIndex": 0])   // [A(2)]
        _ = r.execute(name: "append_clip", args: ["assetIndex": 1])   // [A,B]
        _ = r.execute(name: "insert_clip", args: ["assetIndex": 0, "atSeconds": 2.0]) // 在2s处插
        XCTAssertEqual(s.document.sequence.spine.count, 3)
    }

    func testBladeViaTool() {
        let s = store(); s.dispatch(.importAsset(videoAsset(6)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "append_clip", args: ["assetIndex": 0])
        _ = r.execute(name: "blade_clip", args: ["atSeconds": 2.0])
        XCTAssertEqual(s.document.sequence.spine.count, 2)
    }

    func testConnectClipMakesOverlay() {
        let s = store()
        s.dispatch(.importAsset(videoAsset(5))); s.dispatch(.importAsset(videoAsset(2)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "append_clip", args: ["assetIndex": 0])
        let out = r.execute(name: "connect_clip", args: ["assetIndex": 1, "atSeconds": 1.0, "lane": 1])
        let conns = Layout.compute(s.document.sequence).filter { $0.isConnected }
        XCTAssertEqual(conns.count, 1)
        XCTAssertEqual(conns.first?.lane, 1)
        XCTAssertTrue(out.contains("叠加"))
    }

    func testSetAdjustOpacityScale() {
        let s = store(); s.dispatch(.importAsset(videoAsset(3)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "append_clip", args: ["assetIndex": 0])
        _ = r.execute(name: "set_adjust", args: ["spineIndex": 0, "opacity": 0.5, "scale": 0.4])
        guard case .clip(let c) = s.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.adjust.opacity, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.adjust.transform.scale.width, 0.4, accuracy: 1e-6)
    }

    func testDeleteClip() {
        let s = store()
        s.dispatch(.importAsset(videoAsset(2))); s.dispatch(.importAsset(videoAsset(3)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "append_clip", args: ["assetIndex": 0])
        _ = r.execute(name: "append_clip", args: ["assetIndex": 1])
        _ = r.execute(name: "delete_clip", args: ["spineIndex": 0])
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }

    func testTimelineSummaryReflectsState() {
        let s = store(); s.dispatch(.importAsset(videoAsset(3, "truck.mov")))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "append_clip", args: ["assetIndex": 0])
        let summary = r.execute(name: "get_timeline", args: [:])
        XCTAssertTrue(summary.contains("truck.mov"))
        XCTAssertTrue(summary.contains("素材库(1)"))
    }

    func testToolsJSONShape() {
        let r = AgentToolRegistry(store: store())
        let tools = r.toolsJSON()
        XCTAssertGreaterThan(tools.count, 8)
        let first = tools[0]
        XCTAssertEqual(first["type"] as? String, "function")
        XCTAssertNotNil((first["function"] as? [String: Any])?["name"])
    }

    func testUndoRedoViaTool() {
        let s = store(); s.dispatch(.importAsset(videoAsset(2)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "append_clip", args: ["assetIndex": 0])
        _ = r.execute(name: "undo", args: [:])
        XCTAssertEqual(s.document.sequence.spine.count, 0)
        _ = r.execute(name: "redo", args: [:])
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }
}
