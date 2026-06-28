import XCTest
@testable import FCPXLite

@MainActor
final class MultiSelectTests: XCTestCase {

    // MARK: - 工厂

    /// 创建4个测试素材 + 一个项目的 store。
    private func makeStore() -> (DocumentStore, [Asset]) {
        let assets = (0..<4).map { i -> Asset in
            Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/clip\(i).mp4"),
                  kind: .video, duration: .seconds(Double(i + 1)),
                  naturalSize: .init(width: 1920, height: 1080),
                  frameRate: 25, hasAudio: false)
        }
        let project = Project(name: "测试项目", formatWidth: 1920, formatHeight: 1080, frameRate: 25)
        let doc = Document(assetLibrary: assets,
                           projects: [project],
                           currentProjectID: project.id)
        return (DocumentStore(document: doc), assets)
    }

    // MARK: - 单选

    func testSingleSelectClearsSet() {
        let (store, assets) = makeStore()
        // 先多选两个
        store.dispatch(.selectAsset(assets[0].id))
        store.dispatch(.toggleAssetSelected(assets[1].id))
        // 再单选第3个 → 集合应只有第3个
        store.dispatch(.selectAsset(assets[2].id))
        XCTAssertEqual(store.ui.selectedAssetIDs, [assets[2].id])
        XCTAssertEqual(store.ui.selectedAssetID, assets[2].id)
    }

    // MARK: - Cmd-click 切换

    func testToggleAddsToSet() {
        let (store, assets) = makeStore()
        store.dispatch(.selectAsset(assets[0].id))       // anchor = 0
        store.dispatch(.toggleAssetSelected(assets[1].id))
        XCTAssertEqual(store.ui.selectedAssetIDs, [assets[0].id, assets[1].id])
    }

    func testToggleRemovesFromSet() {
        let (store, assets) = makeStore()
        store.dispatch(.selectAsset(assets[0].id))
        store.dispatch(.toggleAssetSelected(assets[1].id))
        store.dispatch(.toggleAssetSelected(assets[1].id))   // 再次 → 移除
        XCTAssertEqual(store.ui.selectedAssetIDs, [assets[0].id])
    }

    func testToggleDoesNotMoveAnchorOnRemoval() {
        // anchor 在 toggle 移除时不改变(FCP 行为)
        let (store, assets) = makeStore()
        store.dispatch(.selectAsset(assets[0].id))           // anchor = 0
        store.dispatch(.toggleAssetSelected(assets[1].id))   // add 1, anchor → 1
        store.dispatch(.toggleAssetSelected(assets[1].id))   // remove 1, anchor 仍 = 1
        XCTAssertEqual(store.ui.selectedAssetID, assets[1].id)
    }

    // MARK: - Shift-click 区间

    func testRangeSelectForward() {
        let (store, assets) = makeStore()
        store.dispatch(.selectAsset(assets[0].id))       // anchor = index 0
        store.dispatch(.selectAssetRange(assets[2].id))  // shift-click index 2
        // 应选中 0, 1, 2
        XCTAssertEqual(store.ui.selectedAssetIDs,
                       Set([assets[0].id, assets[1].id, assets[2].id]))
    }

    func testRangeSelectBackward() {
        let (store, assets) = makeStore()
        store.dispatch(.selectAsset(assets[3].id))       // anchor = index 3
        store.dispatch(.selectAssetRange(assets[1].id))  // shift-click index 1
        // 应选中 1, 2, 3
        XCTAssertEqual(store.ui.selectedAssetIDs,
                       Set([assets[1].id, assets[2].id, assets[3].id]))
    }

    func testRangeSelectFromNoAnchor() {
        // 无 anchor 时 Shift-click 只选点击的那一个
        let (store, assets) = makeStore()
        XCTAssertNil(store.ui.selectedAssetID)
        store.dispatch(.selectAssetRange(assets[2].id))
        XCTAssertEqual(store.ui.selectedAssetIDs, [assets[2].id])
    }

    // MARK: - 全选 / 清除

    func testSelectAllSelectsEverything() {
        let (store, assets) = makeStore()
        store.dispatch(.selectAllAssets)
        XCTAssertEqual(store.ui.selectedAssetIDs, Set(assets.map(\.id)))
    }

    func testClearAssetSelectionEmptiesSet() {
        let (store, _) = makeStore()
        store.dispatch(.selectAllAssets)
        store.dispatch(.clearAssetSelection)
        XCTAssertTrue(store.ui.selectedAssetIDs.isEmpty)
        XCTAssertNil(store.ui.selectedAssetID)
    }

    // MARK: - 批量追加

    func testAppendAllSelectedAddsNClips() {
        let (store, assets) = makeStore()
        // 选中前3个素材
        store.dispatch(.selectAsset(assets[0].id))
        store.dispatch(.toggleAssetSelected(assets[1].id))
        store.dispatch(.toggleAssetSelected(assets[2].id))
        XCTAssertEqual(store.ui.selectedAssetIDs.count, 3)

        store.appendAllSelected()

        XCTAssertEqual(store.document.sequence.spine.count, 3)
    }

    func testAppendAllSelectedPreservesAssetLibraryOrder() {
        let (store, assets) = makeStore()
        // 以逆序 dispatch toggle(选中 index 2, 0) — 追加应按 library 顺序(0 先)
        store.dispatch(.selectAsset(assets[2].id))
        store.dispatch(.toggleAssetSelected(assets[0].id))

        store.appendAllSelected()

        let spine = store.document.sequence.spine
        XCTAssertEqual(spine.count, 2)
        // 第一个追加的 clip 应对应 assets[0](index 0 < 2)
        if case .clip(let c) = spine[0] {
            XCTAssertEqual(c.assetID, assets[0].id)
        } else {
            XCTFail("spine[0] is not a clip")
        }
        if case .clip(let c) = spine[1] {
            XCTAssertEqual(c.assetID, assets[2].id)
        } else {
            XCTFail("spine[1] is not a clip")
        }
    }

    func testAppendAllSelectedNoOpWithoutProject() {
        // 无项目时 appendAllSelected 不崩溃,不改变 spine
        let assets = (0..<2).map { i -> Asset in
            Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a\(i).mp4"),
                  kind: .video, duration: .seconds(2),
                  naturalSize: .init(width: 1920, height: 1080),
                  frameRate: 25, hasAudio: false)
        }
        let store = DocumentStore(document: Document(assetLibrary: assets,
                                                      projects: [], currentProjectID: nil))
        store.dispatch(.selectAllAssets)
        store.appendAllSelected()
        XCTAssertEqual(store.document.sequence.spine.count, 0)
    }
}
