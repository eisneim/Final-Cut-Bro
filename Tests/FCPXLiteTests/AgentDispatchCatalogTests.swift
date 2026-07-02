import XCTest
@testable import FCPXLite

@MainActor
final class AgentDispatchCatalogTests: XCTestCase {
    func testCatalogHasDomainsAndLookup() {
        // 三个领域都有动作
        XCTAssertFalse(AgentActionCatalog.actions(in: .timeline).isEmpty)
        XCTAssertFalse(AgentActionCatalog.actions(in: .adjust).isEmpty)
        XCTAssertFalse(AgentActionCatalog.actions(in: .navigate).isEmpty)
        // 按 type 能查到,且 domain 正确
        XCTAssertEqual(AgentActionCatalog.find("insert")?.domain, .timeline)
        XCTAssertEqual(AgentActionCatalog.find("volume")?.domain, .adjust)
        XCTAssertEqual(AgentActionCatalog.find("playhead")?.domain, .navigate)
        XCTAssertNil(AgentActionCatalog.find("nonexistent"))
        // type 唯一
        let types = AgentActionCatalog.all.map { $0.type }
        XCTAssertEqual(types.count, Set(types).count, "action type 必须唯一")
    }

    private func storeWith2Assets() -> DocumentStore {
        let a0 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                       duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let a1 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/b.mov"), kind: .video,
                       duration: .seconds(8), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        return DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                assetLibrary: [a0, a1], sequence: Sequence(spine: [])))
    }
    private func clipCount(_ s: DocumentStore) -> Int {
        s.document.sequence.spine.reduce(0) { if case .clip = $1 { return $0 + 1 }; return $0 }
    }

    private func currentAdjust(_ s: DocumentStore, clipIndex: Int) -> Adjustments? {
        var n = 0
        for el in s.document.sequence.spine {
            if case .clip(let c) = el { if n == clipIndex { return c.adjust }; n += 1 }
        }
        return nil
    }

    func testTimelineAppendInsertDelete() {
        let store = storeWith2Assets()
        // append 第0个素材
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        XCTAssertEqual(clipCount(store), 1)
        // append 第1个素材
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 1])
        XCTAssertEqual(clipCount(store), 2)
        // delete 第0个片段(ripple)
        _ = AgentActionCatalog.find("delete")!.apply(store, ["clipIndex": 0, "ripple": true])
        XCTAssertEqual(clipCount(store), 1)
    }

    func testTimelineConnectMakesOverlay() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        _ = AgentActionCatalog.find("connect")!.apply(store, ["assetIndex": 1, "atSeconds": 1.0, "lane": 1])
        let connected = Layout.compute(store.document.sequence).filter { $0.isConnected }
        XCTAssertEqual(connected.count, 1)
    }

    func testTimelineBladeSplits() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0]) // 10s 片段
        _ = AgentActionCatalog.find("blade")!.apply(store, ["clipIndex": 0, "atSeconds": 4.0])
        XCTAssertEqual(clipCount(store), 2)
    }

    func testTimelineBadIndexReturnsError() {
        let store = storeWith2Assets()
        let r = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 99])
        XCTAssertTrue(r.contains("错误"), "非法 index 应返回错误文本: \(r)")
    }

    // Bug 1: insert mid-clip should land at the index of the element whose range contains `at`
    func testInsertMidClipLandsAtCorrectIndex() {
        // spine: [clip0=10s, clip1=8s]
        // inserting at 7.0s falls inside clip0 (range 0..10), so new clip should go at spine index 0 (before clip0)
        // Wait — per spec: "insert at index of FIRST element whose range contains at"
        // clip0 occupies [0,10), at=7.0 is inside clip0, so idx=0 → new clip inserted AT position 0
        // After insert: [newClip, clip0, clip1]
        // But the more meaningful test for mid-clip is: at=7.0 inside clip0 should NOT land AFTER clip1
        // Use at=7.0: inside clip0 [0,10) → idx=0
        // spine after: index 0 = newClip (asset2 placeholder, but we only have 2 assets)
        // Let's test: append a0 (10s), append a1 (8s), then insert a0 again at atSeconds=7.0
        // Expected: new clip at spine[0], because 7.0 falls inside clip at [0,10)
        // The bug would put it at spine index 2 (end), so we assert spine[0] is the inserted clip

        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0]) // clip0, 10s, spine[0]
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 1]) // clip1, 8s, spine[1]

        // Insert asset 1 at 7.0s — inside clip0 [0,10) — should land at spine index 0
        _ = AgentActionCatalog.find("insert")!.apply(store, ["assetIndex": 1, "atSeconds": 7.0])

        XCTAssertEqual(store.document.sequence.spine.count, 3, "spine should have 3 elements after insert")

        // The inserted clip (asset1, 8s) should be at spine[0]
        // clip0 (asset0, 10s) should now be at spine[1]
        guard case .clip(let insertedClip) = store.document.sequence.spine[0] else {
            XCTFail("spine[0] should be the newly inserted clip")
            return
        }
        guard case .clip(let originalClip0) = store.document.sequence.spine[1] else {
            XCTFail("spine[1] should be the original clip0 (asset0)")
            return
        }
        let assets = store.document.assetLibrary
        XCTAssertEqual(insertedClip.assetID, assets[1].id,
                       "newly inserted clip should be asset1 (8s) at spine[0]")
        XCTAssertEqual(originalClip0.assetID, assets[0].id,
                       "original clip0 (asset0, 10s) should remain at spine[1]")
    }

    // Bug 2: delete with ripple=false (Swift Bool) should leave a gap, not ripple-delete
    func testDeleteRippleFalseLeavesGap() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0]) // clip0
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 1]) // clip1

        // Delete clip0 with ripple=false passed as Swift Bool (JSON boolean)
        _ = AgentActionCatalog.find("delete")!.apply(store, ["clipIndex": 0, "ripple": false])

        // With ripple=false (liftDelete), the spine element count stays 2 (gap replaces clip)
        XCTAssertEqual(store.document.sequence.spine.count, 2,
                       "liftDelete should leave a gap; spine should still have 2 elements")

        // The first element should now be a gap, not a clip
        if case .clip = store.document.sequence.spine[0] {
            XCTFail("spine[0] should be a .gap after ripple=false delete, not a clip")
        }
    }

    func testAdjustScaleVolumeCrop() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0]) // 1920x1080
        // scale 2x
        _ = AgentActionCatalog.find("scale")!.apply(store, ["clipIndex": 0, "value": 2.0])
        XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.transform.scale.width, 2.0)
        // volume 0.2
        _ = AgentActionCatalog.find("volume")!.apply(store, ["clipIndex": 0, "value": 0.2])
        XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.volume ?? 0, 0.2, accuracy: 0.001)
        // crop left 15% → 0.15 * 1920 = 288 px
        _ = AgentActionCatalog.find("crop")!.apply(store, ["clipIndex": 0, "left": 0.15])
        XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.crop.left ?? 0, 288, accuracy: 0.5)
    }

    func testAdjustOpacityAndPosition() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        _ = AgentActionCatalog.find("opacity")!.apply(store, ["clipIndex": 0, "value": 0.5])
        XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.opacity ?? 0, 0.5, accuracy: 0.001)
        _ = AgentActionCatalog.find("position")!.apply(store, ["clipIndex": 0, "x": 100, "y": -50])
        XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.transform.position.x, 100)
        XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.transform.position.y, -50)
    }

    func testNavigatePlayheadZoomToolUndo() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("playhead")!.apply(store, ["atSeconds": 3.0])
        XCTAssertEqual(store.ui.playhead.seconds, 3.0, accuracy: 0.001)
        _ = AgentActionCatalog.find("zoom")!.apply(store, ["pxPerSecond": 120])
        XCTAssertEqual(store.ui.pxPerSecond, 120)
        _ = AgentActionCatalog.find("tool")!.apply(store, ["name": "blade"])
        XCTAssertEqual(store.ui.currentTool, .blade)
        // undo 还原 tool 之前? tool 不进撤销栈;改测一次结构编辑的 undo
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        XCTAssertEqual(clipCount(store), 1)
        _ = AgentActionCatalog.find("undo")!.apply(store, [:])
        XCTAssertEqual(clipCount(store), 0)
    }

    func testNavigateSelect() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        _ = AgentActionCatalog.find("select")!.apply(store, ["clipIndex": 0])
        XCTAssertNotNil(store.ui.selectedClipID)
    }

    func testRegistryExposesSixTools() {
        let store = storeWith2Assets()
        let reg = AgentToolRegistry(store: store)
        let names = Set(reg.tools().map { $0.name })
        XCTAssertEqual(names, ["query_timeline", "timeline_edit", "clip_adjust", "navigate", "file_ops", "shell"])
    }

    func testDispatchToolRoutesToCatalog() {
        let store = storeWith2Assets()
        let reg = AgentToolRegistry(store: store)
        // 通过 timeline_edit 工具发 append
        let r = reg.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
        XCTAssertFalse(r.contains("错误"), r)
        XCTAssertEqual(clipCount(store), 1)
        // query_timeline 返回摘要文本
        let q = reg.execute(name: "query_timeline", args: [:])
        XCTAssertTrue(q.contains("素材库"))
    }

    func testAddAndRemoveEffect() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        _ = AgentActionCatalog.find("add_effect")!.apply(store, ["clipIndex": 0, "kind": "blur"])
        guard case .clip(let c1) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c1.effects.count, 1)
        XCTAssertEqual(c1.effects[0].kind, .blur)
        _ = AgentActionCatalog.find("remove_effect")!.apply(store, ["clipIndex": 0, "effectIndex": 0])
        guard case .clip(let c2) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c2.effects.count, 0)
    }

    func testRemoveEffectBadIndexErrors() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        // 没有任何 effect,删 index 5 → 应明确报错而非假成功
        let r = AgentActionCatalog.find("remove_effect")!.apply(store, ["clipIndex": 0, "effectIndex": 5])
        XCTAssertTrue(r.contains("错误"), r)
        let r2 = AgentActionCatalog.find("set_effect_param")!.apply(store, ["clipIndex": 0, "effectIndex": 5, "key": "radius", "value": 3])
        XCTAssertTrue(r2.contains("错误"), r2)
    }

    func testSetEffectParam() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        _ = AgentActionCatalog.find("add_effect")!.apply(store, ["clipIndex": 0, "kind": "color"])
        _ = AgentActionCatalog.find("set_effect_param")!.apply(store, ["clipIndex": 0, "effectIndex": 0, "key": "brightness", "value": 0.3])
        guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.effects[0].params["brightness"], 0.3)
    }

    func testAddEffectBadKindErrors() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        let r = AgentActionCatalog.find("add_effect")!.apply(store, ["clipIndex": 0, "kind": "nonsense"])
        XCTAssertTrue(r.contains("错误"), r)
    }

    func testToggleEnabled() {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        _ = AgentActionCatalog.find("toggle_enabled")!.apply(store, ["clipIndex": 0, "enabled": false])
        guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertFalse(c.enabled)
    }

    func testExportFCPXMLAction() throws {
        let store = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID().uuidString).fcpxml")
        defer { try? FileManager.default.removeItem(at: out) }
        let r = AgentActionCatalog.find("export_fcpxml")!.apply(store, ["path": out.path])
        XCTAssertFalse(r.contains("错误"), r)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        let content = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(content.contains("<fcpxml"))
    }

    func testExportActionsRegisteredInNavigate() {
        XCTAssertEqual(AgentActionCatalog.find("export_fcpxml")?.domain, .navigate)
        XCTAssertEqual(AgentActionCatalog.find("export_movie")?.domain, .navigate)
    }
}
