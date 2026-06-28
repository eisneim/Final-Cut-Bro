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
}
