# Multi-Select Asset Pool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add FCP-style multi-select to the asset pool browser (Cmd-click, Shift-range, Cmd-A) with batch add to timeline via E key.

**Architecture:** Add `selectedAssetIDs: Set<AssetID>` to `UIState` alongside the existing `selectedAssetID` anchor. Wire four new `EditorAction` cases (toggleAssetSelected, selectAssetRange, selectAllAssets, clearAssetSelection) through `DocumentStore.dispatch`. Update `BrowserView` to read modifier keys on tap and highlight based on the Set. Add `appendAllSelected()` to `DocumentStore` and route E key through it.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (NSEvent.modifierFlags for modifier keys), SwiftPM.

## Global Constraints

- Files must stay under 500 lines; split if exceeded.
- Fail-fast: no silent fallbacks in new code paths.
- `EditorAction` must remain `Codable` and `Equatable` — no `Set<AssetID>` in action cases (single-AssetID params only; selectAll/clear take none).
- Existing 213 tests must stay green.
- Chinese comments matching existing code style.
- `AssetID` is `Hashable, Codable` — safe in `Set<AssetID>` in `UIState`.
- `UIState` is `Codable, Equatable` — `Set<AssetID>` satisfies both.

---

### Task 1: UIState + EditorAction — multi-select state and actions

**Files:**
- Modify: `Sources/FCPXLite/Store/UIState.swift`
- Modify: `Sources/FCPXLite/Store/EditorAction.swift`

**Interfaces:**
- Produces: `UIState.selectedAssetIDs: Set<AssetID>` (new field, default `[]`)
- Produces: `EditorAction.toggleAssetSelected(AssetID)`, `.selectAssetRange(AssetID)`, `.selectAllAssets`, `.clearAssetSelection`
- Existing `EditorAction.selectAsset(AssetID?)` kept unchanged (single-select / anchor).

- [ ] **Step 1: Add `selectedAssetIDs` to `UIState`**

In `Sources/FCPXLite/Store/UIState.swift`, add one line after `var selectedAssetID: AssetID? = nil`:

```swift
var selectedAssetIDs: Set<AssetID> = []   // 多选集合;selectedAssetID 作为 anchor
```

- [ ] **Step 2: Add four new cases to `EditorAction`**

In `Sources/FCPXLite/Store/EditorAction.swift`, add after the `case selectAsset(AssetID?)` line:

