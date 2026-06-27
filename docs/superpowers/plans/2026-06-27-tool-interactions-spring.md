# Tool Interactions + Cursors + Spring-Loaded Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-tool mouse-handling branches (select/position/trim/hand/zoom/blade), gap rendering for the position tool, NSCursor feedback, and spring-loaded tool switching (hold = temporary, tap = permanent).

**Architecture:** Four independent deliverables: (1) a new `Mutations.positionMove` + `Mutations.setGapDuration` on the model layer; (2) rewrite of `TimelineContentView+Drag.swift` to branch on `currentTool`; (3) gap rendering inside `TimelineContentView.swift`; (4) a small `SpringToolStateMachine` type in `AppDelegate.swift` (or its own file) that replaces the plain keyDown monitor. All AppKit drawing uses `TimelineColors` (NSColor only), never `Color(hex:)` or SwiftUI colors. Each file must remain ≤ 500 lines after changes; split files that would exceed the limit.

**Tech Stack:** Swift 5.9 / macOS 14 target, AppKit + SwiftUI bridged via NSViewRepresentable, no third-party dependencies. XCTest for unit tests. Swift build system (SPM). DEBUG-only `DebugControlServer` harness on port 8765.

## Global Constraints

- SwiftUI `View` files: zero `Color(hex:)` / `Color.<name>`. Use `Tokens.Palette.*` or system colors. AppKit canvas may use `TimelineColors.*` / `NSColor`.
- Every source file ≤ 500 lines. Split if a change would breach this.
- Keep all 117 existing tests green.
- Add unit tests for every new mutation and the spring state machine.
- No server left running after each self-test. `pkill -f '.build/debug/FCPXLite'` after every test run.
- Fail-fast: no silent try/catch hiding errors in new code.
- Commit after each task in a logical unit.

---

## File Map

### New files
- `Sources/FCPXLite/Store/SpringToolStateMachine.swift` — pure value-type state machine for spring-loaded tool switching. Testable with zero AppKit imports.
- `Tests/FCPXLiteTests/SpringToolTests.swift` — unit tests for state machine.
- `Tests/FCPXLiteTests/PositionMoveTests.swift` — unit tests for `positionMove` and `setGapDuration` mutations.
- `.superpowers/sdd/DE-report.md` — final report (written in Task 5).

### Modified files
- `Sources/FCPXLite/Document/Magnetic/Mutations.swift` — add `positionMove(clipID:atTime:in:)` and `setGapDuration(at:duration:in:)`.
- `Sources/FCPXLite/Store/EditorAction.swift` — add `.positionMove(ClipID, time: Time)` and `.setGapDuration(at: Int, duration: Time)`.
- `Sources/FCPXLite/Store/DocumentStore.swift` — dispatch new actions.
- `Sources/FCPXLite/Views/TimelineContentView.swift` — add gap drawing (`drawGaps()`) + gap hit-test + gap edge detection; extend `debugGeometryJSON()` with gap rects.
- `Sources/FCPXLite/Views/TimelineContentView+Drag.swift` — rewrite with per-tool branching, cursor management, trim-edge hover state.
- `Sources/FCPXLite/Views/TimelineColors.swift` — add `gapFill` and `gapBorder` NSColors.
- `Sources/FCPXLite/AppDelegate.swift` — replace plain keyDown monitor with `SpringToolStateMachine`-driven dual-monitor (keyDown + keyUp).
- `Sources/FCPXLite/DebugControlServer.swift` — add `/cmd` ops: `trimClip`, `positionMove`, `setGapDuration`; extend `/layout` with `gaps` array and `cursorName` field.

---

### Task 1: Model mutations — positionMove + setGapDuration

**Files:**
- Modify: `Sources/FCPXLite/Document/Magnetic/Mutations.swift`
- Modify: `Sources/FCPXLite/Store/EditorAction.swift`
- Modify: `Sources/FCPXLite/Store/DocumentStore.swift`
- Test: `Tests/FCPXLiteTests/PositionMoveTests.swift`

**Interfaces:**
- Produces:
  - `Mutations.positionMove(clipID: ClipID, atTime: Time, in: Sequence) -> Sequence` — lift clip from spine (leave `.gap(duration:)` at source index), insert it at target time (lane 0, no snap). If the clip is a connected child, fall back to `relocate` behavior (no gap needed since it was already off-spine). If clip not found, no-op.
  - `Mutations.setGapDuration(at index: Int, duration: Time, in: Sequence) -> Sequence` — resize the `.gap` at `spine[index]` to new duration (clamp to `Time(value:1, timescale:)` minimum). If `spine[index]` is not a gap, no-op.
  - `EditorAction.positionMove(ClipID, time: Time)` — dispatches `Mutations.positionMove`.
  - `EditorAction.setGapDuration(at: Int, duration: Time)` — dispatches `Mutations.setGapDuration`.

- [ ] **Step 1: Create test file with failing tests**

Create `/Users/teli/www/video_editing_related/FCPX_lite/Tests/FCPXLiteTests/PositionMoveTests.swift`:

```swift
import XCTest
@testable import FCPXLite

final class PositionMoveTests: XCTestCase {

    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    // positionMove on a spine clip: source slot becomes .gap, clip lands at target
    func testPositionMoveLeavesGapAtSource() {
        let a = clip(3), b = clip(2), c = clip(1)
        let seq = Sequence(spine: [.clip(a), .clip(b), .clip(c)])
        // Move clip B (index 1) to time=6 (after c)
        let out = Mutations.positionMove(clipID: b.id, atTime: .seconds(6), in: seq)
        // spine[1] must now be a gap of 2s
        if case .gap(let d) = out.spine[1] {
            XCTAssertEqual(d, .seconds(2))
        } else {
            XCTFail("spine[1] should be .gap; got \(out.spine[1])")
        }
        // B must appear somewhere in the spine after the gap
        let ids = out.spine.compactMap { $0.asClip?.id }
        XCTAssertTrue(ids.contains(b.id))
        // Spine count unchanged (gap replaces clip slot, clip inserted elsewhere = count+1? No: we extract+replace-with-gap, then insert → count stays same only if we don't grow. Spec: replace source with gap, insert clip at target → spine.count == original + 1? Actually: original [A,B,C] → after replacing B with gap: [A,gap,C] (count 3) → insert B → [A,gap,C,B] (count 4). That's count+1. Let's verify the count = original.count + 1 — wait, original had 3 clips, after positionMove we have 3 elements (one gap replaces clip) + 1 new clip = 4 elements. That's the correct behavior.)
        XCTAssertEqual(out.spine.count, 4) // [A, gap, C, B]
        XCTAssertNoThrow(try Invariants.check(out))
    }

    func testPositionMoveUnknownIdIsNoop() {
        let a = clip(3)
        let seq = Sequence(spine: [.clip(a)])
        let out = Mutations.positionMove(clipID: ClipID(), atTime: .seconds(0), in: seq)
        XCTAssertEqual(out, seq)
    }

    func testPositionMoveConnectedClipFallsBackToRelocate() {
        let idHost = ClipID()
        let child = Clip(id: ClipID(), assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                         lane: 1, offset: .seconds(0.5))
        let host = Clip(id: idHost, assetID: AssetID(), sourceIn: .zero, duration: .seconds(4),
                        connected: [child])
        let seq = Sequence(spine: [.clip(host)])
        // Moving a connected clip: no gap should appear (it wasn't on spine)
        let out = Mutations.positionMove(clipID: child.id, atTime: .seconds(0), in: seq)
        // Spine still has 1 element (host), no extra gap
        XCTAssertEqual(out.spine.count, 2) // host + child now on spine as lane 0
        // Actually positionMove for connected clip should just do relocate to lane 0:
        XCTAssertNoThrow(try Invariants.check(out))
    }

    // setGapDuration resizes a gap
    func testSetGapDurationResizesGap() {
        let seq = Sequence(spine: [.gap(duration: .seconds(3))])
        let out = Mutations.setGapDuration(at: 0, duration: .seconds(5), in: seq)
        XCTAssertEqual(out.spine[0].duration, .seconds(5))
    }

    func testSetGapDurationClampsToMinimum() {
        let seq = Sequence(spine: [.gap(duration: .seconds(3))])
        let out = Mutations.setGapDuration(at: 0, duration: .seconds(-1), in: seq)
        // Duration must be at least 1 tick (non-zero positive)
        XCTAssertGreaterThan(out.spine[0].duration, .zero)
    }

    func testSetGapDurationOnClipIsNoop() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let seq = Sequence(spine: [.clip(a)])
        let out = Mutations.setGapDuration(at: 0, duration: .seconds(5), in: seq)
        XCTAssertEqual(out, seq)
    }

    func testSetGapDurationOutOfBoundsIsNoop() {
        let seq = Sequence(spine: [.gap(duration: .seconds(3))])
        let out = Mutations.setGapDuration(at: 5, duration: .seconds(5), in: seq)
        XCTAssertEqual(out, seq)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test --filter PositionMoveTests 2>&1 | tail -20
```

