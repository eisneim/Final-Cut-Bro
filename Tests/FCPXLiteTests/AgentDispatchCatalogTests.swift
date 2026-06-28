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
}
