import XCTest
@testable import FCPXLite

/// Inspector 跟随【最后选择的对象】切换聚焦(FCP 行为):点素材→.asset,点片段→.clip,建/选项目→.project。
@MainActor
final class InspectorFocusTests: XCTestCase {

    private func store() -> DocumentStore {
        DocumentStore(document: Document(formatWidth: 720, formatHeight: 1280, frameRate: 25,
                                         assetLibrary: [], sequence: Sequence(spine: [])))
    }
    private func vAsset() -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v.mov"), kind: .video,
              duration: .seconds(5), naturalSize: CGSize(width: 720, height: 1280), frameRate: 30, hasAudio: true)
    }

    func testFocusFollowsLastSelection() {
        let s = store()
        let a = vAsset()
        s.dispatch(.importAsset(a))
        s.dispatch(.insertClip(Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5)), at: 0))
        guard case .clip(let c) = s.document.sequence.spine[0] else { return XCTFail() }

        // 建项目 → .project
        s.dispatch(.createProject(Project(name: "P", formatWidth: 720, formatHeight: 1280, frameRate: 25)))
        XCTAssertEqual(s.ui.inspectorFocus, .project)

        // 点素材 → .asset
        s.dispatch(.selectAsset(a.id))
        XCTAssertEqual(s.ui.inspectorFocus, .asset)
        XCTAssertEqual(s.selectedAsset()?.id, a.id)

        // 点时间轴片段 → .clip
        s.dispatch(.selectClip(c.id))
        XCTAssertEqual(s.ui.inspectorFocus, .clip)

        // 再点素材 → 回到 .asset(最后选择胜出)
        s.dispatch(.toggleAssetSelected(a.id))
        XCTAssertEqual(s.ui.inspectorFocus, .asset)
    }

    /// 选中素材后能取到 meta(分辨率/帧率来自 Asset)。
    func testSelectedAssetMeta() {
        let s = store()
        let a = vAsset()
        s.dispatch(.importAsset(a))
        s.dispatch(.selectAsset(a.id))
        let sel = s.selectedAsset()
        XCTAssertEqual(sel?.naturalSize.width, 720)
        XCTAssertEqual(sel?.naturalSize.height, 1280)
        XCTAssertEqual(sel?.frameRate, 30)
    }
}