Expected: compilation errors ("positionMove not found", "setGapDuration not found").

- [ ] **Step 3: Add actions to EditorAction.swift**

In `Sources/FCPXLite/Store/EditorAction.swift`, add two cases after `case relocateClip`:

```swift
case positionMove(ClipID, time: Time)
case setGapDuration(at: Int, duration: Time)
```

The full enum becomes:
```swift
enum EditorAction: Codable, Equatable {
    case insertClip(Clip, at: Int)
    case rippleDelete(at: Int)
    case liftDelete(at: Int)
    case moveClip(from: Int, to: Int)
    case trimRight(at: Int, newDuration: Time, assetDuration: Time)
    case trimLeft(at: Int, deltaIn: Time)
    case blade(at: Int, localTime: Time)
    case connect(Clip, host: Int, lane: Int, offset: Time)
    case relocateClip(ClipID, lane: Int, time: Time)
    case positionMove(ClipID, time: Time)
    case setGapDuration(at: Int, duration: Time)
    case setInspector(Bool)
    case setEffects(Bool)
    case importAsset(Asset)
    case selectClip(ClipID?)
    case setTool(EditTool)
    case setZoom(Double)
    case setPlayhead(Time)
    case setTimelineHeight(Double)
    case selectAsset(AssetID?)
    case setPlaying(Bool)
    case togglePlay
    case toggleSnapping
    case setPanelWidth(PanelKind, Double)
}
```

- [ ] **Step 4: Implement positionMove and setGapDuration in Mutations.swift**

Append to `Sources/FCPXLite/Document/Magnetic/Mutations.swift` before the final closing `}` of the enum, after the `assertInvariants` helper:

```swift
/// Position-move: lift a spine clip, replace its slot with .gap(duration:),
/// insert the clip at target time in lane 0 (no magnetic snap).
/// If clipID refers to a connected child, falls back to relocate(lane:0) since there's no spine slot to leave a gap in.
/// Returns seq unchanged if clipID not found.
static func positionMove(clipID: ClipID, atTime t: Time, in seq: Sequence) -> Sequence {
    var s = seq
    // Check if it's a spine-direct clip first
    guard let spineIdx = s.spine.firstIndex(where: {
        if case .clip(let c) = $0 { return c.id == clipID }
        return false
    }) else {
        // Not a spine clip — try connected child fallback via relocate lane 0
        guard let _ = s.spine.compactMap({ (el: Element) -> Clip? in
            guard case .clip(let c) = el else { return nil }
            return c.connected.first(where: { $0.id == clipID })
        }).first else { return seq } // truly unknown id → no-op
        return relocate(clipID: clipID, toLane: 0, atTime: t, in: seq)
    }
    // Extract clip value, replace with gap
    guard case .clip(let extracted) = s.spine[spineIdx] else { return seq }
    let gapDuration = extracted.duration
    s.spine[spineIdx] = .gap(duration: gapDuration)
    // Insert at target time in the now-gap-containing sequence
    let idx = spineInsertionIndex(forTime: t, in: s)
    var placed = extracted
    placed.lane = 0
    placed.offset = .zero
    s.spine.insert(.clip(placed), at: idx)
    assertInvariants(s)
    return s
}

/// Resize a .gap at spine[index] to new duration.
/// Clamps to minimum 1 tick. No-op if spine[index] is a clip or index is out of bounds.
static func setGapDuration(at index: Int, duration: Time, in seq: Sequence) -> Sequence {
    var s = seq
    guard s.spine.indices.contains(index) else { return s }
    guard case .gap = s.spine[index] else { return s }
    let ts = duration.timescale > 0 ? duration.timescale : 600
    let minDur = Time(value: 1, timescale: ts)
    let clamped = duration < minDur ? minDur : duration
    s.spine[index] = .gap(duration: clamped)
    assertInvariants(s)
    return s
}
```

- [ ] **Step 5: Wire dispatch in DocumentStore.swift**

In `Sources/FCPXLite/Store/DocumentStore.swift`, in the `dispatch` switch, add two cases after `case let .relocateClip(id, lane, t)`:

```swift
case let .positionMove(id, t):           apply { Mutations.positionMove(clipID: id, atTime: t, in: $0) }
case let .setGapDuration(i, dur):        apply { Mutations.setGapDuration(at: i, duration: dur, in: $0) }
```

- [ ] **Step 6: Run tests — all must pass**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -10
```

Expected: "Executed 12X tests, with 0 failures"

- [ ] **Step 7: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Document/Magnetic/Mutations.swift \
        Sources/FCPXLite/Store/EditorAction.swift \
        Sources/FCPXLite/Store/DocumentStore.swift \
        Tests/FCPXLiteTests/PositionMoveTests.swift
git commit -m "feat(model): positionMove (leaves gap at source) + setGapDuration mutations"
```

---

### Task 2: Gap rendering + gap hit-test in TimelineContentView

**Files:**
- Modify: `Sources/FCPXLite/Views/TimelineColors.swift`
- Modify: `Sources/FCPXLite/Views/TimelineContentView.swift`

**Interfaces:**
- Consumes: `Layout.compute(sequence)` returns `[Placed]` which currently skips gaps. We need gap positions independently. Add a helper `gapRects() -> [(index: Int, rect: NSRect)]` on the view itself, iterating `sequence.spine` directly.
- Produces:
  - `TimelineContentView.hitTestGap(at:) -> (index: Int, rect: NSRect)?` — returns spine index and rect of gap under point (lane 0 only).
  - `TimelineContentView.gapEdge(at:edgeThreshold:) -> (index: Int, isLeft: Bool)?` — returns spine index and whether point is near the left or right edge of a gap.
  - Extended `debugGeometryJSON()` with a `"gaps"` key containing array of `{index, x, y, w, h}`.

Note: `TimelineContentView.swift` is currently 353 lines. With gap drawing additions it will approach ~420 lines — acceptable. If it exceeds 500, split drawing into `TimelineContentView+Draw.swift`.

- [ ] **Step 1: Add gap colors to TimelineColors.swift**

Append to the enum body in `Sources/FCPXLite/Views/TimelineColors.swift`:

```swift
/// Gap element fill: neutral gray, clearly distinct from blue clips.
static let gapFill    = NSColor(hex: "#3A3A3A")
/// Gap element border: subtle lighter gray.
static let gapBorder  = NSColor(hex: "#555555")
```

