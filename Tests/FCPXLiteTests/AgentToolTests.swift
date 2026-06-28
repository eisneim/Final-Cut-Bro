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
        let out = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        XCTAssertEqual(s.document.sequence.spine.count, 1)
        XCTAssertFalse(out.contains("错误"), out)
    }

    func testInsertAtSeconds() {
        let s = store()
        s.dispatch(.importAsset(videoAsset(2))); s.dispatch(.importAsset(videoAsset(3)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])   // [A(2)]
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 1])   // [A,B]
        _ = r.execute(name: "timeline_edit", args: ["type": "insert", "assetIndex": 0, "atSeconds": 2.0]) // 在2s处插
        XCTAssertEqual(s.document.sequence.spine.count, 3)
    }

    func testBladeViaTool() {
        let s = store(); s.dispatch(.importAsset(videoAsset(6)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        _ = r.execute(name: "timeline_edit", args: ["type": "blade", "clipIndex": 0, "atSeconds": 2.0])
        XCTAssertEqual(s.document.sequence.spine.count, 2)
    }

    func testConnectClipMakesOverlay() {
        let s = store()
        s.dispatch(.importAsset(videoAsset(5))); s.dispatch(.importAsset(videoAsset(2)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        let out = r.execute(name: "timeline_edit", args: ["type": "connect", "assetIndex": 1, "atSeconds": 1.0, "lane": 1])
        let conns = Layout.compute(s.document.sequence).filter { $0.isConnected }
        XCTAssertEqual(conns.count, 1)
        XCTAssertEqual(conns.first?.lane, 1)
        XCTAssertFalse(out.contains("错误"), out)
    }

    func testSetAdjustOpacityScale() {
        let s = store(); s.dispatch(.importAsset(videoAsset(3)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        _ = r.execute(name: "clip_adjust", args: ["type": "opacity", "clipIndex": 0, "value": 0.5])
        _ = r.execute(name: "clip_adjust", args: ["type": "scale", "clipIndex": 0, "value": 0.4])
        guard case .clip(let c) = s.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.adjust.opacity, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.adjust.transform.scale.width, 0.4, accuracy: 1e-6)
    }

    func testDeleteClip() {
        let s = store()
        s.dispatch(.importAsset(videoAsset(2))); s.dispatch(.importAsset(videoAsset(3)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 1])
        _ = r.execute(name: "timeline_edit", args: ["type": "delete", "clipIndex": 0])
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }

    func testTimelineSummaryReflectsState() {
        let s = store(); s.dispatch(.importAsset(videoAsset(3, "truck.mov")))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        let summary = r.execute(name: "query_timeline", args: [:])
        XCTAssertTrue(summary.contains("truck.mov"))
        XCTAssertTrue(summary.contains("素材库(1)"))
    }

    func testToolsJSONShape() {
        let r = AgentToolRegistry(store: store())
        let tools = r.toolsJSON()
        XCTAssertEqual(tools.count, 4)
        let first = tools[0]
        XCTAssertEqual(first["type"] as? String, "function")
        XCTAssertNotNil((first["function"] as? [String: Any])?["name"])
    }

    func testUndoRedoViaTool() {
        let s = store(); s.dispatch(.importAsset(videoAsset(2)))
        let r = AgentToolRegistry(store: s)
        _ = r.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        _ = r.execute(name: "navigate", args: ["type": "undo"])
        XCTAssertEqual(s.document.sequence.spine.count, 0)
        _ = r.execute(name: "navigate", args: ["type": "redo"])
        XCTAssertEqual(s.document.sequence.spine.count, 1)
    }
}
