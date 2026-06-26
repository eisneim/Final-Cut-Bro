# FCPX-lite 基础切片(M1.0–M1.2)实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭起 SwiftPM 工程与可启动的五区外壳,实现 FCPXML 对齐的文档模型与命令层,以及全套磁性时间线引擎(L1主轴+L2连接片段+L3泳道),并用控制变量对照实验证明其正确。

**Architecture:** 三层架构的纯逻辑地基。文档模型(值类型 `struct`,单一数据源)→ 命令层(唯一修改入口,即未来 Agent 预留口)→ 磁性引擎(`[Element]→[Element]` 纯函数,无 UI / 无 AVFoundation)。UI 仅为可启动的空五区外壳,验证配色与布局骨架。本切片不含 AVFoundation、不含时间线自绘画布,因此全程可 TDD,不依赖手动 `.app` 观察(外壳除外)。

**Tech Stack:** Swift 5.9 / SwiftPM(`.executableTarget` + `.testTarget`)/ macOS 14 / AppKit 入口 + SwiftUI 托管(`NSHostingView`)/ XCTest。沿用用户既有项目 `meetingAssitant`、`feishu_msg` 的工程约定。

## Global Constraints

- macOS 平台:`platforms: [.macOS(.v14)]`,`LSMinimumSystemVersion 14.0`(verbatim,spec §1)。
- Swift 工具链:`swift-tools-version:5.9`。
- 构建系统:SwiftPM,**不用 Xcode project**(spec §1)。
- 入口:AppKit `main.swift` + `AppDelegate`,SwiftUI 视图用 `NSHostingView` 托管(spec §1)。
- **单文件 ≤ 500 行**,超出拆分;`.swift` 不混大段样式(用户 CLAUDE.md)。
- **配色只引用 `DesignSystem/Tokens.swift` 的 Token,严禁裸 hex**;Token 值来自 `design/style.md` 实采(spec §6)。
- **时间用有理数 `Time`,严禁浮点表示时间线位置/时长**(spec §2,帧精度根本)。
- **Spine 元素绝对起点不存储,由引擎前缀和实时算**(spec §2/§3,磁性正确性根本)。
- **所有文档修改只走命令层**(spec §1,Agent 预留口);命令层每次 mutation 后断言三条磁性不变量(spec §7)。
- **fail fast**:dev 阶段不写兜底 fallback,异常显式上抛(用户 CLAUDE.md + spec §7)。
- 模块名 `FCPXLite`;包名 `FCPXLite`;bundle id `com.local.fcpxlite`。
- App 由用户自己启停,**实现者不得后台常驻 app 进程**(用户 CLAUDE.md)。

---

## 文件结构(本切片创建/修改的文件)

```
Package.swift                                            # SwiftPM 清单
Sources/FCPXLite/
  main.swift                                             # AppKit 入口
  AppDelegate.swift                                      # 建窗 + 托管 RootView
  DesignSystem/
    Color+Hex.swift                                      # Color(hex:) 扩展
    Tokens.swift                                         # 落 style.md 的色/字/间距 Token
  Models/
    Time.swift                                           # 有理数时间(CMTime 语义)
    Ids.swift                                            # AssetID / ClipID 强类型 ID
    Asset.swift                                          # 素材引用 + MediaKind
    Adjustments.swift                                    # Transform/Crop/opacity/volume
  Document/
    Clip.swift                                           # Clip 值类型(含 connected/lane/offset)
    Element.swift                                        # Element = clip | gap
    Spine.swift                                          # Sequence + Spine + Project + Document
    Magnetic/
      Layout.swift                                       # 前缀和布局 → [Placed]
      Snapping.swift                                     # 纯函数吸附
      Mutations.swift                                    # 命令层:insert/delete/move/trim/blade/connect
      Invariants.swift                                   # 三条不变量校验
  Store/
    DocumentStore.swift                                  # @Observable 包裹 Document
  Views/
    RootView.swift                                       # 五区布局骨架
    Placeholders.swift                                   # 各区占位子视图 + ChatPanel 占位
Tests/FCPXLiteTests/
  TimeTests.swift
  LayoutTests.swift
  SnappingTests.swift
  MutationTests.swift
  InvariantPropertyTests.swift                           # 控制变量对照实验框架
scripts/
  make_app.sh                                            # 打包 .app(沿用 feishu 结构)
```

---

## Task 1: SwiftPM 工程骨架 + 冒烟测试

**Files:**
- Create: `Package.swift`
- Create: `Sources/FCPXLite/Placeholder.swift`(临时,Task 2 起被真实文件取代)
- Test: `Tests/FCPXLiteTests/SmokeTest.swift`

**Interfaces:**
- Consumes: 无
- Produces: 可 `swift build` / `swift test` 的包;模块名 `FCPXLite`。

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FCPXLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FCPXLite",
            path: "Sources/FCPXLite"
        ),
        .testTarget(
            name: "FCPXLiteTests",
            dependencies: ["FCPXLite"],
            path: "Tests/FCPXLiteTests"
        ),
    ]
)
```

- [ ] **Step 2: 写临时占位源文件(让 executable target 能编译)**

`Sources/FCPXLite/Placeholder.swift`:
```swift
enum BuildSmoke {
    static let ok = true
}
```

- [ ] **Step 3: 写冒烟测试**

`Tests/FCPXLiteTests/SmokeTest.swift`:
```swift
import XCTest
@testable import FCPXLite