- [ ] **Step 2: Add gapRects helper and hitTestGap/gapEdge to TimelineContentView.swift**

In `Sources/FCPXLite/Views/TimelineContentView.swift`, add a new `// MARK: - Gap geometry` section after the existing `// MARK: - 几何辅助` section:

```swift
// MARK: - Gap geometry

/// Compute rects for all .gap elements on lane 0 in the current sequence.
/// Returns (spineIndex, NSRect) pairs, in spine order.
func gapRects() -> [(index: Int, rect: NSRect)] {
    var out: [(index: Int, rect: NSRect)] = []
    var t = Time.zero
    for (i, el) in sequence.spine.enumerated() {
        if case .gap(let d) = el {
            let x = TimelineGeometry.x(forSeconds: t.seconds, pxPerSecond: pxPerSecond)
            let w = max(2, TimelineGeometry.x(forSeconds: d.seconds, pxPerSecond: pxPerSecond))
            let y = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                              laneHeight: Self.laneHeight, laneGap: Self.laneGap,
                                              contentHeight: bounds.height)
            out.append((index: i, rect: NSRect(x: x, y: y, width: w, height: Self.laneHeight)))
        }
        t = t + el.duration
    }
    return out
}

/// Hit-test: returns the gap whose rect contains `point`, or nil.
func hitTestGap(at point: NSPoint) -> (index: Int, rect: NSRect)? {
    for entry in gapRects() where entry.rect.contains(point) {
        return entry
    }
    return nil
}

/// Returns gap index + isLeft=true if near the left edge, isLeft=false if near right edge.
/// edgeThreshold in pixels (typically 6).
func gapEdge(at point: NSPoint, edgeThreshold: CGFloat = 6) -> (index: Int, isLeft: Bool)? {
    for entry in gapRects() {
        let r = entry.rect
        guard r.contains(point) || (point.x >= r.minX - edgeThreshold && point.x <= r.maxX + edgeThreshold
                                     && point.y >= r.minY && point.y <= r.maxY) else { continue }
        if abs(point.x - r.minX) <= edgeThreshold { return (entry.index, true) }
        if abs(point.x - r.maxX) <= edgeThreshold { return (entry.index, false) }
    }
    return nil
}
```

- [ ] **Step 3: Add drawGaps() and call it in draw(_:)**

In `TimelineContentView.swift`, add a `drawGaps()` method in the `// MARK: - 绘制` section:

```swift
private func drawGaps() {
    for entry in gapRects() {
        let path = NSBezierPath(roundedRect: entry.rect, xRadius: 3, yRadius: 3)
        TimelineColors.gapFill.setFill()
        path.fill()
        TimelineColors.gapBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
        // Optional label
        let label = "gap" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: TimelineColors.textMuted,
        ]
        let pt = NSPoint(x: entry.rect.minX + 4, y: entry.rect.minY + 3)
        label.draw(at: pt, withAttributes: attrs)
    }
}
```

In the `draw(_ dirtyRect:)` method, call `drawGaps()` just before `drawDragGhost()`:

```swift
override func draw(_ dirtyRect: NSRect) {
    TimelineColors.canvas.setFill()
    bounds.fill()

    drawMainLaneBand()
    drawRuler()

    let ps = placed
    if ps.isEmpty && gapRects().isEmpty {
        drawEmptyHint()
    } else {
        for p in ps { drawClip(p) }
        drawGaps()
    }

    drawDragGhost()
    drawPlayhead()
}
```

- [ ] **Step 4: Extend debugGeometryJSON() with gaps**

In `debugGeometryJSON()`, after building the `clips` array, add a `gaps` array:

```swift
var gaps: [[String: Any]] = []
for entry in gapRects() {
    gaps.append(["spineIndex": entry.index,
                 "x": Double(entry.rect.minX), "y": Double(entry.rect.minY),
                 "w": Double(entry.rect.width), "h": Double(entry.rect.height)])
}
// ... existing return dict, add "gaps": gaps
return [
    "frameH": Double(frame.height), "boundsH": Double(bounds.height),
    "clipViewH": Double(enclosingScrollView?.contentView.bounds.height ?? -1),
    "scrollViewH": Double(enclosingScrollView?.bounds.height ?? -1),
    "rulerHeight": Double(Self.rulerHeight), "laneHeight": Double(Self.laneHeight),
    "lane0TopY": Double(lane0), "clips": clips, "gaps": gaps
]
```

- [ ] **Step 5: swift build to verify no compile errors**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: "Build complete!"

- [ ] **Step 6: swift test — all pass**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -5
```

Expected: "Executed 12X tests, with 0 failures"

- [ ] **Step 7: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Views/TimelineColors.swift \
        Sources/FCPXLite/Views/TimelineContentView.swift
git commit -m "feat(render): gap rendering on lane 0 (gray rects, hit-test, edge detect, debugGeometry)"
```

---

### Task 3: Tool-branched mouse handling + cursors in TimelineContentView+Drag.swift

**Files:**
- Modify: `Sources/FCPXLite/Views/TimelineContentView+Drag.swift` (full rewrite)
- Modify: `Sources/FCPXLite/Views/TimelineContentView.swift` (add trim hover state + resetCursorRects)

**Interfaces:**
- Consumes from Task 1: `EditorAction.positionMove(ClipID, time: Time)`, `EditorAction.setGapDuration(at: Int, duration: Time)`, `EditorAction.trimRight`, `EditorAction.trimLeft`.
- Consumes from Task 2: `hitTestGap(at:)`, `gapEdge(at:edgeThreshold:)`.
- Produces: No new public API. The rewrite replaces all of `TimelineContentView+Drag.swift`.

**Cursor mapping:**
| Tool | Default cursor | Drag cursor |
|------|---------------|-------------|
| select | arrow | arrow |
| position | arrow | arrow |
| trim (near edge) | resizeLeftRight | resizeLeftRight |
| trim (not near edge) | arrow | — |
| hand | openHand | closedHand |
| zoom | crosshair | crosshair |
| blade | crosshair | — |

**Implementation notes:**
- Add stored properties to `TimelineContentView` (in the main file): `var trimDragState: TrimDragState?` and `var handDragStartPoint: NSPoint?` and `var zoomDragStartX: CGFloat?` and `var zoomDragStartPxPerSecond: CGFloat?`.
- `TrimDragState`: struct `{ spineIndex: Int, isLeft: Bool, originalDuration: Time, originalSourceIn: Time, assetDuration: Time }` — stored so mouseUp can finalize.
- The trim interaction dispatches live (on mouseDragged) using `trimRight`/`trimLeft` so the ghost updates in real-time.
- Zoom: dispatch `.setZoom` live on drag. No ghost needed. `delta = (currentX - startX) * 0.5`; `newZoom = startZoom * pow(2, delta/100)`.
- Hand: directly scroll `enclosingScrollView?.contentView`. No dispatch needed.
- `resetCursorRects()` sets the cursor for the entire bounds based on `currentTool`. For trim, the default (non-edge) cursor is arrow; only when mouse is near an edge does it become resizeLeftRight (this is done via `mouseMoved` since `resetCursorRects` fires on layout, not hover).
- Add `mouseMoved(with:)` override to handle trim edge hover and update cursor dynamically. Enable mouse moved events: set `acceptsMouseMovedEvents = true` in window, or call `window?.acceptsMouseMovedEvents = true` in `apply(state:)`.
- The `TimelineContentView+Drag.swift` rewrite will be ~130 lines. If it grows beyond 200, further split into `+Hand.swift` and `+Trim.swift`.

**Stored properties to add to TimelineContentView.swift (main file):**

In the `// MARK: - 拖动片段状态` section, add:

```swift
// MARK: - Per-tool drag state

struct TrimDragState {
    var spineIndex: Int
    var isLeft: Bool            // true = left/head edge, false = right/tail edge
    var startX: CGFloat         // pixel x when drag started
    var originalDuration: Time
    var originalSourceIn: Time
    var assetDuration: Time
}

var trimDrag: TrimDragState?
var handDragStart: NSPoint?      // cursor position when hand drag began
var handScrollStart: NSPoint?    // scroll view content origin when hand drag began
var zoomDragStartX: CGFloat?
var zoomDragStartPPS: CGFloat?   // px per second at zoom drag start
```

Also override `resetCursorRects()` in the main file:

```swift
override func resetCursorRects() {
    discardCursorRects()
    switch currentTool {
    case .hand:
        addCursorRect(bounds, cursor: .openHand)
    case .zoom:
        addCursorRect(bounds, cursor: .crosshair)
    case .blade:
        addCursorRect(bounds, cursor: .crosshair)
    default:
        addCursorRect(bounds, cursor: .arrow)
    }
}
```

- [ ] **Step 1: Add new stored properties and resetCursorRects to TimelineContentView.swift**

In `Sources/FCPXLite/Views/TimelineContentView.swift`, in the `// MARK: - 拖动片段状态(Pass 2)` section, after `static let dragThresholdPx`, add:

```swift
// Per-tool drag state
struct TrimDragState {
    var spineIndex: Int
    var isLeft: Bool
    var startX: CGFloat
    var originalDuration: Time
    var originalSourceIn: Time
    var assetDuration: Time
}
var trimDrag: TrimDragState?
var handDragStart: NSPoint?
var handScrollStart: NSPoint?
var zoomDragStartX: CGFloat?
var zoomDragStartPPS: CGFloat?
```

After `func apply(state:)`, add:

```swift
override func resetCursorRects() {
    discardCursorRects()
    switch currentTool {
    case .hand:
        addCursorRect(bounds, cursor: .openHand)
    case .zoom, .blade:
        addCursorRect(bounds, cursor: .crosshair)
    default:
        addCursorRect(bounds, cursor: .arrow)
    }
}
```

Also, in `apply(state:)`, add `window?.invalidateCursorRects(for: self)` after `needsDisplay = true`:

```swift
func apply(state: State) {
    sequence = state.sequence
    assetLibrary = state.assetLibrary
    pxPerSecond = state.pxPerSecond
    playheadSeconds = state.playheadSeconds
    selectedClipID = state.selectedClipID
    currentTool = state.currentTool
    snappingEnabled = state.snappingEnabled
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
}
```

- [ ] **Step 2: Rewrite TimelineContentView+Drag.swift**

Replace the entire content of `Sources/FCPXLite/Views/TimelineContentView+Drag.swift` with:

```swift
import AppKit

/// TimelineContentView mouse interaction — branched per currentTool.
/// select:   drag clip → relocate with magnetic snap (kept from original).
/// position: drag clip → positionMove (no snap; leaves gap at source).
/// trim:     near head/tail edge → rippleTrimLeft/Right live.
/// hand:     drag → scroll NSScrollView horizontally.
/// zoom:     drag right/left → setZoom in/out.
/// blade:    click clip → cut.
/// default:  click empty → setPlayhead.
extension TimelineContentView {

    // MARK: - Edge threshold for trim cursor

    static let trimEdgePx: CGFloat = 6

    // MARK: - mouseDown

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        let inRuler = pt.y < Self.rulerHeight
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)

        switch currentTool {

        case .blade:
            guard !inRuler, let p = hitTestClip(at: pt) else {
                dispatch?(.setPlayhead(Time.seconds(t))); return
            }
            if let idx = TimelineGeometry.spineIndex(ofClipID: p.clipID, in: sequence) {
                let localT = max(0, t - p.absStart.seconds)
                dispatch?(.blade(at: idx, localTime: Time.seconds(localT)))
            }

        case .trim:
            guard !inRuler else { dispatch?(.setPlayhead(Time.seconds(t))); return }
            // Check clip edges first
            if let state = trimHitTest(at: pt) {
                trimDrag = state
                NSCursor.resizeLeftRight.set()
            } else {
                // Check gap edges
                if let gapEntry = gapEdge(at: pt, edgeThreshold: Self.trimEdgePx) {
                    // Use a pseudo-TrimDragState for gaps: isLeft maps to left/right edge
                    // We store spineIndex negative to distinguish gap (convention: -(index+1))
                    // Actually: use spineIndex directly; isLeft/false = left/right of gap
                    trimDrag = TrimDragState(
                        spineIndex: gapEntry.index,
                        isLeft: gapEntry.isLeft,
                        startX: pt.x,
                        originalDuration: sequence.spine[gapEntry.index].duration,
                        originalSourceIn: .zero,
                        assetDuration: .seconds(9999) // gaps have no asset limit
                    )
                    NSCursor.resizeLeftRight.set()
                } else {
                    dispatch?(.setPlayhead(Time.seconds(t)))
                }
            }

        case .hand:
            handDragStart = pt
            handScrollStart = enclosingScrollView.map { NSPoint(x: $0.contentView.bounds.origin.x,
                                                                 y: $0.contentView.bounds.origin.y) }
            NSCursor.closedHand.set()

        case .zoom:
            zoomDragStartX = pt.x
            zoomDragStartPPS = pxPerSecond
            NSCursor.crosshair.set()

        case .select, .position, .range:
            guard !inRuler, let p = hitTestClip(at: pt) else {
                dragClipID = nil
                dispatch?(.setPlayhead(Time.seconds(t)))
                return
            }
            dragClipID = p.clipID
            let clipStartX = TimelineGeometry.x(forSeconds: p.absStart.seconds, pxPerSecond: pxPerSecond)
            dragGrabDX = pt.x - clipStartX
            dragStartPoint = pt
            dragCurrentPoint = pt
            dispatch?(.selectClip(p.clipID))
        }
    }

    // MARK: - mouseDragged

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        switch currentTool {

        case .trim:
            guard let state = trimDrag else {
                // Scrub playhead fallback
                let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
                dispatch?(.setPlayhead(Time.seconds(t)))
                return
            }
            let dx = pt.x - state.startX
            let deltaSec = Double(dx / pxPerSecond)
            let idx = state.spineIndex
            if case .gap = sequence.spine[safe: idx] {
                // Trim gap: left edge shrinks gap from left, right edge extends from right
                let newDur: Time
                if state.isLeft {
                    newDur = state.originalDuration - Time.seconds(deltaSec)
                } else {
                    newDur = state.originalDuration + Time.seconds(deltaSec)
                }
                dispatch?(.setGapDuration(at: idx, duration: newDur))
            } else if state.isLeft {
                dispatch?(.trimLeft(at: idx, deltaIn: Time.seconds(deltaSec)))
            } else {
                let newDur = state.originalDuration + Time.seconds(deltaSec)
                dispatch?(.trimRight(at: idx, newDuration: newDur, assetDuration: state.assetDuration))
            }

        case .hand:
            guard let start = handDragStart, let scrollStart = handScrollStart,
                  let sv = enclosingScrollView else { return }
            let dx = pt.x - start.x
            let dy = pt.y - start.y
            let clip = sv.contentView
            let contentW = bounds.width
            let contentH = bounds.height
            let visW = clip.bounds.width
            let visH = clip.bounds.height
            var newX = scrollStart.x - dx
            var newY = scrollStart.y - dy
            newX = max(0, min(newX, max(0, contentW - visW)))
            newY = max(0, min(newY, max(0, contentH - visH)))
            clip.scroll(to: NSPoint(x: newX, y: newY))
            sv.reflectScrolledClipView(clip)

        case .zoom:
            guard let startX = zoomDragStartX, let startPPS = zoomDragStartPPS else { return }
            let dx = pt.x - startX
            // 100 pixels of drag = 1 doubling/halving
            let newZoom = startPPS * pow(2.0, Double(dx) / 100.0)
            dispatch?(.setZoom(newZoom))

        case .select, .position, .range:
            if dragClipID != nil {
                dragCurrentPoint = pt
                needsDisplay = true
            } else {
                let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
                dispatch?(.setPlayhead(Time.seconds(t)))
            }

        case .blade:
            let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
            dispatch?(.setPlayhead(Time.seconds(t)))
        }
    }

    // MARK: - mouseUp

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        switch currentTool {

        case .trim:
            // Final state already applied live during drag; just clear state.
            trimDrag = nil
            window?.invalidateCursorRects(for: self)

        case .hand:
            handDragStart = nil
            handScrollStart = nil
            NSCursor.openHand.set()

        case .zoom:
            zoomDragStartX = nil
            zoomDragStartPPS = nil

        case .select, .position, .range:
            defer {
                dragClipID = nil
                dragStartPoint = nil
                dragCurrentPoint = nil
                needsDisplay = true
            }
            guard let id = dragClipID else { return }
            if let start = dragStartPoint {
                let moved = hypot(pt.x - start.x, pt.y - start.y)
                if moved <= Self.dragThresholdPx { return }
            }
            if currentTool == .position {
                let rawSeconds = TimelineGeometry.seconds(forX: pt.x - dragGrabDX, pxPerSecond: pxPerSecond)
                dispatch?(.positionMove(id, time: Time.seconds(max(0, rawSeconds))))
            } else {
                let snappedSec = snappedTargetSeconds(forCursorX: pt.x)
                let lane = TimelineGeometry.lane(forY: pt.y, rulerHeight: Self.rulerHeight,
                                                  laneHeight: Self.laneHeight, laneGap: Self.laneGap,
                                                  contentHeight: bounds.height)
                dispatch?(.relocateClip(id, lane: lane, time: Time.seconds(snappedSec)))
            }

        case .blade:
            break
        }
    }

    // MARK: - mouseMoved (trim edge cursor)

    override func mouseMoved(with event: NSEvent) {
        guard currentTool == .trim else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if trimHitTest(at: pt) != nil || gapEdge(at: pt, edgeThreshold: Self.trimEdgePx) != nil {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Snap (select tool)

    func snappedTargetSeconds(forCursorX cursorX: CGFloat) -> Double {
        let rawSeconds = TimelineGeometry.seconds(forX: cursorX - dragGrabDX, pxPerSecond: pxPerSecond)
        guard snappingEnabled else { return max(0, rawSeconds) }
        let target = Time.seconds(rawSeconds)
        let thresholdSeconds = pxPerSecond > 0 ? Double(8.0 / pxPerSecond) : 0
        let threshold = Time.seconds(thresholdSeconds)
        let snapped = Snapping.snap(target, candidates: snapCandidates(), threshold: threshold)
        return max(0, snapped.seconds)
    }

    private func snapCandidates() -> [Time] {
        var out: [Time] = [Time.zero, Time.seconds(playheadSeconds)]
        for p in placed where p.clipID != dragClipID {
            out.append(p.absStart)
            out.append(p.absStart + p.duration)
        }
        return out
    }

    // MARK: - Trim hit-test helper

    /// Returns a TrimDragState if `point` is near the head or tail edge of any spine clip.
    /// Returns nil if not near any clip edge or point is in ruler.
    private func trimHitTest(at point: NSPoint) -> TrimDragState? {
        guard point.y >= Self.rulerHeight else { return nil }
        for p in placed where !p.isConnected {
            let rect = clipRect(p)
            guard rect.minY <= point.y, point.y <= rect.maxY else { continue }
            let isNearLeft  = abs(point.x - rect.minX) <= Self.trimEdgePx
            let isNearRight = abs(point.x - rect.maxX) <= Self.trimEdgePx
            guard isNearLeft || isNearRight else { continue }
            guard let idx = TimelineGeometry.spineIndex(ofClipID: p.clipID, in: sequence),
                  case .clip(let c) = sequence.spine[idx] else { continue }
            // Look up asset duration for right-trim clamping
            let assetDur = assetLibrary.first(where: { $0.id == c.assetID })?.duration
                ?? (c.sourceIn + c.duration + Time.seconds(3600)) // fallback: huge
            return TrimDragState(spineIndex: idx, isLeft: isNearLeft,
                                 startX: point.x,
                                 originalDuration: c.duration,
                                 originalSourceIn: c.sourceIn,
                                 assetDuration: assetDur)
        }
        return nil
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

**Note on trim live dispatch:** The trim drag dispatches mutations on every `mouseDragged` call. Because `trimLeft` uses `deltaIn` (delta from original sourceIn), but we're calling it repeatedly, we need to recalculate from the original each time. However, the current `rippleTrimLeft` signature takes a `deltaIn` that's applied cumulatively to the *current* state — not to the original. This means live drag will compound the delta incorrectly.

**Fix**: In `mouseDragged` for trim, instead of dispatching incremental `deltaIn`, reconstruct the full delta from `startX` each time:
- For left trim: `deltaFromStart = (pt.x - state.startX) / pxPerSecond` in seconds. We need to produce `deltaIn` = how much to move the in-point from the *original* position. Since each drag event applies the delta on current state, we need to undo the previous delta first. **Better approach**: store `originalDuration` and `originalSourceIn` in `TrimDragState`, then on each drag compute `desiredDuration = originalDuration - deltaFromStart` for left trim, and dispatch `trimRight` (since we're really changing duration from original). Wait — left trim from start:
  - `deltaFromStart` px / pxPerSecond = how many seconds we want to move the left edge RIGHT (+) or LEFT (-)
  - new `sourceIn = originalSourceIn + deltaFromStart`
  - new `duration = originalDuration - deltaFromStart`
  - This can be expressed as `trimRight(at:, newDuration: originalDuration - deltaFromStart, assetDuration:)` + manually adjusting sourceIn? No, `trimRight` only changes duration.

**Revised implementation for live trim**: Don't apply incremental mutations. Instead, recalculate from snapshot and dispatch the "final state" mutation directly. For left trim:

In mouseDragged, for trim (left edge):
```swift
let deltaFromStart = Double((pt.x - state.startX) / pxPerSecond)
// Dispatch trimLeft with deltaIn measured from original (undo previous delta first)
// Approach: use trimRight with adjusted duration and trim sourceIn manually?
// Actually safest: compute the absolute new duration from original, use trimRight for duration,
// then fix sourceIn separately. But we don't have a "setSourceIn" mutation.
// Solution: dispatch trimLeft with deltaIn = deltaFromStart - previousDeltaApplied.
// But we don't track previousDeltaApplied.
// Better: dispatch trimLeft with a deltaIn computed so the cumulative effect = deltaFromStart from original.
// We need to track lastAppliedDelta and send (deltaFromStart - lastAppliedDelta) as incremental.
```

This is getting complex. **Simplest correct approach**: add `lastAppliedDeltaSec: Double = 0` to `TrimDragState`, and on each drag:
```swift
let deltaFromStart = Double((pt.x - state.startX) / pxPerSecond)
let incrementalDelta = deltaFromStart - state.lastAppliedDeltaSec
trimDrag?.lastAppliedDeltaSec = deltaFromStart
// dispatch trimLeft(at: idx, deltaIn: Time.seconds(incrementalDelta))
```

Update `TrimDragState` to include `var lastAppliedDeltaSec: Double = 0`.

- [ ] **Step 3: Update TrimDragState to include lastAppliedDeltaSec**

In `TimelineContentView.swift`, in the `TrimDragState` struct, add:

```swift
struct TrimDragState {
    var spineIndex: Int
    var isLeft: Bool
    var startX: CGFloat
    var originalDuration: Time
    var originalSourceIn: Time
    var assetDuration: Time
    var lastAppliedDeltaSec: Double = 0
}
```

And update the `mouseDragged` trim branch in `TimelineContentView+Drag.swift` to use the incremental approach:

```swift
case .trim:
    guard var state = trimDrag else {
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
        dispatch?(.setPlayhead(Time.seconds(t)))
        return
    }
    let deltaFromStart = Double((pt.x - state.startX) / pxPerSecond)
    let incrementalDelta = deltaFromStart - state.lastAppliedDeltaSec
    state.lastAppliedDeltaSec = deltaFromStart
    trimDrag = state
    let idx = state.spineIndex
    if case .gap = sequence.spine[safe: idx] {
        let newDur: Time
        if state.isLeft {
            newDur = state.originalDuration - Time.seconds(deltaFromStart)
        } else {
            newDur = state.originalDuration + Time.seconds(deltaFromStart)
        }
        dispatch?(.setGapDuration(at: idx, duration: newDur))
    } else if state.isLeft {
        dispatch?(.trimLeft(at: idx, deltaIn: Time.seconds(incrementalDelta)))
    } else {
        let newDur = state.originalDuration + Time.seconds(deltaFromStart)
        dispatch?(.trimRight(at: idx, newDuration: newDur, assetDuration: state.assetDuration))
    }
