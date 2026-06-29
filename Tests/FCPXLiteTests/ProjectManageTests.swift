import XCTest
@testable import FCPXLite

/// T4:项目删除 / 重命名。
@MainActor
final class ProjectManageTests: XCTestCase {
    private func storeWith(_ projects: [Project], current: ProjectID?) -> DocumentStore {
        DocumentStore(document: Document(assetLibrary: [], projects: projects, currentProjectID: current))
    }

    func testRenameProject() {
        let a = Project(name: "旧名", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let s = storeWith([a], current: a.id)
        s.dispatch(.renameProject(a.id, "新名字"))
        XCTAssertEqual(s.document.projects[0].name, "新名字")
    }

    func testRenameEmptyIsIgnored() {
        let a = Project(name: "保留", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let s = storeWith([a], current: a.id)
        s.dispatch(.renameProject(a.id, "   "))   // 全空白
        XCTAssertEqual(s.document.projects[0].name, "保留")
    }

    func testRenameTrimsWhitespace() {
        let a = Project(name: "x", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let s = storeWith([a], current: a.id)
        s.dispatch(.renameProject(a.id, "  片头  "))
        XCTAssertEqual(s.document.projects[0].name, "片头")
    }

    func testRemoveNonCurrentProjectKeepsCurrent() {
        let a = Project(name: "A", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let b = Project(name: "B", formatWidth: 1080, formatHeight: 1920, frameRate: 30)
        let s = storeWith([a, b], current: a.id)
        s.dispatch(.removeProject(b.id))
        XCTAssertEqual(s.document.projects.count, 1)
        XCTAssertEqual(s.document.currentProjectID, a.id, "删非当前项目,当前不变")
    }

    func testRemoveCurrentProjectSwitchesToFirstRemaining() {
        let a = Project(name: "A", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let b = Project(name: "B", formatWidth: 1080, formatHeight: 1920, frameRate: 30)
        let s = storeWith([a, b], current: a.id)
        s.dispatch(.removeProject(a.id))   // 删当前
        XCTAssertEqual(s.document.projects.count, 1)
        XCTAssertEqual(s.document.currentProjectID, b.id, "删当前项目 → 切到剩下第一个")
        XCTAssertTrue(s.document.hasProject)
    }

    func testRemoveLastProjectFallsBackToNoProjectGate() {
        let a = Project(name: "A", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let s = storeWith([a], current: a.id)
        s.dispatch(.removeProject(a.id))
        XCTAssertEqual(s.document.projects.count, 0)
        XCTAssertNil(s.document.currentProjectID)
        XCTAssertFalse(s.document.hasProject, "删光 → 回到无项目门控")
    }

    func testRemoveProjectIsUndoable() {
        let a = Project(name: "A", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let b = Project(name: "B", formatWidth: 1080, formatHeight: 1920, frameRate: 30)
        let s = storeWith([a, b], current: a.id)
        s.dispatch(.removeProject(b.id))
        XCTAssertEqual(s.document.projects.count, 1)
        s.undo()
        XCTAssertEqual(s.document.projects.count, 2, "删除可撤销")
    }
}