final class SmokeTest: XCTestCase {
    func testBuildSmoke() {
        XCTAssertTrue(BuildSmoke.ok)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test`
Expected: PASS,`Executed 1 test`。

- [ ] **Step 5: 提交**

```bash
git add Package.swift Sources/FCPXLite/Placeholder.swift Tests/FCPXLiteTests/SmokeTest.swift
git commit -m "chore: SwiftPM 工程骨架 + 冒烟测试"
```

---

## Task 2: 有理数时间 `Time`

**Files:**
- Create: `Sources/FCPXLite/Models/Time.swift`
- Test: `Tests/FCPXLiteTests/TimeTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct Time: Equatable, Comparable, Hashable, Codable`
  - `init(value: Int64, timescale: Int32)`;`static let zero: Time`
  - `static func seconds(_ s: Double, timescale: Int32 = 600) -> Time`
  - `var seconds: Double { get }`
  - `static func + / - (Time, Time) -> Time`(自动通分)
  - `static func * (Time, Double) -> Time`(按比例,blade 用)
  - `func clamped(to range: ClosedRange<Time>) -> Time`
  - `var fcpxmlString: String { get }`(形如 `"3600/600s"`)

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/TimeTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class TimeTests: XCTestCase {
    func testAddSameTimescale() {
        let a = Time(value: 100, timescale: 600)
        let b = Time(value: 200, timescale: 600)
        XCTAssertEqual(a + b, Time(value: 300, timescale: 600))
    }

    func testAddDifferentTimescaleCommonizes() {
        let a = Time(value: 1, timescale: 2)   // 0.5s
        let b = Time(value: 1, timescale: 3)   // 0.333..s
        // 0.5 + 0.3333 = 0.8333.. -> 5/6
        XCTAssertEqual((a + b).seconds, 5.0/6.0, accuracy: 1e-9)
    }

    func testComparable() {
        XCTAssertLessThan(Time(value: 1, timescale: 600), Time(value: 2, timescale: 600))
        XCTAssertLessThan(Time(value: 1, timescale: 3), Time(value: 1, timescale: 2))
    }

    func testScaleByRatio() {
        let a = Time(value: 600, timescale: 600) // 1s
        XCTAssertEqual((a * 0.5).seconds, 0.5, accuracy: 1e-9)
    }

    func testClamp() {
        let lo = Time(value: 0, timescale: 600)
        let hi = Time(value: 600, timescale: 600)
        XCTAssertEqual(Time(value: -10, timescale: 600).clamped(to: lo...hi), lo)
        XCTAssertEqual(Time(value: 900, timescale: 600).clamped(to: lo...hi), hi)
        XCTAssertEqual(Time(value: 300, timescale: 600).clamped(to: lo...hi), Time(value: 300, timescale: 600))
    }

    func testFcpxmlString() {
        XCTAssertEqual(Time(value: 3600, timescale: 600).fcpxmlString, "3600/600s")
        XCTAssertEqual(Time.zero.fcpxmlString, "0s")
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter TimeTests`
Expected: FAIL（`cannot find 'Time' in scope`）。

- [ ] **Step 3: 实现 Time**

`Sources/FCPXLite/Models/Time.swift`:
```swift
import Foundation

/// 有理数时间(CMTime 语义)。时间线上所有位置/时长都用它,避免浮点累积误差。
struct Time: Equatable, Comparable, Hashable, Codable {
    var value: Int64
    var timescale: Int32

    init(value: Int64, timescale: Int32) {
        precondition(timescale > 0, "timescale 必须为正")
        self.value = value
        self.timescale = timescale
    }

    static let zero = Time(value: 0, timescale: 600)

    static func seconds(_ s: Double, timescale: Int32 = 600) -> Time {
        Time(value: Int64((s * Double(timescale)).rounded()), timescale: timescale)
    }

    var seconds: Double { Double(value) / Double(timescale) }

    private static func commonize(_ a: Time, _ b: Time) -> (Int64, Int64, Int32) {
        if a.timescale == b.timescale { return (a.value, b.value, a.timescale) }
        let ts = lcm(a.timescale, b.timescale)
        let av = a.value * Int64(ts / a.timescale)
        let bv = b.value * Int64(ts / b.timescale)
        return (av, bv, ts)
    }

    static func + (l: Time, r: Time) -> Time {
        let (a, b, ts) = commonize(l, r)
        return Time(value: a + b, timescale: ts)
    }

    static func - (l: Time, r: Time) -> Time {
        let (a, b, ts) = commonize(l, r)
        return Time(value: a - b, timescale: ts)
    }

    static func * (l: Time, ratio: Double) -> Time {
        Time(value: Int64((Double(l.value) * ratio).rounded()), timescale: l.timescale)
    }

    static func < (l: Time, r: Time) -> Bool {
        let (a, b, _) = commonize(l, r)
        return a < b
    }

    static func == (l: Time, r: Time) -> Bool {
        let (a, b, _) = commonize(l, r)
        return a == b
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(seconds)
    }

    func clamped(to range: ClosedRange<Time>) -> Time {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }

    var fcpxmlString: String {
        value == 0 ? "0s" : "\(value)/\(timescale)s"
    }
}

private func gcd(_ a: Int32, _ b: Int32) -> Int32 {
    var a = abs(a), b = abs(b)
    while b != 0 { (a, b) = (b, a % b) }
    return a == 0 ? 1 : a
}
private func lcm(_ a: Int32, _ b: Int32) -> Int32 {
    a / gcd(a, b) * b
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter TimeTests`
Expected: PASS（6 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Models/Time.swift Tests/FCPXLiteTests/TimeTests.swift
git commit -m "feat: 有理数 Time 类型(帧精度时间基础)"
```

---

## Task 3: 强类型 ID 与 Asset / Adjustments 值类型

**Files:**
- Create: `Sources/FCPXLite/Models/Ids.swift`
- Create: `Sources/FCPXLite/Models/Asset.swift`
- Create: `Sources/FCPXLite/Models/Adjustments.swift`
- Test: `Tests/FCPXLiteTests/ModelValueTests.swift`

**Interfaces:**
- Consumes: `Time`
- Produces:
  - `struct AssetID: Hashable, Codable` / `struct ClipID: Hashable, Codable`,各有 `init()` 生成唯一值 + `let raw: String`
  - `enum MediaKind: String, Codable { case video, audio, image }`
  - `struct Asset: Identifiable, Codable, Equatable { let id: AssetID; var url: URL; var kind: MediaKind; var duration: Time; var naturalSize: CGSize; var frameRate: Double?; var hasAudio: Bool }`
  - `struct Transform: Codable, Equatable { var position = CGPoint.zero; var scale = CGSize(width:1,height:1); var rotation = 0.0; var anchor = CGPoint.zero }`
  - `struct Crop: Codable, Equatable { var left=0.0; var right=0.0; var top=0.0; var bottom=0.0 }`
  - `struct Adjustments: Codable, Equatable { var transform = Transform(); var crop = Crop(); var opacity = 1.0; var volume = 1.0 }`

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/ModelValueTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class ModelValueTests: XCTestCase {
    func testIdsUnique() {
        XCTAssertNotEqual(AssetID(), AssetID())
        XCTAssertNotEqual(ClipID(), ClipID())
    }

    func testAdjustmentsDefaults() {
        let a = Adjustments()
        XCTAssertEqual(a.opacity, 1.0)
        XCTAssertEqual(a.volume, 1.0)
        XCTAssertEqual(a.transform.scale, CGSize(width: 1, height: 1))
    }

    func testAssetCodableRoundTrip() throws {
        let asset = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"),
                          kind: .video, duration: Time(value: 600, timescale: 600),
                          naturalSize: CGSize(width: 1920, height: 1080),
                          frameRate: 25, hasAudio: true)
        let data = try JSONEncoder().encode(asset)
        let back = try JSONDecoder().decode(Asset.self, from: data)
        XCTAssertEqual(asset, back)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter ModelValueTests`
Expected: FAIL（类型未定义）。

- [ ] **Step 3: 实现三个文件**

`Sources/FCPXLite/Models/Ids.swift`:
```swift
import Foundation

struct AssetID: Hashable, Codable {
    let raw: String
    init() { raw = UUID().uuidString }
    init(raw: String) { self.raw = raw }
}

struct ClipID: Hashable, Codable {
    let raw: String
    init() { raw = UUID().uuidString }
    init(raw: String) { self.raw = raw }
}
```

`Sources/FCPXLite/Models/Asset.swift`:
```swift
import Foundation

enum MediaKind: String, Codable { case video, audio, image }

/// 素材库条目:只引用源文件,不拷贝/不转码。
struct Asset: Identifiable, Codable, Equatable {
    let id: AssetID
    var url: URL
    var kind: MediaKind
    var duration: Time
    var naturalSize: CGSize
    var frameRate: Double?
    var hasAudio: Bool
}
```

`Sources/FCPXLite/Models/Adjustments.swift`:
```swift
import Foundation

struct Transform: Codable, Equatable {
    var position = CGPoint.zero
    var scale = CGSize(width: 1, height: 1)
    var rotation = 0.0
    var anchor = CGPoint.zero
}

struct Crop: Codable, Equatable {
    var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0
}

/// Inspector 可调参数,挂在 clip 上。对齐 FCPXML <adjust-*>。
struct Adjustments: Codable, Equatable {
    var transform = Transform()
    var crop = Crop()
    var opacity = 1.0   // → <adjust-blend> / video opacity
    var volume = 1.0    // → <adjust-volume>
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter ModelValueTests`
Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Models/Ids.swift Sources/FCPXLite/Models/Asset.swift Sources/FCPXLite/Models/Adjustments.swift Tests/FCPXLiteTests/ModelValueTests.swift
git commit -m "feat: 强类型 ID + Asset + Adjustments 值类型"
```

---

## Task 4: 文档模型 Clip / Element / Spine / Document

**Files:**
- Create: `Sources/FCPXLite/Document/Clip.swift`
- Create: `Sources/FCPXLite/Document/Element.swift`
- Create: `Sources/FCPXLite/Document/Spine.swift`
- Test: `Tests/FCPXLiteTests/DocumentModelTests.swift`
- Delete: `Sources/FCPXLite/Placeholder.swift`(不再需要;executable 已有真实类型)

**Interfaces:**
- Consumes: `Time`、`ClipID`、`AssetID`、`Adjustments`
- Produces:
  - `struct Clip: Identifiable, Codable, Equatable { let id: ClipID; var assetID: AssetID; var sourceIn: Time; var duration: Time; var connected: [Clip]; var lane: Int; var offset: Time; var adjust: Adjustments }`,含便利 `init(assetID:sourceIn:duration:)`(connected=[], lane=0, offset=.zero, adjust=Adjustments())
  - `enum Element: Codable, Equatable { case clip(Clip); case gap(duration: Time) }`,含 `var duration: Time`、`var asClip: Clip?`
  - `struct Sequence: Codable, Equatable { var spine: [Element] }`
  - `struct Project: Codable, Equatable { var formatWidth: Int; var formatHeight: Int; var frameRate: Double; var assetLibrary: [Asset]; var sequence: Sequence }`
  - `typealias Document = Project`

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/DocumentModelTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class DocumentModelTests: XCTestCase {
    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    func testElementDuration() {
        XCTAssertEqual(Element.gap(duration: .seconds(2)).duration, .seconds(2))
        XCTAssertEqual(Element.clip(clip(3)).duration, .seconds(3))
    }

    func testElementAsClip() {
        XCTAssertNil(Element.gap(duration: .seconds(1)).asClip)
        XCTAssertNotNil(Element.clip(clip(1)).asClip)
    }

    func testEmptyDocument() {
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: []))
        XCTAssertTrue(doc.sequence.spine.isEmpty)
    }

    func testDocumentCodableRoundTrip() throws {
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [],
                           sequence: Sequence(spine: [.clip(clip(2)), .gap(duration: .seconds(1))]))
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertEqual(doc, back)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter DocumentModelTests`
Expected: FAIL（类型未定义）。

- [ ] **Step 3: 实现三个文件并删除占位**

`Sources/FCPXLite/Document/Clip.swift`:
```swift
import Foundation

/// 时间线片段。引用 asset,自己只存 in/out。
/// connected/lane/offset 仅用于连接片段(L2/L3);spine 上的 clip lane 恒为 0。
struct Clip: Identifiable, Codable, Equatable {
    let id: ClipID
    var assetID: AssetID
    var sourceIn: Time
    var duration: Time
    var connected: [Clip]
    var lane: Int
    var offset: Time          // 相对【宿主 clip 起点】
    var adjust: Adjustments

    init(id: ClipID = ClipID(), assetID: AssetID, sourceIn: Time, duration: Time,
         connected: [Clip] = [], lane: Int = 0, offset: Time = .zero,
         adjust: Adjustments = Adjustments()) {
        self.id = id; self.assetID = assetID
        self.sourceIn = sourceIn; self.duration = duration
        self.connected = connected; self.lane = lane
        self.offset = offset; self.adjust = adjust
    }
}
```

`Sources/FCPXLite/Document/Element.swift`:
```swift
import Foundation

/// 主轴元素:clip 或显式空隙(gap)。
enum Element: Codable, Equatable {
    case clip(Clip)
    case gap(duration: Time)

    var duration: Time {
        switch self {
        case .clip(let c): return c.duration
        case .gap(let d): return d
        }
    }

    var asClip: Clip? {
        if case .clip(let c) = self { return c }
        return nil
    }
}
```

`Sources/FCPXLite/Document/Spine.swift`:
```swift
import Foundation

/// 主时间线:有序元素数组,首尾相接,磁性隐含在顺序里。
struct Sequence: Codable, Equatable {
    var spine: [Element]
}

struct Project: Codable, Equatable {
    var formatWidth: Int
    var formatHeight: Int
    var frameRate: Double
    var assetLibrary: [Asset]
    var sequence: Sequence
}

typealias Document = Project
```

删除占位文件:
```bash
rm Sources/FCPXLite/Placeholder.swift
```
并把 `Tests/FCPXLiteTests/SmokeTest.swift` 改为引用真实类型(避免引用已删除的 `BuildSmoke`):
```swift
import XCTest
@testable import FCPXLite

final class SmokeTest: XCTestCase {
    func testModuleLoads() {
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: []))
        XCTAssertEqual(doc.formatWidth, 1920)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test`
Expected: PASS（含 SmokeTest 重写后的 1 个 + DocumentModelTests 4 个 + 之前的）。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: 文档模型 Clip/Element/Spine/Document(FCPXML 对齐)"
```

---

## Task 5: 布局引擎 `layout`(前缀和,绝对起点实时算)

**Files:**
- Create: `Sources/FCPXLite/Document/Magnetic/Layout.swift`
- Test: `Tests/FCPXLiteTests/LayoutTests.swift`

**Interfaces:**
- Consumes: `Document`、`Element`、`Clip`、`Time`
- Produces:
  - `struct Placed: Equatable { let clipID: ClipID; let absStart: Time; let duration: Time; let lane: Int; let isConnected: Bool }`
  - `enum Layout { static func compute(_ sequence: Sequence) -> [Placed] }`
    - 主轴元素 lane=0,absStart = 前缀和;gap 不产出 Placed 但推进时间。
    - 每个主轴 clip 的 connected 子项:absStart = 宿主 absStart + offset,lane = 子项 lane,isConnected=true。
    - 输出顺序:按 absStart 升序,同 absStart 按 lane 升序(确定性)。

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/LayoutTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class LayoutTests: XCTestCase {
    private func clip(_ secs: Double, lane: Int = 0, offset: Time = .zero,
                      connected: [Clip] = []) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs),
             connected: connected, lane: lane, offset: offset)
    }

    func testPrefixSumPositions() {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3)), .clip(clip(1))])
        let placed = Layout.compute(seq)
        XCTAssertEqual(placed.map(\.absStart), [.seconds(0), .seconds(2), .seconds(5)])
    }

    func testGapAdvancesTimeButNoPlaced() {
        let seq = Sequence(spine: [.clip(clip(2)), .gap(duration: .seconds(4)), .clip(clip(1))])
        let placed = Layout.compute(seq)
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed.last?.absStart, .seconds(6)) // 2 + 4
    }

    func testConnectedClipAnchoredToHostStart() {
        // 主轴: A(2s) 起点0, B(3s) 起点2; B 上挂 connected offset=1, lane=1
        let conn = clip(1, lane: 1, offset: .seconds(1))
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3, connected: [conn]))])
        let placed = Layout.compute(seq)
        let c = placed.first { $0.isConnected }
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.absStart, .seconds(3)) // 宿主起点2 + offset1
        XCTAssertEqual(c?.lane, 1)
    }

    func testDeterministicOrdering() {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        XCTAssertEqual(Layout.compute(seq), Layout.compute(seq))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LayoutTests`
Expected: FAIL（`Layout` / `Placed` 未定义）。

- [ ] **Step 3: 实现 Layout**

`Sources/FCPXLite/Document/Magnetic/Layout.swift`:
```swift
import Foundation

/// 算出来的绝对位置(不存储在文档里)。供画布绘制与合成引擎使用。
struct Placed: Equatable {
    let clipID: ClipID
    let absStart: Time
    let duration: Time
    let lane: Int
    let isConnected: Bool
}

/// 纯函数布局:Sequence → [Placed]。磁性的"绝对位置"在这里实时算。
enum Layout {
    static func compute(_ sequence: Sequence) -> [Placed] {
        var out: [Placed] = []
        var t = Time.zero
        for element in sequence.spine {
            if case .clip(let c) = element {
                out.append(Placed(clipID: c.id, absStart: t, duration: c.duration,
                                  lane: 0, isConnected: false))
                for conn in c.connected {
                    out.append(Placed(clipID: conn.id, absStart: t + conn.offset,
                                      duration: conn.duration, lane: conn.lane,
                                      isConnected: true))
                }
            }
            t = t + element.duration
        }
        return out.sorted {
            if $0.absStart != $1.absStart { return $0.absStart < $1.absStart }
            return $0.lane < $1.lane
        }
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter LayoutTests`
Expected: PASS（4 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Document/Magnetic/Layout.swift Tests/FCPXLiteTests/LayoutTests.swift
git commit -m "feat: 布局引擎 layout(前缀和,绝对起点实时算)"
```

---

## Task 6: 不变量校验 `Invariants`

**Files:**
- Create: `Sources/FCPXLite/Document/Magnetic/Invariants.swift`
- Test: `Tests/FCPXLiteTests/InvariantTests.swift`

**Interfaces:**
- Consumes: `Sequence`、`Layout`、`Placed`
- Produces:
  - `enum InvariantViolation: Error, Equatable { case spineOverlap; case laneCollision; case negativeDuration }`
  - `enum Invariants { static func check(_ sequence: Sequence) throws }`
    - 主轴连续:lane 0 元素首尾相接(layout 已保证,但校验无负时长、无零时长 clip)。
    - 泳道隔离:同一时间区间 [absStart, absStart+duration) 内,connected clip 的 lane 互不重复重叠。
    - 无负/零时长。

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/InvariantTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class InvariantTests: XCTestCase {
    private func clip(_ secs: Double, lane: Int = 0, offset: Time = .zero,
                      connected: [Clip] = []) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs),
             connected: connected, lane: lane, offset: offset)
    }

    func testValidSequencePasses() throws {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        XCTAssertNoThrow(try Invariants.check(seq))
    }

    func testLaneCollisionThrows() {
        // 同一宿主上两个 connected,时间重叠且同 lane → 冲突
        let a = clip(2, lane: 1, offset: .seconds(0))
        let b = clip(2, lane: 1, offset: .seconds(1)) // 与 a 在 [1,2) 重叠且同 lane
        let seq = Sequence(spine: [.clip(clip(5, connected: [a, b]))])
        XCTAssertThrowsError(try Invariants.check(seq)) { err in
            XCTAssertEqual(err as? InvariantViolation, .laneCollision)
        }
    }

    func testLaneSeparationPasses() throws {
        let a = clip(2, lane: 1, offset: .seconds(0))
        let b = clip(2, lane: 2, offset: .seconds(1)) // 重叠但不同 lane → OK
        let seq = Sequence(spine: [.clip(clip(5, connected: [a, b]))])
        XCTAssertNoThrow(try Invariants.check(seq))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter InvariantTests`
Expected: FAIL（`Invariants` 未定义）。

- [ ] **Step 3: 实现 Invariants**

`Sources/FCPXLite/Document/Magnetic/Invariants.swift`:
```swift
import Foundation

enum InvariantViolation: Error, Equatable {
    case spineOverlap
    case laneCollision
    case negativeDuration
}

/// 三条磁性不变量校验。命令层每次 mutation 后调用(debug 断言;测试显式调用)。
enum Invariants {
    static func check(_ sequence: Sequence) throws {
        // 不变量 1/3:无负/零时长
        for el in sequence.spine {
            if el.duration.seconds <= 0 { throw InvariantViolation.negativeDuration }
            if case .clip(let c) = el {
                for conn in c.connected where conn.duration.seconds <= 0 {
                    throw InvariantViolation.negativeDuration
                }
            }
        }
        // 不变量 3:泳道隔离 —— 同 lane 的 connected 不得时间重叠
        let placed = Layout.compute(sequence).filter(\.isConnected)
        for i in placed.indices {
            for j in placed.indices where j > i {
                let a = placed[i], b = placed[j]
                guard a.lane == b.lane else { continue }
                let aEnd = a.absStart + a.duration
                let bEnd = b.absStart + b.duration
                let overlap = a.absStart < bEnd && b.absStart < aEnd
                if overlap { throw InvariantViolation.laneCollision }
            }
        }
        // 不变量 1(主轴连续)由 layout 前缀和结构保证,无需额外校验重叠。
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter InvariantTests`
Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Document/Magnetic/Invariants.swift Tests/FCPXLiteTests/InvariantTests.swift
git commit -m "feat: 三条磁性不变量校验"
```

---

## Task 7: 吸附 `Snapping`(纯函数)

**Files:**
- Create: `Sources/FCPXLite/Document/Magnetic/Snapping.swift`
- Test: `Tests/FCPXLiteTests/SnappingTests.swift`

**Interfaces:**
- Consumes: `Time`
- Produces:
  - `enum Snapping { static func snap(_ t: Time, candidates: [Time], threshold: Time) -> Time }`
    - 返回距离 `t` 最近且 ≤ threshold 的候选;否则返回原 `t`。多个等距取最小 Time。

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/SnappingTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class SnappingTests: XCTestCase {
    func testSnapsToNearestWithinThreshold() {
        let t = Time.seconds(2.03)
        let r = Snapping.snap(t, candidates: [.seconds(2.0), .seconds(5.0)],
                              threshold: .seconds(0.05))
        XCTAssertEqual(r, .seconds(2.0))
    }

    func testNoSnapBeyondThreshold() {
        let t = Time.seconds(2.5)
        let r = Snapping.snap(t, candidates: [.seconds(2.0)], threshold: .seconds(0.05))
        XCTAssertEqual(r, t)
    }

    func testEmptyCandidatesReturnsInput() {
        let t = Time.seconds(1.0)
        XCTAssertEqual(Snapping.snap(t, candidates: [], threshold: .seconds(1)), t)
    }

    func testPicksNearestAmongMany() {
        let t = Time.seconds(4.96)
        let r = Snapping.snap(t, candidates: [.seconds(2), .seconds(5), .seconds(8)],
                              threshold: .seconds(0.1))
        XCTAssertEqual(r, .seconds(5))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter SnappingTests`
Expected: FAIL（`Snapping` 未定义）。

- [ ] **Step 3: 实现 Snapping**

`Sources/FCPXLite/Document/Magnetic/Snapping.swift`:
```swift
import Foundation

/// 纯函数吸附。threshold 由画布把"像素阈值 ÷ 缩放"换算成时间传入;引擎不碰像素。
enum Snapping {
    static func snap(_ t: Time, candidates: [Time], threshold: Time) -> Time {
        var best: Time? = nil
        var bestDist = threshold
        for c in candidates {
            let dist = c >= t ? (c - t) : (t - c)
            if dist < bestDist || (dist == bestDist && (best == nil || c < best!)) {
                if dist <= threshold {
                    bestDist = dist
                    best = c
                }
            }
        }
        return best ?? t
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter SnappingTests`
Expected: PASS（4 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Document/Magnetic/Snapping.swift Tests/FCPXLiteTests/SnappingTests.swift
git commit -m "feat: 纯函数吸附 Snapping"
```

---

## Task 8: 命令层 `Mutations` — 插入 / ripple 删除 / lift 留洞

**Files:**
- Create: `Sources/FCPXLite/Document/Magnetic/Mutations.swift`
- Test: `Tests/FCPXLiteTests/MutationInsertDeleteTests.swift`

**Interfaces:**
- Consumes: `Sequence`、`Element`、`Clip`、`Invariants`
- Produces(命令层第一批,全部为 `Sequence → Sequence` 纯函数,内部 `assert(try Invariants.check)`):
  - `enum Mutations { ... }`
  - `static func insertClip(_ clip: Clip, at index: Int, in seq: Sequence) -> Sequence`
  - `static func rippleDelete(at index: Int, in seq: Sequence) -> Sequence`(移除元素,后续自动合拢)
  - `static func liftDelete(at index: Int, in seq: Sequence) -> Sequence`(替换为等长 gap,保留空隙)
  - 私有 `static func assertInvariants(_ seq: Sequence)`(debug 断言,fail fast)

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/MutationInsertDeleteTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class MutationInsertDeleteTests: XCTestCase {
    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    func testInsertShiftsLaterClips() {
        let seq0 = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        let seq1 = Mutations.insertClip(clip(1), at: 1, in: seq0)
        let pos = Layout.compute(seq1).map(\.absStart)
        // [A(2)@0, NEW(1)@2, B(3)@3]
        XCTAssertEqual(pos, [.seconds(0), .seconds(2), .seconds(3)])
    }

    func testRippleDeleteCollapsesGap() {
        let seq0 = Sequence(spine: [.clip(clip(2)), .clip(clip(3)), .clip(clip(1))])
        let seq1 = Mutations.rippleDelete(at: 1, in: seq0) // 删中间 3s
        let pos = Layout.compute(seq1).map(\.absStart)
        // [A(2)@0, C(1)@2]  ← 合拢
        XCTAssertEqual(pos, [.seconds(0), .seconds(2)])
    }

    func testLiftDeleteKeepsHole() {
        let seq0 = Sequence(spine: [.clip(clip(2)), .clip(clip(3)), .clip(clip(1))])
        let seq1 = Mutations.liftDelete(at: 1, in: seq0)
        let pos = Layout.compute(seq1).map(\.absStart)
        // gap 占位,C 仍在 @5
        XCTAssertEqual(pos, [.seconds(0), .seconds(5)])
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter MutationInsertDeleteTests`
Expected: FAIL（`Mutations` 未定义）。

- [ ] **Step 3: 实现 Mutations(第一批)**

`Sources/FCPXLite/Document/Magnetic/Mutations.swift`:
```swift
import Foundation

/// 命令层:唯一的文档修改入口。手动 UI 与未来 Agent 工具都只调这里。
/// 每个命令是 Sequence → Sequence 纯函数,执行后断言三条不变量(fail fast)。
enum Mutations {

    static func insertClip(_ clip: Clip, at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        let i = max(0, min(index, s.spine.count))
        s.spine.insert(.clip(clip), at: i)
        assertInvariants(s)
        return s
    }

    /// ripple 删除(默认):移除元素,后续自动左移合拢。
    static func rippleDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        s.spine.remove(at: index)
        assertInvariants(s)
        return s
    }

    /// lift 删除:替换为等长 gap,保留空隙。
    static func liftDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        let d = s.spine[index].duration
        s.spine[index] = .gap(duration: d)
        assertInvariants(s)
        return s
    }

    static func assertInvariants(_ seq: Sequence) {
        #if DEBUG
        do { try Invariants.check(seq) }
        catch { assertionFailure("磁性不变量被破坏: \(error)") }
        #endif
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter MutationInsertDeleteTests`
Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Document/Magnetic/Mutations.swift Tests/FCPXLiteTests/MutationInsertDeleteTests.swift
git commit -m "feat: 命令层 insert/rippleDelete/liftDelete"
```

---

## Task 9: 命令层 — 主轴内移动 + ripple trim

**Files:**
- Modify: `Sources/FCPXLite/Document/Magnetic/Mutations.swift`(追加方法)
- Test: `Tests/FCPXLiteTests/MutationMoveTrimTests.swift`

**Interfaces:**
- Consumes: 同 Task 8 + `Asset`(用于 trim 边界夹紧需要 asset 时长 —— 通过参数传入避免耦合素材库)
- Produces(追加到 `Mutations`):
  - `static func moveClip(from: Int, to: Int, in seq: Sequence) -> Sequence`(主轴内换序 = remove+insert)
  - `static func rippleTrimRight(at index: Int, newDuration: Time, assetDuration: Time, in seq: Sequence) -> Sequence`(改右边缘 duration,夹在 `sourceIn..assetDuration`)
  - `static func rippleTrimLeft(at index: Int, deltaIn: Time, assetDuration: Time, in seq: Sequence) -> Sequence`(改左边缘:同时调 sourceIn 与 duration,clip 起点跟随前缀和)

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/MutationMoveTrimTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class MutationMoveTrimTests: XCTestCase {
    private func clip(_ secs: Double, sourceIn: Time = .zero) -> Clip {
        Clip(assetID: AssetID(), sourceIn: sourceIn, duration: .seconds(secs))
    }

    func testMoveReorders() {
        let a = clip(2), b = clip(3), c = clip(1)
        let seq0 = Sequence(spine: [.clip(a), .clip(b), .clip(c)])
        let seq1 = Mutations.moveClip(from: 0, to: 2, in: seq0) // A 移到末尾
        let ids = seq1.spine.compactMap { $0.asClip?.id }
        XCTAssertEqual(ids, [b.id, c.id, a.id])
        // 位置:B(3)@0, C(1)@3, A(2)@4
        XCTAssertEqual(Layout.compute(seq1).map(\.absStart),
                       [.seconds(0), .seconds(3), .seconds(4)])
    }

    func testRippleTrimRightShortens() {
        let seq0 = Sequence(spine: [.clip(clip(5)), .clip(clip(2))])
        // 把第0个从 5s 裁到 3s,素材总长 10s
        let seq1 = Mutations.rippleTrimRight(at: 0, newDuration: .seconds(3),
                                             assetDuration: .seconds(10), in: seq0)
        XCTAssertEqual(seq1.spine[0].duration, .seconds(3))
        // 后续 clip 跟着左移:第二个 @3
        XCTAssertEqual(Layout.compute(seq1).map(\.absStart), [.seconds(0), .seconds(3)])
    }

    func testRippleTrimRightClampsToAsset() {
        let seq0 = Sequence(spine: [.clip(clip(5))])
        // 试图裁长到 20s,但素材只有 8s(sourceIn=0)→ 夹到 8s
        let seq1 = Mutations.rippleTrimRight(at: 0, newDuration: .seconds(20),
                                             assetDuration: .seconds(8), in: seq0)
        XCTAssertEqual(seq1.spine[0].duration, .seconds(8))
    }

    func testRippleTrimLeftAdjustsSourceInAndDuration() {
        // clip sourceIn=2, duration=5(用素材 [2,7]);左边缘内移 1s → sourceIn=3, duration=4
        let seq0 = Sequence(spine: [.clip(clip(5, sourceIn: .seconds(2)))])
        let seq1 = Mutations.rippleTrimLeft(at: 0, deltaIn: .seconds(1),
                                            assetDuration: .seconds(10), in: seq0)
        XCTAssertEqual(seq1.spine[0].asClip?.sourceIn, .seconds(3))
        XCTAssertEqual(seq1.spine[0].duration, .seconds(4))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter MutationMoveTrimTests`
Expected: FAIL（方法未定义）。

- [ ] **Step 3: 追加实现**

在 `Mutations` 中追加(放在 `assertInvariants` 之前):
```swift
    /// 主轴内移动/换序 = remove + insert(等价于一次 ripple)。
    static func moveClip(from: Int, to: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(from) else { return s }
        let el = s.spine.remove(at: from)
        let dest = max(0, min(to, s.spine.count))
        s.spine.insert(el, at: dest)
        assertInvariants(s)
        return s
    }

    /// ripple trim 右边缘:改 duration,夹在 (0, assetDuration - sourceIn]。
    static func rippleTrimRight(at index: Int, newDuration: Time,
                                assetDuration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard case .clip(var c) = s.spine[index] else { return s }
        let maxDur = assetDuration - c.sourceIn
        let minDur = Time(value: 1, timescale: maxDur.timescale) // 至少 1 个 timescale 单位
        guard minDur <= maxDur else { return s }                 // 素材已无可用余量,放弃
        c.duration = newDuration.clamped(to: minDur...maxDur)
        s.spine[index] = .clip(c)
        assertInvariants(s)
        return s
    }

    /// ripple trim 左边缘:同时调 sourceIn(+delta)与 duration(-delta),夹在素材内。
    static func rippleTrimLeft(at index: Int, deltaIn: Time,
                               assetDuration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard case .clip(var c) = s.spine[index] else { return s }
        // 新 sourceIn 不得 < 0,也不得使 duration ≤ 0
        let newSourceIn = (c.sourceIn + deltaIn).clamped(
            to: Time.zero...(c.sourceIn + c.duration - Time(value: 1, timescale: c.duration.timescale)))
        let consumed = newSourceIn - c.sourceIn
        c.sourceIn = newSourceIn
        c.duration = c.duration - consumed
        s.spine[index] = .clip(c)
        assertInvariants(s)
        return s
    }
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter MutationMoveTrimTests`
Expected: PASS（4 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Document/Magnetic/Mutations.swift Tests/FCPXLiteTests/MutationMoveTrimTests.swift
git commit -m "feat: 命令层 moveClip + ripple trim(左右边缘,素材边界夹紧)"
```

---

## Task 10: 命令层 — blade 切割 + connect 连接片段

**Files:**
- Modify: `Sources/FCPXLite/Document/Magnetic/Mutations.swift`(追加方法)
- Test: `Tests/FCPXLiteTests/MutationBladeConnectTests.swift`

**Interfaces:**
- Consumes: 同上
- Produces(追加到 `Mutations`):
  - `static func blade(at index: Int, localTime: Time, in seq: Sequence) -> Sequence`
    - 在主轴第 index 个 clip 内部 localTime(相对该 clip 起点)处切两半,共享 assetID;左 `sourceIn`=原,`duration`=localTime;右 `sourceIn`=原+localTime,`duration`=原-localTime。
    - connected 子项按各自 offset 归到左/右半(offset < localTime 留左;否则归右并 `offset -= localTime`)。
  - `static func connectClip(_ clip: Clip, toHostIndex: Int, lane: Int, offset: Time, in seq: Sequence) -> Sequence`
    - 把 clip 作为 connected 挂到主轴第 toHostIndex 个 clip,设定 lane/offset。

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/MutationBladeConnectTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class MutationBladeConnectTests: XCTestCase {
    private func clip(_ secs: Double, sourceIn: Time = .zero, connected: [Clip] = []) -> Clip {
        Clip(assetID: AssetID(), sourceIn: sourceIn, duration: .seconds(secs), connected: connected)
    }

    func testBladeSplitsIntoTwoSharingAsset() {
        let original = clip(6, sourceIn: .seconds(1))
        let seq0 = Sequence(spine: [.clip(original)])
        let seq1 = Mutations.blade(at: 0, localTime: .seconds(2), in: seq0) // 在 clip 内 2s 处切
        XCTAssertEqual(seq1.spine.count, 2)
        let left = seq1.spine[0].asClip!
        let right = seq1.spine[1].asClip!
        XCTAssertEqual(left.assetID, right.assetID)          // 共享素材
        XCTAssertEqual(left.assetID, original.assetID)
        XCTAssertEqual(left.duration, .seconds(2))
        XCTAssertEqual(right.duration, .seconds(4))           // 6 - 2
        XCTAssertEqual(left.sourceIn, .seconds(1))
        XCTAssertEqual(right.sourceIn, .seconds(3))           // 1 + 2
    }

    func testBladeRoutesConnectedToCorrectHalf() {
        let connLeft = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                            lane: 1, offset: .seconds(0.5))   // 在 2s 切点之前 → 留左
        let connRight = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                             lane: 1, offset: .seconds(3))    // 切点之后 → 归右, offset-2
        let original = clip(6, connected: [connLeft, connRight])
        let seq1 = Mutations.blade(at: 0, localTime: .seconds(2),
                                   in: Sequence(spine: [.clip(original)]))
        XCTAssertEqual(seq1.spine[0].asClip!.connected.count, 1)
        XCTAssertEqual(seq1.spine[1].asClip!.connected.count, 1)
        XCTAssertEqual(seq1.spine[1].asClip!.connected[0].offset, .seconds(1)) // 3 - 2
    }

    func testConnectAttachesToHost() {
        let host = clip(5)
        let conn = clip(2)
        let seq1 = Mutations.connectClip(conn, toHostIndex: 0, lane: 1, offset: .seconds(1),
                                         in: Sequence(spine: [.clip(host)]))
        let attached = seq1.spine[0].asClip!.connected
        XCTAssertEqual(attached.count, 1)
        XCTAssertEqual(attached[0].lane, 1)
        XCTAssertEqual(attached[0].offset, .seconds(1))
        // layout 中它锚在宿主起点(0)+offset(1) = 1s
        let placedConn = Layout.compute(seq1).first { $0.isConnected }
        XCTAssertEqual(placedConn?.absStart, .seconds(1))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter MutationBladeConnectTests`
Expected: FAIL（方法未定义）。

- [ ] **Step 3: 追加实现**

在 `Mutations` 中追加:
```swift
    /// 在主轴第 index 个 clip 内部 localTime(相对该 clip 起点)处切两半。
    static func blade(at index: Int, localTime: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard case .clip(let c) = s.spine[index] else { return s }
        guard localTime > .zero, localTime < c.duration else { return s } // 边界不切

        var left = c
        left.duration = localTime
        left.connected = c.connected.filter { $0.offset < localTime }

        var right = Clip(assetID: c.assetID,
                         sourceIn: c.sourceIn + localTime,
                         duration: c.duration - localTime,
                         connected: c.connected
                            .filter { $0.offset >= localTime }
                            .map { var x = $0; x.offset = x.offset - localTime; return x },
                         adjust: c.adjust)

        s.spine.replaceSubrange(index...index, with: [.clip(left), .clip(right)])
        assertInvariants(s)
        return s
    }

    /// 把 clip 作为连接片段挂到主轴第 toHostIndex 个 clip 上。
    static func connectClip(_ clip: Clip, toHostIndex: Int, lane: Int, offset: Time,
                            in seq: Sequence) -> Sequence {
        var s = seq
        guard case .clip(var host) = s.spine[toHostIndex] else { return s }
        var conn = clip
        conn.lane = lane
        conn.offset = offset
        host.connected.append(conn)
        s.spine[toHostIndex] = .clip(host)
        assertInvariants(s)
        return s
    }
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter MutationBladeConnectTests`
Expected: PASS（3 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Document/Magnetic/Mutations.swift Tests/FCPXLiteTests/MutationBladeConnectTests.swift
git commit -m "feat: 命令层 blade 切割 + connectClip 连接片段"
```

---

## Task 11: 控制变量对照实验框架(spec §8)

**Files:**
- Create: `Sources/FCPXLite/Document/Magnetic/ExperimentReport.swift`
- Test: `Tests/FCPXLiteTests/InvariantPropertyTests.swift`

**Interfaces:**
- Consumes: `Sequence`、`Layout`、`Invariants`、`Mutations`
- Produces:
  - `struct PlacementRow: Equatable { let clipID: String; let absStartSeconds: Double; let durationSeconds: Double; let lane: Int }`
  - `enum ExperimentReport { static func placementTable(_ seq: Sequence) -> [PlacementRow]; static func csv(_ seq: Sequence) -> String }`(导出对照数据)

实现 spec §8 的四类对照实验作为测试:A/B(加 vs 不加吸附)、顺序对照(ABC vs BCA)、参数扫描(trim duration 1..10)、多维矩阵(位置×类型×lane)。每个实验断言三条不变量恒成立 + 输出可比对的位置表。

- [ ] **Step 1: 写实验报告 + 属性测试**

`Tests/FCPXLiteTests/InvariantPropertyTests.swift`:
```swift
import XCTest
@testable import FCPXLite

/// spec §8 控制变量对照实验:用数据驱动证明磁性引擎正确,杜绝肉眼猜测。
final class InvariantPropertyTests: XCTestCase {
    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    // 多维矩阵:一批操作随机序列,每步断言三不变量恒成立。固定种子可复现。
    func testRandomOperationSequencesPreserveInvariants() {
        var rng = SeededRNG(seed: 42)
        for _ in 0..<200 {
            var seq = Sequence(spine: (0..<5).map { _ in
                Element.clip(clip(Double(rng.next(in: 1...5))))
            })
            for _ in 0..<10 {
                let op = rng.next(in: 0...3)
                let n = seq.spine.count
                guard n > 0 else { break }
                switch op {
                case 0: seq = Mutations.insertClip(clip(2), at: rng.next(in: 0...n), in: seq)
                case 1: seq = Mutations.rippleDelete(at: rng.next(in: 0...(n-1)), in: seq)
                case 2: seq = Mutations.moveClip(from: rng.next(in: 0...(n-1)),
                                                 to: rng.next(in: 0...(n-1)), in: seq)
                default: seq = Mutations.liftDelete(at: rng.next(in: 0...(n-1)), in: seq)
                }
                XCTAssertNoThrow(try Invariants.check(seq), "操作序列破坏了不变量")
            }
        }
    }

    // 顺序对照:insert-then-delete vs delete-then-insert,结果应不同但可预测。
    func testOrderMattersPredictably() {
        let base = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        let insThenDel = Mutations.rippleDelete(at: 0,
            in: Mutations.insertClip(clip(1), at: 1, in: base))
        let delThenIns = Mutations.insertClip(clip(1), at: 1,
            in: Mutations.rippleDelete(at: 0, in: base))
        // 两者位置表不同 —— 证明顺序敏感且各自确定
        XCTAssertNotEqual(ExperimentReport.placementTable(insThenDel),
                          ExperimentReport.placementTable(delThenIns))
    }

    // 参数扫描:trim duration 从 1..9,后续 clip 起点应单调左移。
    func testTrimSweepMonotonic() {
        var prevStart = Double.infinity
        for d in stride(from: 9, through: 1, by: -1) {
            let seq = Mutations.rippleTrimRight(at: 0, newDuration: .seconds(Double(d)),
                assetDuration: .seconds(20),
                in: Sequence(spine: [.clip(clip(10)), .clip(clip(2))]))
            let secondStart = ExperimentReport.placementTable(seq)[1].absStartSeconds
            XCTAssertLessThan(secondStart, prevStart, "trim 越短,后续起点应越靠左")
            prevStart = secondStart
        }
    }

    // A/B:吸附 on vs off,落点不同且可解释。
    func testSnapOnVsOff() {
        let raw = Time.seconds(2.03)
        let cands = [Time.seconds(2.0)]
        let snapped = Snapping.snap(raw, candidates: cands, threshold: .seconds(0.05))
        let notSnapped = Snapping.snap(raw, candidates: cands, threshold: .seconds(0.001))
        XCTAssertEqual(snapped, .seconds(2.0))
        XCTAssertEqual(notSnapped, raw)
    }

    func testCSVExport() {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        let csv = ExperimentReport.csv(seq)
        XCTAssertTrue(csv.contains("clipID,absStart,duration,lane"))
        XCTAssertEqual(csv.split(separator: "\n").count, 3) // header + 2 rows
    }
}

/// 确定性 RNG(固定种子,实验可复现)。
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func nextRaw() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func next(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(nextRaw() % span)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter InvariantPropertyTests`
Expected: FAIL（`ExperimentReport` 未定义）。

- [ ] **Step 3: 实现 ExperimentReport**

`Sources/FCPXLite/Document/Magnetic/ExperimentReport.swift`:
```swift
import Foundation

/// 对照实验数据导出:把布局结果摊成可比对的位置表 / CSV。
struct PlacementRow: Equatable {
    let clipID: String
    let absStartSeconds: Double
    let durationSeconds: Double
    let lane: Int
}

enum ExperimentReport {
    static func placementTable(_ seq: Sequence) -> [PlacementRow] {
        Layout.compute(seq).map {
            PlacementRow(clipID: $0.clipID.raw,
                         absStartSeconds: $0.absStart.seconds,
                         durationSeconds: $0.duration.seconds,
                         lane: $0.lane)
        }
    }

    static func csv(_ seq: Sequence) -> String {
        var lines = ["clipID,absStart,duration,lane"]
        for r in placementTable(seq) {
            lines.append("\(r.clipID),\(r.absStartSeconds),\(r.durationSeconds),\(r.lane)")
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter InvariantPropertyTests`
Expected: PASS（5 tests）。

- [ ] **Step 5: 全量回归 + 提交**

Run: `swift test`
Expected: 所有测试 PASS。
```bash
git add Sources/FCPXLite/Document/Magnetic/ExperimentReport.swift Tests/FCPXLiteTests/InvariantPropertyTests.swift
git commit -m "feat: 控制变量对照实验框架(spec §8 数据驱动验证)"
```

---

## Task 12: DesignSystem Token(落 style.md)

**Files:**
- Create: `Sources/FCPXLite/DesignSystem/Color+Hex.swift`
- Create: `Sources/FCPXLite/DesignSystem/Tokens.swift`
- Test: `Tests/FCPXLiteTests/TokenTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `extension Color { init(hex: String) }`(SwiftUI)
  - `enum Tokens { enum Palette { static let chrome/canvas/titlebar/... : Color }; enum Metric { static let ... : CGFloat }; enum Type {...} }`
  - 关键值(verbatim 自 style.md):chrome `#212121`、canvas `#1A1A1A`、titlebar `#3B3B3B`、effectsPanel `#1F1F1F`、elevated `#2C2C2C`、textPrimary `#EAEAEA`、textCool `#DCE2FF`、textMuted `#696969`、clipBlue `#243553`、selectYellow `#FFD754`、selectClipBorder `#FFDB86`、waveform `#8C9CBD`

- [ ] **Step 1: 写失败测试**

`Tests/FCPXLiteTests/TokenTests.swift`:
```swift
import XCTest
import SwiftUI
@testable import FCPXLite

final class TokenTests: XCTestCase {
    func testHexParsesToComponents() {
        // #212121 → (33,33,33)/255
        let c = Color(hex: "#212121")
        let ns = NSColor(c).usingColorSpace(.sRGB)!
        XCTAssertEqual(Double(ns.redComponent), 33.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(ns.greenComponent), 33.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(ns.blueComponent), 33.0/255.0, accuracy: 0.01)
    }

    func testTokensExist() {
        // 仅验证可访问(编译期保证类型),运行期确认非崩溃。
        _ = Tokens.Palette.chrome
        _ = Tokens.Palette.clipBlue
        _ = Tokens.Palette.selectYellow
        _ = Tokens.Metric.librariesWidth
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter TokenTests`
Expected: FAIL（`Color(hex:)` / `Tokens` 未定义）。

- [ ] **Step 3: 实现**

`Sources/FCPXLite/DesignSystem/Color+Hex.swift`:
```swift
import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
```

`Sources/FCPXLite/DesignSystem/Tokens.swift`:
```swift
import SwiftUI

/// 设计令牌 —— 全部源自 design/style.md 截图实采。视图只引用这里,严禁裸 hex。
enum Tokens {
    enum Palette {
        static let titlebar      = Color(hex: "#3B3B3B")
        static let chrome        = Color(hex: "#212121")
        static let canvas        = Color(hex: "#1A1A1A")
        static let effectsPanel  = Color(hex: "#1F1F1F")
        static let chatPanel     = Color(hex: "#1E1E1E")
        static let elevated      = Color(hex: "#2C2C2C")

        static let textPrimary   = Color(hex: "#EAEAEA")
        static let textCool      = Color(hex: "#DCE2FF")
        static let textIcon      = Color(hex: "#EEEEEE")
        static let textMuted     = Color(hex: "#696969")

        static let clipBlue      = Color(hex: "#243553")
        static let clipBlueEdge  = Color(hex: "#3E5E96")
        static let selectYellow  = Color(hex: "#FFD754")
        static let selectClipBorder = Color(hex: "#FFDB86")
        static let waveform      = Color(hex: "#8C9CBD")
        static let playhead      = Color.white
    }

    enum Metric {
        static let titlebarHeight: CGFloat = 30
        static let toolbarHeight: CGFloat = 26
        static let timelineToolbarHeight: CGFloat = 24
        static let librariesWidth: CGFloat = 200
        static let browserWidth: CGFloat = 280
        static let inspectorWidth: CGFloat = 320
        static let chatWidth: CGFloat = 320
        static let effectsWidth: CGFloat = 360
        static let dividerWidth: CGFloat = 1
    }

    enum Typeface {
        static let label = Font.system(size: 11)
        static let body = Font.system(size: 12)
        static let timecode = Font.system(size: 13).monospaced()
        static let title = Font.system(size: 13, weight: .medium)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter TokenTests`
Expected: PASS（2 tests）。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/DesignSystem/ Tests/FCPXLiteTests/TokenTests.swift
git commit -m "feat: DesignSystem Token(落 style.md 实采配色)"
```

---

## Task 13: 五区外壳 + DocumentStore + 可启动 app

**Files:**
- Create: `Sources/FCPXLite/Store/DocumentStore.swift`
- Create: `Sources/FCPXLite/Views/Placeholders.swift`
- Create: `Sources/FCPXLite/Views/RootView.swift`
- Create: `Sources/FCPXLite/AppDelegate.swift`
- Create: `Sources/FCPXLite/main.swift`
- Create: `scripts/make_app.sh`
- Test: `Tests/FCPXLiteTests/StoreTests.swift`

**Interfaces:**
- Consumes: `Document`、`Tokens`、`Mutations`
- Produces:
  - `@Observable final class DocumentStore { var document: Document; func apply(_ transform: (Sequence) -> Sequence) }`(apply 把命令作用在 sequence 上并写回,统一 commit 入口)
  - `struct RootView: View`(五区骨架:通栏状态栏 → 左工作区[格式工具栏/边栏·管理器·预览/时间线工具栏/时间线占位] + 右 Chat;Inspector/效果默认隐藏,开关 toggle `@State`)
  - 可启动的 `.app`

- [ ] **Step 1: 写 Store 测试**

`Tests/FCPXLiteTests/StoreTests.swift`:
```swift
import XCTest
@testable import FCPXLite

final class StoreTests: XCTestCase {
    func testApplyMutatesDocument() {
        let store = DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        store.apply { Mutations.insertClip(clip, at: 0, in: $0) }
        XCTAssertEqual(store.document.sequence.spine.count, 1)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter StoreTests`
Expected: FAIL（`DocumentStore` 未定义）。

- [ ] **Step 3: 实现 Store**

`Sources/FCPXLite/Store/DocumentStore.swift`:
```swift
import Observation

/// 顶层单一数据源。命令层通过 apply 作用于 sequence,统一 commit。
@Observable final class DocumentStore {
    var document: Document
    init(document: Document) { self.document = document }

    /// 唯一 commit 入口:把一个 Sequence→Sequence 命令作用到文档并写回。
    func apply(_ transform: (Sequence) -> Sequence) {
        document.sequence = transform(document.sequence)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter StoreTests`
Expected: PASS（1 test）。

- [ ] **Step 5: 实现五区视图**

`Sources/FCPXLite/Views/Placeholders.swift`:
```swift
import SwiftUI

struct PanelPlaceholder: View {
    let title: String
    var background: Color = Tokens.Palette.chrome
    var body: some View {
        ZStack {
            background
            Text(title).font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textMuted)
        }
    }
}

struct ChatPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("🤖 Agent").font(Tokens.Typeface.body)
                       .foregroundStyle(Tokens.Palette.textCool); Spacer() }
                .padding(8)
                .background(Tokens.Palette.elevated)
            PanelPlaceholder(title: "对话区(M2 接入)", background: Tokens.Palette.chatPanel)
            HStack { Text("和 Agent 对话…").font(Tokens.Typeface.label)
                       .foregroundStyle(Tokens.Palette.textMuted); Spacer() }
                .padding(8).background(Tokens.Palette.elevated).cornerRadius(5).padding(8)
        }
        .frame(width: Tokens.Metric.chatWidth)
        .background(Tokens.Palette.chatPanel)
    }
}
```

`Sources/FCPXLite/Views/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    @State private var showInspector = false
    @State private var showEffects = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider().overlay(Color.black)
            HStack(spacing: 0) {
                leftWorkspace
                ChatPanelView()
            }
        }
        .background(Tokens.Palette.chrome)
        .frame(minWidth: 1100, minHeight: 680)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Circle().fill(.yellow).frame(width: 10, height: 10)
            Circle().fill(.green).frame(width: 10, height: 10)
            Spacer()
            Text("FCPX-lite").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
            Spacer()
            Button { showInspector.toggle() } label: { Text("≡|||") }
                .help("检查器开关 ⌘4")
                .buttonStyle(.plain)
                .foregroundStyle(showInspector ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
        }
        .padding(.horizontal, 12).frame(height: Tokens.Metric.titlebarHeight)
        .background(Tokens.Palette.titlebar)
    }

    private var leftWorkspace: some View {
        VStack(spacing: 0) {
            PanelPlaceholder(title: "格式工具栏").frame(height: Tokens.Metric.toolbarHeight)
            Divider().overlay(Color.black)
            HStack(spacing: 0) {
                PanelPlaceholder(title: "边栏").frame(width: 80)
                Divider().overlay(Color.black)
                PanelPlaceholder(title: "资源管理器").frame(width: Tokens.Metric.browserWidth)
                Divider().overlay(Color.black)
                PanelPlaceholder(title: "预览 Viewer", background: Tokens.Palette.canvas)
                if showInspector {
                    Divider().overlay(Color.black)
                    PanelPlaceholder(title: "检查器").frame(width: Tokens.Metric.inspectorWidth)
                }
            }
            timelineToolbar
            Divider().overlay(Color.black)
            HStack(spacing: 0) {
                PanelPlaceholder(title: "磁性时间线", background: Tokens.Palette.canvas)
                if showEffects {
                    Divider().overlay(Color.black)
                    PanelPlaceholder(title: "效果/转场", background: Tokens.Palette.effectsPanel)
                        .frame(width: Tokens.Metric.effectsWidth)
                }
            }
            .frame(height: 200)
        }
    }

    private var timelineToolbar: some View {
        HStack {
            Text("索引 ✛⊟✄").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
            Button { showEffects.toggle() } label: { Text("▤▤") }
                .help("效果开关 ⌘5")
                .buttonStyle(.plain)
                .foregroundStyle(showEffects ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
        }
        .padding(.horizontal, 12).frame(height: Tokens.Metric.timelineToolbarHeight)
        .background(Tokens.Palette.chrome)
    }
}
```

- [ ] **Step 6: 实现 AppKit 入口 + 打包脚本**

`Sources/FCPXLite/AppDelegate.swift`:
```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = DocumentStore(document: Document(
            formatWidth: 1920, formatHeight: 1080, frameRate: 25,
            assetLibrary: [], sequence: Sequence(spine: [])))
        _ = store // M1.0 外壳暂不绑定数据;占位以验证编译与启动

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "FCPX-lite"
        window.contentView = NSHostingView(rootView: RootView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

`Sources/FCPXLite/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
```

`scripts/make_app.sh`(沿用 feishu 结构):
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=".build/FCPXLite.app"
BIN=".build/release/FCPXLite"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FCPXLite"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FCPXLite</string>
  <key>CFBundleIdentifier</key><string>com.local.fcpxlite</string>
  <key>CFBundleExecutable</key><string>FCPXLite</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
xattr -cr "$APP"
echo "built $APP"
```

- [ ] **Step 7: 全量测试 + 构建验证(不启动 app —— 由用户手动启停)**

Run: `swift test && swift build -c release && bash scripts/make_app.sh`
Expected: 所有测试 PASS;构建成功;打印 `built .build/FCPXLite.app`。
**不要后台启动 app**;告诉用户:可执行 `open .build/FCPXLite.app` 自行查看五区外壳(配色/布局/Inspector⌘4、效果⌘5 开关显隐),看完自行关闭。

- [ ] **Step 8: 提交**

```bash
git add Sources/FCPXLite/Store/ Sources/FCPXLite/Views/ Sources/FCPXLite/AppDelegate.swift Sources/FCPXLite/main.swift scripts/make_app.sh Tests/FCPXLiteTests/StoreTests.swift
chmod +x scripts/make_app.sh
git commit -m "feat: 五区外壳 + DocumentStore + 可启动 app(M1.0 完成)"
```

---

## 本切片完成定义(DoD)

- `swift test` 全绿:Time / 模型 / Layout / Invariants / Snapping / Mutations(insert/delete/move/trim/blade/connect)/ 对照实验框架 / Token / Store。
- 磁性引擎三条不变量在 200×10 随机操作序列下恒成立(属性测试)。
- 控制变量对照实验(A/B、顺序、参数扫描、CSV 导出)全部通过。
- `make_app.sh` 产出可启动 `.app`,五区布局 + FCPX 配色 + Inspector/效果开关显隐符合 spec §6。
- 命令层就位:所有修改走 `Mutations` + `DocumentStore.apply`,为 M1.3+ 的 UI 接入和 M2 的 Agent 接入预留好统一入口。

---

## 下一切片(本计划不含,后续单独成计划)

M1.3 资源管理器(AVFoundation 导入 + 缩略图)、M1.4 时间线自绘画布(AppKit + 拖拽/trim/blade/吸附 UI)、M1.5 预览引擎(CompositionBuilder + AVPlayer)、M1.6 Inspector、M1.7 FCPXML 导出器 + 串联。这些依赖本切片的文档模型与命令层,且需手动 `.app` 验证。