```

Note: for gap trim, we use `originalDuration ± deltaFromStart` (absolute from start), which is correct since `setGapDuration` takes an absolute duration. For clip left trim, we use incremental. For clip right trim, we also use absolute (`originalDuration + deltaFromStart`).

- [ ] **Step 4: Verify build**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: "Build complete!"

- [ ] **Step 5: swift test — all pass**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Views/TimelineContentView+Drag.swift \
        Sources/FCPXLite/Views/TimelineContentView.swift
git commit -m "feat(tools): tool-branched mouse handling + NSCursor feedback (trim/hand/zoom/position/select)"
```

---

### Task 4: Spring-loaded tools (SpringToolStateMachine + AppDelegate keyUp monitor)

**Files:**
- Create: `Sources/FCPXLite/Store/SpringToolStateMachine.swift`
- Create: `Tests/FCPXLiteTests/SpringToolTests.swift`
- Modify: `Sources/FCPXLite/AppDelegate.swift`

**Interfaces:**
- Produces:
  - `struct SpringToolStateMachine` with:
    - `mutating func keyDown(tool: EditTool, at timestamp: TimeInterval) -> EditTool?` — returns the tool to switch to (or nil if already that tool). Records spring state.
    - `mutating func keyUp(tool: EditTool, at timestamp: TimeInterval) -> EditTool?` — returns the tool to revert to (if spring) or nil (if permanent tap).
    - `var currentTool: EditTool` — the current active tool (updated internally).
    - `var savedTool: EditTool?` — the pre-spring tool to revert to.
    - `let holdThresholdMs: Double = 250` — configurable threshold.

**Spring state machine spec:**
- State: `{currentTool, savedTool: EditTool?, springKeyDownTime: TimeInterval?}`
- `keyDown(tool: T)`:
  - If `T == currentTool`: no-op, return nil.
  - If `savedTool == nil`: save currentTool → savedTool; set currentTool = T; record springKeyDownTime; return T.
  - If `savedTool != nil` (already spring-held): replace with new spring: save currentTool → savedTool; set currentTool = T; return T.
- `keyUp(tool: T)`:
  - If `T != currentTool`: no-op, return nil (key up for a non-active spring key).
  - If `springKeyDownTime == nil`: no-op.
  - If elapsed < holdThresholdMs: treat as permanent tap → clear savedTool, clear springKeyDownTime, return nil (no revert; user sees T as permanent).
  - If elapsed >= holdThresholdMs: spring revert → restore currentTool = savedTool!; clear savedTool and springKeyDownTime; return restored tool.

- [ ] **Step 1: Create SpringToolTests.swift**

Create `Tests/FCPXLiteTests/SpringToolTests.swift`:

```swift
import XCTest
@testable import FCPXLite

final class SpringToolTests: XCTestCase {

    func testQuickTapIsPermanent() {
        var sm = SpringToolStateMachine(currentTool: .select)
        // Quick tap: down then up within 100ms (< 250ms threshold)
        let t0 = 0.0
        let switched = sm.keyDown(tool: .trim, at: t0)
        XCTAssertEqual(switched, .trim)
        XCTAssertEqual(sm.currentTool, .trim)
        let reverted = sm.keyUp(tool: .trim, at: t0 + 0.1) // 100ms < 250ms
        // Quick tap = permanent → no revert
        XCTAssertNil(reverted)
        XCTAssertEqual(sm.currentTool, .trim)
        XCTAssertNil(sm.savedTool)
    }

    func testHoldRevertsOnKeyUp() {
        var sm = SpringToolStateMachine(currentTool: .select)
        let t0 = 0.0
        let switched = sm.keyDown(tool: .trim, at: t0)
        XCTAssertEqual(switched, .trim)
        let reverted = sm.keyUp(tool: .trim, at: t0 + 0.5) // 500ms >= 250ms
        // Long hold = spring → revert to .select
        XCTAssertEqual(reverted, .select)
        XCTAssertEqual(sm.currentTool, .select)
        XCTAssertNil(sm.savedTool)
    }

    func testKeyDownSameTool_NoOp() {
        var sm = SpringToolStateMachine(currentTool: .select)
        let result = sm.keyDown(tool: .select, at: 0)
        XCTAssertNil(result)
        XCTAssertEqual(sm.currentTool, .select)
    }

    func testKeyUpNonActiveTool_NoOp() {
        var sm = SpringToolStateMachine(currentTool: .select)
        _ = sm.keyDown(tool: .trim, at: 0)
        // keyUp for a different key (.blade) while .trim is active
        let result = sm.keyUp(tool: .blade, at: 0.5)
        XCTAssertNil(result)
        XCTAssertEqual(sm.currentTool, .trim)
    }

    func testNestedSpringReplacesOuter() {
        var sm = SpringToolStateMachine(currentTool: .select)
        _ = sm.keyDown(tool: .trim, at: 0.0)
        XCTAssertEqual(sm.savedTool, .select)
        // Hold another key while trim is held
        _ = sm.keyDown(tool: .hand, at: 0.1)
        XCTAssertEqual(sm.currentTool, .hand)
        // Release hand after long hold → revert to trim (the savedTool at time of second keyDown)
        let reverted = sm.keyUp(tool: .hand, at: 0.1 + 0.5)
        XCTAssertEqual(reverted, .trim)
        XCTAssertEqual(sm.currentTool, .trim)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test --filter SpringToolTests 2>&1 | tail -10
```

Expected: compilation error ("SpringToolStateMachine not found").

- [ ] **Step 3: Create SpringToolStateMachine.swift**

Create `Sources/FCPXLite/Store/SpringToolStateMachine.swift`:

