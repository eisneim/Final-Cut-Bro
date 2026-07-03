import XCTest
@testable import FCPXLite

/// 素材池右键「以此素材新建项目」:项目格式继承素材的分辨率/帧率(竖屏→竖屏),宽高取偶,帧率缺失回退 25。
@MainActor
final class CreateProjectFromAssetTests: XCTestCase {

    private func emptyStore() -> DocumentStore {
        DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                         assetLibrary: [], sequence: Sequence(spine: [])))
    }

    func testInheritsPortraitResolutionAndFps() {
        let store = emptyStore()
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/vertical.mp4"), kind: .video,
                      duration: .seconds(5), naturalSize: CGSize(width: 720, height: 1280),
                      frameRate: 30, hasAudio: true)
        store.createProject(fromAsset: a)
        let p = store.document.projects.last!
        XCTAssertEqual(p.formatWidth, 720)
        XCTAssertEqual(p.formatHeight, 1280)
        XCTAssertEqual(p.frameRate, 30, accuracy: 0.001)
        XCTAssertEqual(p.name, "vertical")
        XCTAssertEqual(store.document.currentProjectID, p.id, "新建后切到该项目")
        // 素材应已放到主轴上,不必手动加轨道。
        XCTAssertEqual(p.sequence.spine.count, 1)
        guard case .clip(let c) = p.sequence.spine[0] else { return XCTFail("主轴应有一个 clip") }
        XCTAssertEqual(c.assetID, a.id)
        XCTAssertEqual(c.duration.seconds, 5, accuracy: 0.001, "clip 时长 = 素材时长")
        XCTAssertEqual(store.ui.playhead.seconds, 0, accuracy: 0.001, "播放头回到 0")
    }

    func testOddDimensionsRoundedToEven() {
        let store = emptyStore()
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/odd.mp4"), kind: .video,
                      duration: .seconds(5), naturalSize: CGSize(width: 1921, height: 1081),
                      frameRate: nil, hasAudio: false)
        store.createProject(fromAsset: a)
        let p = store.document.projects.last!
        XCTAssertEqual(p.formatWidth % 2, 0, "宽必须偶数")
        XCTAssertEqual(p.formatHeight % 2, 0, "高必须偶数")
        XCTAssertEqual(p.formatWidth, 1920)
        XCTAssertEqual(p.formatHeight, 1080)
        XCTAssertEqual(p.frameRate, 25, accuracy: 0.001, "帧率缺失回退 25")
    }
}