```swift
case toggleAssetSelected(AssetID)   // ⌘-click:加入/移出多选集
case selectAssetRange(AssetID)       // ⇧-click:从 anchor 到此 inclusive 区间选中
case selectAllAssets                 // ⌘A:选中素材库全部
case clearAssetSelection             // 清除多选
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!` (dispatch has a default/switch exhaustion warning for the new cases, but no error — Swift doesn't error for missing switch arms in a func that has a `default` or exhaustive catch-all). Actually Swift WILL error if the switch is exhaustive without default. Proceed to Task 2 immediately to add dispatch arms; do not linger here if there are "non-exhaustive switch" errors.

---

### Task 2: Wire new actions into DocumentStore.dispatch

**Files:**
- Modify: `Sources/FCPXLite/Store/DocumentStore.swift`

**Interfaces:**
- Consumes: `UIState.selectedAssetIDs: Set<AssetID>`, `UIState.selectedAssetID: AssetID?` (anchor)
- Consumes: `document.assetLibrary: [Asset]` (ordered, used for range-select)
- Produces: `DocumentStore.appendAllSelected()` — appends each asset in `selectedAssetIDs` (in assetLibrary order) to spine end

- [ ] **Step 1: Add dispatch arms for the four new actions**

In `DocumentStore.dispatch(_:)`, inside the `switch action {` block, add these four cases before the closing `}`. Find the line `case let .selectAsset(id): ui.selectedAssetID = id` and add the new cases immediately after it:

```swift
case let .toggleAssetSelected(id):
    // ⌘-click:切换单个素材的选中状态;anchor 更新到该素材
    if ui.selectedAssetIDs.contains(id) {
        ui.selectedAssetIDs.remove(id)
    } else {
        ui.selectedAssetIDs.insert(id)
        ui.selectedAssetID = id   // 更新 anchor
    }
case let .selectAssetRange(id):
    // ⇧-click:从 anchor 到 id 在 assetLibrary 顺序中选中区间
    let ids = document.assetLibrary.map(\.id)
    guard let toIdx = ids.firstIndex(of: id) else { break }
    let fromIdx = ui.selectedAssetID.flatMap { ids.firstIndex(of: $0) } ?? toIdx
    let lo = min(fromIdx, toIdx)
    let hi = max(fromIdx, toIdx)
    for i in lo...hi { ui.selectedAssetIDs.insert(ids[i]) }
    // anchor 不变(FCP 行为:Shift 不移动 anchor)
case .selectAllAssets:
    // ⌘A:选中全部素材(不影响时间轴选中)
    ui.selectedAssetIDs = Set(document.assetLibrary.map(\.id))
    ui.selectedAssetID = document.assetLibrary.last?.id   // anchor 设为最后一个
case .clearAssetSelection:
    ui.selectedAssetIDs = []
    ui.selectedAssetID = nil
```

- [ ] **Step 2: Update the existing `selectAsset` arm to also update `selectedAssetIDs`**

Find the line:
```swift
case let .selectAsset(id):               ui.selectedAssetID = id
```
Replace it with:
```swift
case let .selectAsset(id):
    // 单选:清除多选集,只保留这一个(同时更新 anchor)
    ui.selectedAssetID = id
    ui.selectedAssetIDs = id.map { [$0] } ?? []
```

- [ ] **Step 3: Add `appendAllSelected()` method**

In `DocumentStore`, after the `appendSelected()` method (around line 193), add:

```swift
/// 批量追加多选素材到主轴末尾(按 assetLibrary 顺序)。
func appendAllSelected() {
    let ordered = document.assetLibrary.filter { ui.selectedAssetIDs.contains($0.id) }
    for asset in ordered {
        dispatch(.insertClip(
            Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration),
            at: document.sequence.spine.count
        ))
    }
}
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

---

### Task 3: BrowserView — modifier-aware tap + multi-select highlight

**Files:**
- Modify: `Sources/FCPXLite/Views/BrowserView.swift`

**Interfaces:**
- Consumes: `store.ui.selectedAssetIDs: Set<AssetID>` for highlight
- Consumes: `NSEvent.modifierFlags` (AppKit, already imported via `import AppKit`)
- Dispatches: `.selectAsset(asset.id)`, `.toggleAssetSelected(asset.id)`, `.selectAssetRange(asset.id)`

- [ ] **Step 1: Replace the `assetGrid` computed property**

Find the `assetGrid` computed property (lines 67–88). Replace the entire `.onTapGesture` + `.overlay` block inside the `ForEach`. The new `ForEach` body should be:

```swift
ForEach(store.document.assetLibrary) { asset in
    AssetCardView(asset: asset)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    // 多选集或 anchor 选中时高亮
                    store.ui.selectedAssetIDs.contains(asset.id)
                        ? Tokens.Palette.selectYellow
                        : Color.clear,
                    lineWidth: 1.5
                )
        )
        .onTapGesture {
            // 读当前 NSEvent 修饰键:⌘=多选切换,⇧=区间,否则单选
            let mods = NSEvent.modifierFlags
            if mods.contains(.command) {
                store.dispatch(.toggleAssetSelected(asset.id))
            } else if mods.contains(.shift) {
                store.dispatch(.selectAssetRange(asset.id))
            } else {
                store.dispatch(.selectAsset(asset.id))
            }
        }
}
```

Note: The old highlight was `store.ui.selectedAssetID == asset.id`. The new one uses `selectedAssetIDs` which already includes the anchor after `selectAsset` now populates both fields.

- [ ] **Step 2: Verify build**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

---

### Task 4: AppDelegate — Cmd-A select all + E key batch append

**Files:**
- Modify: `Sources/FCPXLite/AppDelegate.swift`

**Interfaces:**
- Consumes: `store.dispatch(.selectAllAssets)` (new action)
- Consumes: `store.appendAllSelected()` (new method)
- Consumes: `store.ui.selectedAssetIDs.count` to decide single vs. batch

- [ ] **Step 1: Add Cmd-A case to the keyboard monitor**

In `installKeyboardShortcuts()`, find the `if hasCmd && !hasOptCtrl { switch ... }` block. Add the `"a"` case before `default`:

```swift
case "a":      store.dispatch(.selectAllAssets); return nil
```

The full switch block for Cmd combos should now be:
```swift
if hasCmd && !hasOptCtrl {
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "=", "+": store.dispatch(.setZoom(store.ui.pxPerSecond * 1.5)); return nil
    case "-":      store.dispatch(.setZoom(store.ui.pxPerSecond / 1.5)); return nil
    case "b":      store.bladeAtPlayhead(); return nil
    case "i":      ImportPanel.present(into: store); return nil
    case "z":      mods.contains(.shift) ? store.redo() : store.undo(); return nil
    case "a":      store.dispatch(.selectAllAssets); return nil
    default:       return event
    }
}
```

Note: The guard `if self.isEditingText { return event }` at the top of the monitor already fires before this block, so Cmd-A in a text field will NOT reach this code — the text field gets it naturally.

- [ ] **Step 2: Update the `"e"` key handler to use batch append**

Find the line:
```swift
case "e": store.appendSelected(); return nil
```
Replace with:
```swift
case "e":
    // 多选时批量追加;单/零选时走原路径
    if store.ui.selectedAssetIDs.count > 1 {
        store.appendAllSelected()
    } else {
        store.appendSelected()
    }
    return nil
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