```swift
import Foundation

/// Pure value-type state machine for FCP-style spring-loaded tool switching.
///
/// Tap (keyDown + keyUp < holdThresholdMs): permanent tool switch, no revert.
/// Hold (keyDown + keyUp >= holdThresholdMs): temporary switch; reverts to previous tool on keyUp.
///
/// Usage:
///   var machine = SpringToolStateMachine(currentTool: store.ui.currentTool)
///   // keyDown event for tool "T":
///   if let newTool = machine.keyDown(tool: T, at: event.timestamp) {
///       store.dispatch(.setTool(newTool))
///   }
///   // keyUp event for tool "T":
///   if let revertTo = machine.keyUp(tool: T, at: event.timestamp) {
///       store.dispatch(.setTool(revertTo))
///   }
struct SpringToolStateMachine {
    var currentTool: EditTool
    private(set) var savedTool: EditTool?
    private var springKeyDownTime: TimeInterval?
    let holdThresholdMs: Double

    init(currentTool: EditTool, holdThresholdMs: Double = 250) {
        self.currentTool = currentTool
        self.holdThresholdMs = holdThresholdMs
    }

    /// Call on keyDown. Returns the tool to dispatch, or nil if no change needed.
    mutating func keyDown(tool: EditTool, at timestamp: TimeInterval) -> EditTool? {
        guard tool != currentTool else { return nil }
        savedTool = currentTool
        springKeyDownTime = timestamp
        currentTool = tool
        return tool
    }

    /// Call on keyUp. Returns the tool to revert to (spring release), or nil (permanent tap / no-op).
    mutating func keyUp(tool: EditTool, at timestamp: TimeInterval) -> EditTool? {
        guard tool == currentTool else { return nil }         // key up for inactive spring
        guard let downTime = springKeyDownTime else { return nil }
        let elapsed = (timestamp - downTime) * 1000           // ms
        springKeyDownTime = nil
        if elapsed < holdThresholdMs {
            // Quick tap → permanent switch, keep currentTool as-is
            savedTool = nil
            return nil
        } else {
            // Long hold → spring revert
            let revert = savedTool ?? currentTool
            currentTool = revert
            savedTool = nil
            return revert
        }
    }
}
```

- [ ] **Step 4: Run SpringToolTests — all pass**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test --filter SpringToolTests 2>&1 | tail -10
```

Expected: 5 tests pass.

- [ ] **Step 5: Rewrite AppDelegate.swift to use SpringToolStateMachine**

Replace `installKeyboardShortcuts()` in `Sources/FCPXLite/AppDelegate.swift`:

```swift
private var keyDownMonitor: Any?
private var keyUpMonitor: Any?
private var springMachine: SpringToolStateMachine = SpringToolStateMachine(currentTool: .select)

private func installKeyboardShortcuts() {
    keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }
        if self.window?.firstResponder is NSText { return event }
        let store = self.store
        let mods = event.modifierFlags
        let hasCmd = mods.contains(.command)
        let hasOptCtrl = !mods.intersection([.option, .control]).isEmpty

        // ⌘ combos
        if hasCmd && !hasOptCtrl {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "=", "+": store.dispatch(.setZoom(store.ui.pxPerSecond * 1.5)); return nil
            case "-":      store.dispatch(.setZoom(store.ui.pxPerSecond / 1.5)); return nil
            case "b":      store.bladeAtPlayhead(); return nil
            case "i":      ImportPanel.present(into: store); return nil
            default:       return event
            }
        }
        if hasCmd || hasOptCtrl { return event }

        // Arrow keys / Home / End / Space / Delete
        switch event.keyCode {
        case 123: store.nudgePlayhead(frames: mods.contains(.shift) ? -10 : -1); return nil
        case 124: store.nudgePlayhead(frames: mods.contains(.shift) ?  10 :  1); return nil
        case 115: store.playheadToStart(); return nil
        case 119: store.playheadToEnd(); return nil
        case 49:  store.dispatch(.togglePlay); return nil
        case 51:  store.deleteSelected(); return nil
        default: break
        }

        if mods.contains(.shift) { return event }

        // Edit operations (Q/W/E/D)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "q": store.connectAtPlayhead(); return nil
        case "w": store.insertAtPlayhead(); return nil
        case "e": store.appendSelected(); return nil
        case "d": store.overwriteAtPlayhead(); return nil
        case "n": store.dispatch(.toggleSnapping); return nil
        default: break
        }

        // Tool keys with spring-loaded behavior
        if let toolKey = event.charactersIgnoringModifiers?.lowercased(),
           let tool = EditTool.allCases.first(where: { $0.shortcut.lowercased() == toolKey }),
           !event.isARepeat {
            // Sync machine with current store tool (in case it was changed externally)
            self.springMachine.currentTool = store.ui.currentTool
            if let newTool = self.springMachine.keyDown(tool: tool, at: event.timestamp) {
                store.dispatch(.setTool(newTool))
            }
            return nil
        }

        return event
    }

    keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
        guard let self else { return event }
        if self.window?.firstResponder is NSText { return event }
        guard let toolKey = event.charactersIgnoringModifiers?.lowercased(),
              let tool = EditTool.allCases.first(where: { $0.shortcut.lowercased() == toolKey }) else {
            return event
        }
        if let revertTo = self.springMachine.keyUp(tool: tool, at: event.timestamp) {
            self.store.dispatch(.setTool(revertTo))
        }
        return event
    }
}
```

Also update the `applicationDidFinishLaunching` to remove old `keyMonitor` reference (we now use `keyDownMonitor` + `keyUpMonitor`). Remove:
```swift
private var keyMonitor: Any?
```
Add in properties:
```swift
private var keyDownMonitor: Any?
private var keyUpMonitor: Any?
private var springMachine: SpringToolStateMachine = SpringToolStateMachine(currentTool: .select)
```

And ensure `applicationWillTerminate` (or `deinit`) removes both monitors:
```swift
func applicationWillTerminate(_ notification: Notification) {
    if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
    if let m = keyUpMonitor   { NSEvent.removeMonitor(m) }
}
```

- [ ] **Step 6: swift build — clean**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 7: swift test — all pass**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | tail -5
```

Expected: "Executed 12X+ tests, with 0 failures"

- [ ] **Step 8: Commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/Store/SpringToolStateMachine.swift \
        Tests/FCPXLiteTests/SpringToolTests.swift \
        Sources/FCPXLite/AppDelegate.swift
git commit -m "feat(spring): spring-loaded tool switching (tap=permanent, hold>250ms=temporary revert)"
```

---

### Task 5: Harness extensions + self-test + report

**Files:**
- Modify: `Sources/FCPXLite/DebugControlServer.swift`
- Create: `.superpowers/sdd/DE-report.md`

**Goal:** Add `/cmd` ops for `trimClip`, `positionMove`, `setGapDuration` to the debug harness; extend `/layout` response with `gaps` and `cursorName`. Then run the self-test sequence and write the report.

**New `/cmd` ops to add:**
| op | params | action |
|----|--------|--------|
| `trimClip` | `index` (spine clip index), `seconds` (new duration), `assetDuration` (optional, default 9999) | `store.dispatch(.trimRight(at: index, newDuration: .seconds(seconds), assetDuration: .seconds(assetDuration)))` |
| `positionMove` | `index` (spine clip index, 0-based clip count), `seconds` (target time) | look up clipID by index, `store.dispatch(.positionMove(id, time: .seconds(seconds)))` |
| `setGapDuration` | `index` (spine index, not clip index), `seconds` (new duration) | `store.dispatch(.setGapDuration(at: index, duration: .seconds(seconds)))` |

**Extended `/layout` response:** The `debugGeometryJSON()` already returns `gaps` after Task 2. Additionally, expose `cursorName` from the view's current tool:
In `debugGeometryJSON()`, add:
```swift
"currentTool": currentTool.rawValue,
```

- [ ] **Step 1: Add new /cmd ops to DebugControlServer.swift**

In `execute(body:)`, add new cases in the `switch cmd.op` block:

```swift
case "trimClip":
    if let idx = cmd.index {
        let assetDur = cmd.px ?? 9999  // reuse px field for assetDuration
        store.dispatch(.trimRight(at: idx, newDuration: .seconds(cmd.seconds ?? 0),
                                  assetDuration: .seconds(assetDur)))
    }
