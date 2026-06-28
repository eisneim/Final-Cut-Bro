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
}