---

### Task 5: Tests for multi-select

**Files:**
- Create: `Tests/FCPXLiteTests/MultiSelectTests.swift`

**Interfaces:**
- Consumes: `DocumentStore(document:)` with `Document(assetLibrary:projects:currentProjectID:)`
- Consumes: `Asset(id:url:kind:duration:naturalSize:frameRate:hasAudio:)` for creating test assets
- Consumes: `store.dispatch(.selectAsset(...))`, `.toggleAssetSelected(...)`, `.selectAssetRange(...)`, `.selectAllAssets`, `.clearAssetSelection`
- Consumes: `store.appendAllSelected()`
- Checks: `store.ui.selectedAssetIDs`, `store.document.sequence.spine.count`

- [ ] **Step 1: Create the test file**

Create `Tests/FCPXLiteTests/MultiSelectTests.swift`:

```swift
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
```

- [ ] **Step 2: Run all tests**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -5
```

Expected output ends with: `Test Suite 'All tests' passed` (or similar with all passing). The new `MultiSelectTests` adds ≥9 tests; total should be 213 + 9 = 222+.

---

### Task 6: Final build+test verification + commit

**Files:**
- No new file changes

- [ ] **Step 1: Full build check**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 2: Full test suite**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -2
```

Expected: `Executed N tests, with 0 failures`

- [ ] **Step 3: Write report**

Create report file at `/Users/teli/www/video_editing_related/FCPX_lite/.superpowers/sdd/multiselect-report.md` with:
- Status (pass/fail)
- Commit hash
- One-line build+test summary
- Any concerns

- [ ] **Step 4: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && git add -A && git commit -m "feat(browser): 素材池多选(Cmd逐个/Shift区间/⌘A全选)+批量加到时间轴(E键)"
```

Expected: commit created on branch `feat/agent-integration`.