case "positionMove":
    if let id = spineClipID(at: cmd.index ?? 0) {
        store.dispatch(.positionMove(id, time: .seconds(cmd.seconds ?? 0)))
    }
case "setGapDuration":
    if let idx = cmd.index {
        store.dispatch(.setGapDuration(at: idx, duration: .seconds(cmd.seconds ?? 1)))
    }
```

Also add `"currentTool": currentTool.rawValue` to `debugGeometryJSON()` in `TimelineContentView.swift`.

- [ ] **Step 2: swift build (release check)**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift build -c release 2>&1 | grep -E "error:|Build complete"
```

Expected: "Build complete!"

- [ ] **Step 3: Run swift test — final count**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && swift test 2>&1 | grep "Executed"
```

Expected: ≥ 126 tests (117 + 5 SpringTool + 7 PositionMove), 0 failures.

- [ ] **Step 4: Run make_app.sh bundle**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite && bash scripts/make_app.sh 2>&1 | tail -5
```

Expected: bundle created OK.

- [ ] **Step 5: grep SwiftUI raw colors = 0**

```bash
grep -r 'Color(hex:' /Users/teli/www/video_editing_related/FCPX_lite/Sources/FCPXLite/Views/ && echo "FOUND" || echo "CLEAN"
grep -r 'Color\.' /Users/teli/www/video_editing_related/FCPX_lite/Sources/FCPXLite/Views/*.swift | grep -v '//' | grep -v 'NSColor' | grep -v 'TimelineColors' | grep -v 'Tokens' && echo "POSSIBLE" || echo "CLEAN"
```

Expected: CLEAN for both.

- [ ] **Step 6: Self-test with harness**

```bash
# Start app
cd /Users/teli/www/video_editing_related/FCPX_lite
./.build/debug/FCPXLite > /tmp/fcpx_app.log 2>&1 &
sleep 2

# Import media
curl -s -X POST http://127.0.0.1:8765/cmd \
     -d '{"op":"importFile","path":"/Users/teli/Downloads/_dl/_telivideo/review_not_vloging.mp4"}' | python3 -m json.tool | grep -E "spine|assetLibrary"

# Insert clip at spine 0
curl -s -X POST http://127.0.0.1:8765/cmd \
     -d '{"op":"insertAsset","index":0,"at":0}' | python3 -m json.tool | grep -E '"spine"' -A5

# Insert second clip
curl -s -X POST http://127.0.0.1:8765/cmd \
     -d '{"op":"insertAsset","index":0,"at":1}' | python3 -m json.tool | grep '"spine"' -A5

# Verify /layout — no gaps initially
curl -s http://127.0.0.1:8765/layout | python3 -m json.tool | grep -E '"gaps"' -A5

# Test trimClip: trim clip 0 to 3s
curl -s -X POST http://127.0.0.1:8765/cmd \
     -d '{"op":"trimClip","index":0,"seconds":3.0,"px":9999}' | python3 -m json.tool | grep '"spine"' -A15

# Test positionMove: move clip 0 to 20s (leaves gap)
curl -s -X POST http://127.0.0.1:8765/cmd \
     -d '{"op":"positionMove","index":0,"seconds":20.0}' | python3 -m json.tool | grep '"spine"' -A20

# Verify /layout shows a gap
curl -s http://127.0.0.1:8765/layout | python3 -m json.tool | grep -E '"gaps"' -A10

# Screenshot
curl -s http://127.0.0.1:8765/screenshot -o /tmp/fcpx_DE_test.png && echo "Screenshot saved"

# Kill app
pkill -f '.build/debug/FCPXLite'
echo "App killed"
```

Capture and record the output (gap count, spine elements, layout gaps) in the report.

- [ ] **Step 7: Write DE-report.md**

Create `/Users/teli/www/video_editing_related/FCPX_lite/.superpowers/sdd/DE-report.md` documenting:
- What was built per tool (select/position/trim/hand/zoom/blade)
- Position-gap behavior (spine element replaced with `.gap` on move)
- Cursors implemented (per-tool + trim edge hover)
- Spring-tool state machine (tap vs hold threshold)
- Harness ops added: `trimClip`, `positionMove`, `setGapDuration`; layout field `gaps` + `currentTool`
- Self-test commands and observed outputs (copy from step 6)
- Test count and build/bundle results
- grep results
- What's deferred (true overwrite-trim at destination; range selection tool behavior)

- [ ] **Step 8: Final commit**

```bash
cd /Users/teli/www/video_editing_related/FCPX_lite
git add Sources/FCPXLite/DebugControlServer.swift \
        .superpowers/sdd/DE-report.md
git commit -m "feat(harness): add trimClip/positionMove/setGapDuration /cmd ops + self-test + DE-report"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| select drag → relocate w/ snap | Task 3 (preserved in mouseUp .select branch) |
| position drag → positionMove no snap | Task 1 (mutation) + Task 3 (mouseUp .position branch) |
| position leaves gap at source | Task 1 (Mutations.positionMove replaces spine slot with .gap) |
| trim near edge → resizeLeftRight cursor | Task 3 (trimHitTest + mouseMoved) |
| trim drag → rippleTrimLeft/Right | Task 3 (mouseDragged .trim) |
| hand drag → scroll scrollView | Task 3 (mouseDragged .hand) |
| hand cursor openHand/closedHand | Task 3 (mouseDown/mouseUp .hand + resetCursorRects) |
| zoom drag → setZoom | Task 3 (mouseDragged .zoom) |
| zoom cursor crosshair | Task 3 (resetCursorRects + mouseDown .zoom) |
| blade → cut clip (keep) | Task 3 (mouseDown .blade preserved) |
| empty/ruler → playhead | Task 3 (fallthrough in all tools) |
| gap rendering gray rects | Task 2 (drawGaps()) |
| gap hit-testable | Task 2 (hitTestGap) |
| gap trim with trim tool | Task 3 (gapEdge detection + setGapDuration dispatch) |
| spring-loaded tools tap vs hold | Task 4 (SpringToolStateMachine) |
| spring keyDown + keyUp monitors | Task 4 (AppDelegate rewrite) |
| unit tests for positionMove + setGapDuration | Task 1 (PositionMoveTests.swift) |
| unit tests for spring state machine | Task 4 (SpringToolTests.swift) |
| harness trimClip/positionMove ops | Task 5 |
| /layout gaps field | Task 2 (debugGeometryJSON extended) |
| swift test green | all tasks |
| files ≤ 500 lines | tracked per-file |
| no SwiftUI Color(hex:) | constraint enforced in all new code |
| release build ok | Task 5 step 2 |
| make_app.sh ok | Task 5 step 4 |

**Deferred (explicit TODO):**
- True overwrite-trim at destination for position tool (spec says "overwrite-trim of destination can be a TODO").
- Range tool mouse behavior (it falls through to select behavior in the current plan).
- `mouseMoved` requires `window?.acceptsMouseMovedEvents = true` — add this in `apply(state:)` or `viewDidMoveToWindow()`.

**Placeholder scan:** All steps contain actual code. No "TBD" or "implement later" stubs.

**Type consistency:**
- `TrimDragState` defined in `TimelineContentView.swift` main file, referenced in `TimelineContentView+Drag.swift` extension — correct (same type, same file, extension shares the type).
- `SpringToolStateMachine` defined in its own file, instantiated in `AppDelegate.swift` — correct.
- `EditorAction.positionMove(ClipID, time: Time)` — consistent across EditorAction, DocumentStore, and TimelineContentView+Drag.swift usage.
- `Mutations.positionMove(clipID: ClipID, atTime: Time, in: Sequence)` — consistent with test file reference.
