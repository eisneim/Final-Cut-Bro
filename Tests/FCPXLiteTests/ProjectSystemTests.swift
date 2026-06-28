import XCTest
@testable import FCPXLite

@MainActor
final class ProjectSystemTests: XCTestCase {
    private func emptyStore() -> DocumentStore {
        DocumentStore(document: Document(assetLibrary: [], projects: [], currentProjectID: nil))
    }

    func testStartsWithNoProject() {
        let s = emptyStore()
        XCTAssertFalse(s.document.hasProject)
        XCTAssertEqual(s.document.sequence.spine.count, 0)   // 无项目 → 空时间线
    }

    func testCreateProjectMakesTimelineEditable() {
        let s = emptyStore()
        let p = Project(name: "测试", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        s.dispatch(.createProject(p))
        XCTAssertTrue(s.document.hasProject)
        XCTAssertEqual(s.document.currentProjectID, p.id)
        XCTAssertEqual(s.document.formatWidth, 1920)
        // 现在能编辑时间线(proxy 写到当前项目)
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5))
        s.dispatch(.insertClip(clip, at: 0))
        XCTAssertEqual(s.document.sequence.spine.count, 1)
        XCTAssertEqual(s.document.projects[0].sequence.spine.count, 1)
    }

    func testSwitchingProjectSwapsTimeline() {
        let s = emptyStore()
        let a = Project(name: "A", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let b = Project(name: "B", formatWidth: 1080, formatHeight: 1920, frameRate: 30)  // 竖屏
        s.dispatch(.createProject(a))
        s.dispatch(.insertClip(Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3)), at: 0))
        s.dispatch(.createProject(b))   // 切到 B(空)
        XCTAssertEqual(s.document.sequence.spine.count, 0, "B 是空项目")
        XCTAssertEqual(s.document.formatWidth, 1080)
        s.dispatch(.selectProject(a.id))  // 切回 A
        XCTAssertEqual(s.document.sequence.spine.count, 1, "A 的时间线还在")
        XCTAssertEqual(s.document.formatWidth, 1920)
    }

    func testNoProjectEditIsNoOp() {
        let s = emptyStore()
        // 无项目时插入 clip 应静默无效(门控)
        s.dispatch(.insertClip(Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5)), at: 0))
        XCTAssertEqual(s.document.sequence.spine.count, 0)
    }
}
