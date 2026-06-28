# Agent Dispatch 工具实现 Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Agent 的 13 个独立工具收敛成 3 个领域 dispatch 工具 + 1 个只读 query 工具,由一张带注释的 action catalog 驱动,补齐之前 LLM 调不了的 volume/position_move/set_gap 等能力,并端到端验证完整剪辑流程。

**Architecture:** 新增 `AgentActionCatalog`——一张 action 元数据表(type/domain/doc/params/apply),作为"清单"与"执行"的单一事实来源。`AgentToolRegistry` 重构为按 domain 从 catalog 自动生成 4 个工具的 JSON schema,`execute` 转为查 catalog 调用 `apply` 闭包。LLM 发扁平 `{type, params}`(index+seconds),`apply` 内部翻译成 `EditorAction` 走 `store.dispatch`——与手动 UI 完全同一条路径。

**Tech Stack:** Swift / SwiftPM / XCTest;`@MainActor` 隔离;现有 `DocumentStore.dispatch(EditorAction)`、`Layout.compute`、`Adjustments` 模型。

## Global Constraints

- 单文件不超过 500 行;超出即拆分(用户铁律)。
- Dev 阶段 fail-fast:catalog `apply` 遇非法参数返回明确错误文本给 LLM,**不**静默兜底。
- Server 永远由用户启动(`bash scripts/run.sh`),Agent 测完即止,不留后台进程。
- LLM 只用 index(0 基)+ seconds;内部 `ClipID`/`Time` 由 `apply` 翻译,绝不外泄给 LLM。
- 现有 151 个测试必须保持通过。
- 翻译辅助沿用现有签名:`intArg(_:_:) -> Int?`、`numArg(_:_:) -> Double?`、`strArg` 需新增;
  `spineClipID(_ clipIndex: Int) -> ClipID?`、`spineElementIndex(clipIndex:) -> Int?`、`clipFromAsset(_:) -> Clip?`。

---

### Task 1: 定义 AgentActionCatalog 数据结构与翻译辅助

**Files:**
- Create: `Sources/FCPXLite/Agent/AgentActionCatalog.swift`
- Test: `Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift`

**Interfaces:**
- Produces:
  - `enum ActionDomain: String { case timeline, adjust, navigate }`
  - `struct ParamSpec { let name: String; let kind: ParamKind; let required: Bool; let doc: String }`
  - `enum ParamKind { case int, number, string; case enumString([String]) }`
  - `struct AgentAction { let type: String; let domain: ActionDomain; let doc: String; let params: [ParamSpec]; let apply: @MainActor (DocumentStore, [String: Any]) -> String }`
  - `enum AgentActionCatalog { static let all: [AgentAction]; static func find(_ type: String) -> AgentAction?; static func actions(in: ActionDomain) -> [AgentAction] }`

- [ ] **Step 1: 写失败测试**

```swift
// Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter AgentDispatchCatalogTests/testCatalogHasDomainsAndLookup`
Expected: 编译失败(`AgentActionCatalog` 未定义)

- [ ] **Step 3: 实现 catalog 骨架 + 一个动作占位**

```swift
// Sources/FCPXLite/Agent/AgentActionCatalog.swift
import Foundation

/// LLM 可见的动作领域。
enum ActionDomain: String { case timeline, adjust, navigate }

/// 形参规格(供生成 JSON schema)。
enum ParamKind { case int, number, string; case enumString([String]) }
struct ParamSpec { let name: String; let kind: ParamKind; let required: Bool; let doc: String }

/// 一个 LLM 可发的扁平动作:type + 注释 + 形参 + 翻译执行闭包(index/秒 → EditorAction → dispatch)。
struct AgentAction {
    let type: String
    let domain: ActionDomain
    let doc: String
    let params: [ParamSpec]
    let apply: @MainActor (DocumentStore, [String: Any]) -> String
}

/// 单一事实来源:全部动作。工具 schema 与执行都从这里来,杜绝清单/代码漂移。
enum AgentActionCatalog {
    static func actions(in domain: ActionDomain) -> [AgentAction] { all.filter { $0.domain == domain } }
    static func find(_ type: String) -> AgentAction? { all.first { $0.type == type } }

    // 翻译辅助(index/秒 → 内部表示)。各 apply 闭包共用。
    static func clipID(_ store: DocumentStore, _ clipIndex: Int) -> ClipID? {
        var n = 0
        for el in store.document.sequence.spine { if case .clip(let c) = el { if n == clipIndex { return c.id }; n += 1 } }
        return nil
    }
    static func spineElementIndex(_ store: DocumentStore, clipIndex: Int) -> Int? {
        var n = 0
        for (i, el) in store.document.sequence.spine.enumerated() { if case .clip = el { if n == clipIndex { return i }; n += 1 } }
        return nil
    }
    static func clipFromAsset(_ store: DocumentStore, _ i: Int) -> Clip? {
        guard store.document.assetLibrary.indices.contains(i) else { return nil }
        let a = store.document.assetLibrary[i]
        return Clip(assetID: a.id, sourceIn: .zero, duration: a.duration)
    }
    static func intArg(_ a: [String: Any], _ k: String) -> Int? { (a[k] as? Int) ?? (a[k] as? Double).map(Int.init) ?? (a[k] as? NSNumber)?.intValue }
    static func numArg(_ a: [String: Any], _ k: String) -> Double? { (a[k] as? Double) ?? (a[k] as? Int).map(Double.init) ?? (a[k] as? NSNumber)?.doubleValue }
    static func strArg(_ a: [String: Any], _ k: String) -> String? { a[k] as? String }

    static let all: [AgentAction] = timeline + adjust + navigate

    // 各 domain 在后续 Task 填充;先放占位让骨架可编译+测试通过。
    static let timeline: [AgentAction] = [
        AgentAction(type: "insert", domain: .timeline, doc: "占位", params: []) { _, _ in "未实现" }
    ]
    static let adjust: [AgentAction] = [
        AgentAction(type: "volume", domain: .adjust, doc: "占位", params: []) { _, _ in "未实现" }
    ]
    static let navigate: [AgentAction] = [
        AgentAction(type: "playhead", domain: .navigate, doc: "占位", params: []) { _, _ in "未实现" }
    ]
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter AgentDispatchCatalogTests/testCatalogHasDomainsAndLookup`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentActionCatalog.swift Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
git commit -m "feat(agent): AgentActionCatalog 骨架 + 翻译辅助 + 唯一性测试"
```

---

### Task 2: 填充 timeline domain 动作(结构编辑)

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentActionCatalog.swift`(替换 `timeline` 数组)
- Test: `Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift`(追加用例)

**Interfaces:**
- Consumes: Task 1 的 `AgentAction`、翻译辅助、`DocumentStore.dispatch`。
- Produces: `timeline` 含 9 个动作:`insert/append/connect/delete/move/blade/trim/set_gap/position_move`。

- [ ] **Step 1: 写失败测试**

```swift
// 追加到 AgentDispatchCatalogTests
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: FAIL(占位 apply 返回"未实现",断言不满足)

- [ ] **Step 3: 实现 timeline 动作**

```swift
// 替换 AgentActionCatalog.swift 中的 timeline 占位数组:
static let timeline: [AgentAction] = [
    AgentAction(type: "insert", domain: .timeline,
                doc: "把素材库第 assetIndex 个素材插入主轴 atSeconds 处(省略则末尾)。后续片段右移。",
                params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引,0基"),
                         ParamSpec(name: "atSeconds", kind: .number, required: false, doc: "插入时间(秒),省略=末尾")]) { store, a in
        guard let clip = clipFromAsset(store, intArg(a, "assetIndex") ?? -1) else { return "错误:assetIndex 无效" }
        let count = store.document.sequence.spine.count
        if let at = numArg(a, "atSeconds") {
            var idx = 0, acc = 0.0
            for (i, el) in store.document.sequence.spine.enumerated() { if acc >= at { idx = i; break }; acc += el.duration.seconds; idx = i + 1 }
            store.dispatch(.insertClip(clip, at: idx))
        } else {
            store.dispatch(.insertClip(clip, at: count))
        }
        return "已插入素材 \(intArg(a, "assetIndex")!)"
    },
    AgentAction(type: "append", domain: .timeline,
                doc: "把素材库第 assetIndex 个素材追加到主轴末尾。",
                params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引,0基")]) { store, a in
        guard let clip = clipFromAsset(store, intArg(a, "assetIndex") ?? -1) else { return "错误:assetIndex 无效" }
        store.dispatch(.insertClip(clip, at: store.document.sequence.spine.count))
        return "已追加素材 \(intArg(a, "assetIndex")!)"
    },
    AgentAction(type: "connect", domain: .timeline,
                doc: "把素材库第 assetIndex 个素材作为连接片段叠加到 atSeconds、第 lane 层(>0在上,<0在下)。用于画中画/多轨。",
                params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引"),
                         ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "时间位置(秒)"),
                         ParamSpec(name: "lane", kind: .int, required: false, doc: "层级,默认1")]) { store, a in
        guard let clip = clipFromAsset(store, intArg(a, "assetIndex") ?? -1) else { return "错误:assetIndex 无效" }
        let at = numArg(a, "atSeconds") ?? 0
        // host = 覆盖 at 的主轴片段;offset = at - host起点
        var hostIdx = 0, acc = 0.0, hostStart = 0.0
        var found = false
        for (i, el) in store.document.sequence.spine.enumerated() {
            if case .clip = el { if at >= acc && at < acc + el.duration.seconds { hostIdx = i; hostStart = acc; found = true; break } }
            acc += el.duration.seconds
        }
        guard found else { return "错误:atSeconds 处主轴无片段可挂载" }
        let lane = intArg(a, "lane") ?? 1
        store.dispatch(.connect(clip, host: hostIdx, lane: lane == 0 ? 1 : lane, offset: .seconds(at - hostStart)))
        return "已连接素材 \(intArg(a, "assetIndex")!) 到 lane\(lane)"
    },
    AgentAction(type: "delete", domain: .timeline,
                doc: "删除主轴第 clipIndex 个片段。ripple=true 磁性合拢,false 留 gap。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "主轴片段索引,0基"),
                         ParamSpec(name: "ripple", kind: .string, required: false, doc: "true/false,默认true")]) { store, a in
        guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
        let ripple = (strArg(a, "ripple") ?? "true") != "false"
        store.dispatch(ripple ? .rippleDelete(at: ei) : .liftDelete(at: ei))
        return "已删除片段 \(intArg(a, "clipIndex")!)"
    },
    AgentAction(type: "move", domain: .timeline,
                doc: "把主轴第 fromClipIndex 个片段移到第 toClipIndex 个位置(调整顺序)。",
                params: [ParamSpec(name: "fromClipIndex", kind: .int, required: true, doc: "源片段索引"),
                         ParamSpec(name: "toClipIndex", kind: .int, required: true, doc: "目标位置索引")]) { store, a in
        guard let from = spineElementIndex(store, clipIndex: intArg(a, "fromClipIndex") ?? -1),
              let to = spineElementIndex(store, clipIndex: intArg(a, "toClipIndex") ?? -1) else { return "错误:索引无效" }
        store.dispatch(.moveClip(from: from, to: to))
        return "已移动片段"
    },
    AgentAction(type: "blade", domain: .timeline,
                doc: "在 atSeconds 处把主轴第 clipIndex 个片段切成两段。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "切割时间(秒)")]) { store, a in
        guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1),
              case .clip = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
        // localTime = at - 片段起点
        var acc = 0.0
        for (i, el) in store.document.sequence.spine.enumerated() { if i == ei { break }; acc += el.duration.seconds }
        let at = numArg(a, "atSeconds") ?? 0
        store.dispatch(.blade(at: ei, localTime: .seconds(at - acc)))
        return "已在 \(at)s 切割片段 \(intArg(a, "clipIndex")!)"
    },
    AgentAction(type: "trim", domain: .timeline,
                doc: "修剪主轴第 clipIndex 个片段。edge=head 改入点(seconds=入点偏移),edge=tail 改时长(seconds=新时长)。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "edge", kind: .enumString(["head", "tail"]), required: true, doc: "修剪哪端"),
                         ParamSpec(name: "seconds", kind: .number, required: true, doc: "head:入点偏移; tail:新时长")]) { store, a in
        guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1),
              case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
        let sec = numArg(a, "seconds") ?? 0
        if strArg(a, "edge") == "head" { store.dispatch(.trimLeft(at: ei, deltaIn: .seconds(sec))) }
        else {
            let assetDur = store.document.assetLibrary.first { $0.id == c.assetID }?.duration ?? c.duration
            store.dispatch(.trimRight(at: ei, newDuration: .seconds(sec), assetDuration: assetDur))
        }
        return "已修剪片段 \(intArg(a, "clipIndex")!) \(strArg(a, "edge") ?? "")"
    },
    AgentAction(type: "set_gap", domain: .timeline,
                doc: "把主轴第 spineIndex 个元素(须为间隙)的时长设为 seconds。",
                params: [ParamSpec(name: "spineIndex", kind: .int, required: true, doc: "spine 元素索引(含间隙)"),
                         ParamSpec(name: "seconds", kind: .number, required: true, doc: "新间隙时长(秒)")]) { store, a in
        let i = intArg(a, "spineIndex") ?? -1
        guard store.document.sequence.spine.indices.contains(i) else { return "错误:spineIndex 无效" }
        store.dispatch(.setGapDuration(at: i, duration: .seconds(numArg(a, "seconds") ?? 1)))
        return "已设置间隙时长"
    },
    AgentAction(type: "position_move", domain: .timeline,
                doc: "位置工具:把主轴第 clipIndex 个片段移到 atSeconds,源处留下占位间隙(不磁性合拢)。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "目标时间(秒)")]) { store, a in
        guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
        store.dispatch(.positionMove(id, time: .seconds(numArg(a, "atSeconds") ?? 0)))
        return "已位置移动片段 \(intArg(a, "clipIndex")!)"
    },
]
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: PASS(5 个用例全过)

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentActionCatalog.swift Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
git commit -m "feat(agent): catalog timeline 域 9 动作 + 翻译测试"
```

---

### Task 3: 填充 adjust domain 动作(画面/音频参数)

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentActionCatalog.swift`(替换 `adjust` 数组)
- Test: `Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift`(追加用例)

**Interfaces:**
- Consumes: Task 1/2 辅助、`store.selectedClip`、`store.dispatch(.setAdjust(_:_:))`、`Adjustments` 模型。
- Produces: `adjust` 含 5 个动作:`scale/position/crop/opacity/volume`。所有动作对 `clipIndex` 片段改 `Adjustments`。

- [ ] **Step 1: 写失败测试**

```swift
// 追加到 AgentDispatchCatalogTests
private func currentAdjust(_ s: DocumentStore, clipIndex: Int) -> Adjustments? {
    var n = 0
    for el in s.document.sequence.spine {
        if case .clip(let c) = el { if n == clipIndex { return c.adjust }; n += 1 }
    }
    return nil
}

func testAdjustScaleVolumeCrop() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0]) // 1920x1080
    // scale 2x
    _ = AgentActionCatalog.find("scale")!.apply(store, ["clipIndex": 0, "value": 2.0])
    XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.transform.scale.width, 2.0)
    // volume 0.2
    _ = AgentActionCatalog.find("volume")!.apply(store, ["clipIndex": 0, "value": 0.2])
    XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.volume, 0.2, accuracy: 0.001)
    // crop left 15% → 0.15 * 1920 = 288 px
    _ = AgentActionCatalog.find("crop")!.apply(store, ["clipIndex": 0, "left": 0.15])
    XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.crop.left ?? 0, 288, accuracy: 0.5)
}

func testAdjustOpacityAndPosition() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    _ = AgentActionCatalog.find("opacity")!.apply(store, ["clipIndex": 0, "value": 0.5])
    XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.opacity, 0.5, accuracy: 0.001)
    _ = AgentActionCatalog.find("position")!.apply(store, ["clipIndex": 0, "x": 100, "y": -50])
    XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.transform.position.x, 100)
    XCTAssertEqual(currentAdjust(store, clipIndex: 0)?.transform.position.y, -50)
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: FAIL(占位 volume 返回"未实现";scale/crop/opacity/position 查不到)

- [ ] **Step 3: 实现 adjust 动作**

```swift
// 替换 adjust 占位数组。共用一个改 Adjustments 的私有 helper:
static func mutateAdjust(_ store: DocumentStore, clipIndex: Int, _ f: (inout Adjustments) -> Void) -> Bool {
    guard let id = clipID(store, clipIndex), let ei = spineElementIndex(store, clipIndex: clipIndex),
          case .clip(let c) = store.document.sequence.spine[ei] else { return false }
    var adj = c.adjust; f(&adj); store.dispatch(.setAdjust(id, adj)); return true
}

static let adjust: [AgentAction] = [
    AgentAction(type: "scale", domain: .adjust, doc: "缩放主轴第 clipIndex 个片段画面,value 0.1–4(画中画/放大)。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "value", kind: .number, required: true, doc: "缩放比例 0.1–4")]) { store, a in
        let v = numArg(a, "value") ?? 1
        return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.transform.scale = CGSize(width: v, height: v) }
            ? "已缩放片段到 \(v)x" : "错误:clipIndex 无效"
    },
    AgentAction(type: "position", domain: .adjust, doc: "平移主轴第 clipIndex 个片段画面 x/y 像素。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "x", kind: .number, required: true, doc: "水平位移px"),
                         ParamSpec(name: "y", kind: .number, required: true, doc: "垂直位移px")]) { store, a in
        let x = numArg(a, "x") ?? 0, y = numArg(a, "y") ?? 0
        return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.transform.position = CGPoint(x: x, y: y) }
            ? "已平移片段" : "错误:clipIndex 无效"
    },
    AgentAction(type: "crop", domain: .adjust, doc: "裁剪主轴第 clipIndex 个片段。left/right/top/bottom 为各边裁剪比例 0–1(如 left=0.15 裁左15%)。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "left", kind: .number, required: false, doc: "左裁比例0–1"),
                         ParamSpec(name: "right", kind: .number, required: false, doc: "右裁比例0–1"),
                         ParamSpec(name: "top", kind: .number, required: false, doc: "上裁比例0–1"),
                         ParamSpec(name: "bottom", kind: .number, required: false, doc: "下裁比例0–1")]) { store, a in
        let ci = intArg(a, "clipIndex") ?? -1
        guard let ei = spineElementIndex(store, clipIndex: ci), case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
        let nat = store.document.assetLibrary.first { $0.id == c.assetID }?.naturalSize ?? CGSize(width: 1920, height: 1080)
        return mutateAdjust(store, clipIndex: ci) {
            if let l = numArg(a, "left")   { $0.crop.left   = l * Double(nat.width) }
            if let r = numArg(a, "right")  { $0.crop.right  = r * Double(nat.width) }
            if let t = numArg(a, "top")    { $0.crop.top    = t * Double(nat.height) }
            if let b = numArg(a, "bottom") { $0.crop.bottom = b * Double(nat.height) }
        } ? "已裁剪片段 \(ci)" : "错误:clipIndex 无效"
    },
    AgentAction(type: "opacity", domain: .adjust, doc: "设主轴第 clipIndex 个片段不透明度 value 0–1。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "value", kind: .number, required: true, doc: "不透明度0–1")]) { store, a in
        let v = numArg(a, "value") ?? 1
        return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.opacity = v }
            ? "已设不透明度 \(v)" : "错误:clipIndex 无效"
    },
    AgentAction(type: "volume", domain: .adjust, doc: "设主轴第 clipIndex 个片段音量 value 0–2(1=原始,0=静音;压低视频原声/调音乐用)。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                         ParamSpec(name: "value", kind: .number, required: true, doc: "音量0–2")]) { store, a in
        let v = numArg(a, "value") ?? 1
        return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.volume = v }
            ? "已设音量 \(v)" : "错误:clipIndex 无效"
    },
]
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentActionCatalog.swift Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
git commit -m "feat(agent): catalog adjust 域 5 动作(含 volume)+ 测试"
```

---

### Task 4: 填充 navigate domain 动作(导航/选择/撤销/导入)

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentActionCatalog.swift`(替换 `navigate` 数组)
- Test: `Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift`(追加用例)

**Interfaces:**
- Consumes: `store.dispatch(.setPlayhead/.setZoom/.setTool/.selectClip/.selectAsset)`、`store.undo/redo`、`MediaImporter.importAsset(from:)`、`EditTool(rawValue:)`。
- Produces: `navigate` 含 8 个动作:`playhead/zoom/tool/select/select_asset/undo/redo/import`。

- [ ] **Step 1: 写失败测试**

```swift
// 追加
func testNavigatePlayheadZoomToolUndo() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("playhead")!.apply(store, ["atSeconds": 3.0])
    XCTAssertEqual(store.ui.playhead.seconds, 3.0, accuracy: 0.001)
    _ = AgentActionCatalog.find("zoom")!.apply(store, ["pxPerSecond": 120])
    XCTAssertEqual(store.ui.pxPerSecond, 120)
    _ = AgentActionCatalog.find("tool")!.apply(store, ["name": "blade"])
    XCTAssertEqual(store.ui.currentTool, .blade)
    // undo 还原 tool 之前? tool 不进撤销栈;改测一次结构编辑的 undo
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    XCTAssertEqual(clipCount(store), 1)
    _ = AgentActionCatalog.find("undo")!.apply(store, [:])
    XCTAssertEqual(clipCount(store), 0)
}

func testNavigateSelect() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    _ = AgentActionCatalog.find("select")!.apply(store, ["clipIndex": 0])
    XCTAssertNotNil(store.ui.selectedClipID)
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: FAIL(playhead 占位返回"未实现";zoom/tool/select/undo 查不到)

- [ ] **Step 3: 实现 navigate 动作**

```swift
// 替换 navigate 占位数组。import 用 MediaImporter(确认签名: MediaImporter.importAsset(from: URL) throws -> Asset)
static let navigate: [AgentAction] = [
    AgentAction(type: "playhead", domain: .navigate, doc: "把播放头移到 atSeconds 秒。",
                params: [ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "时间(秒)")]) { store, a in
        store.dispatch(.setPlayhead(.seconds(numArg(a, "atSeconds") ?? 0))); return "播放头到 \(numArg(a, "atSeconds") ?? 0)s"
    },
    AgentAction(type: "zoom", domain: .navigate, doc: "设置时间线缩放 pxPerSecond(像素/秒)。",
                params: [ParamSpec(name: "pxPerSecond", kind: .number, required: true, doc: "每秒像素数")]) { store, a in
        store.dispatch(.setZoom(numArg(a, "pxPerSecond") ?? 60)); return "缩放设为 \(numArg(a, "pxPerSecond") ?? 60)"
    },
    AgentAction(type: "tool", domain: .navigate, doc: "切换编辑工具:select/trim/position/range/blade/zoom/hand。",
                params: [ParamSpec(name: "name", kind: .enumString(["select","trim","position","range","blade","zoom","hand"]), required: true, doc: "工具名")]) { store, a in
        guard let t = strArg(a, "name").flatMap({ EditTool(rawValue: $0) }) else { return "错误:未知工具" }
        store.dispatch(.setTool(t)); return "工具切到 \(t.rawValue)"
    },
    AgentAction(type: "select", domain: .navigate, doc: "选中主轴第 clipIndex 个片段(供 inspector 编辑)。",
                params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引")]) { store, a in
        guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
        store.dispatch(.selectClip(id)); return "已选中片段 \(intArg(a, "clipIndex")!)"
    },
    AgentAction(type: "select_asset", domain: .navigate, doc: "选中素材库第 assetIndex 个素材。",
                params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引")]) { store, a in
        let i = intArg(a, "assetIndex") ?? -1
        guard store.document.assetLibrary.indices.contains(i) else { return "错误:assetIndex 无效" }
        store.dispatch(.selectAsset(store.document.assetLibrary[i].id)); return "已选中素材 \(i)"
    },
    AgentAction(type: "undo", domain: .navigate, doc: "撤销上一次编辑。", params: []) { store, _ in store.undo(); return "已撤销" },
    AgentAction(type: "redo", domain: .navigate, doc: "重做。", params: []) { store, _ in store.redo(); return "已重做" },
    AgentAction(type: "import", domain: .navigate, doc: "从磁盘绝对路径导入媒体(视频/音乐)到素材库。",
                params: [ParamSpec(name: "path", kind: .string, required: true, doc: "媒体文件绝对路径")]) { store, a in
        guard let p = strArg(a, "path") else { return "错误:缺 path" }
        do { let asset = try MediaImporter.importAsset(from: URL(fileURLWithPath: p)); store.dispatch(.importAsset(asset)); return "已导入 \(URL(fileURLWithPath: p).lastPathComponent)" }
        catch { return "错误:导入失败 \(error)" }
    },
]
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentActionCatalog.swift Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
git commit -m "feat(agent): catalog navigate 域 8 动作(含 import)+ 测试"
```

---

### Task 5: AgentToolRegistry 重构为 4 个 dispatch 工具

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentToolRegistry.swift`(替换 `tools()` / `execute()`;删除 13 个旧工具定义与对应 case;保留 `timelineSummary()` 与翻译辅助 helper)
- Test: `Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift`(追加工具生成用例)

**Interfaces:**
- Consumes: `AgentActionCatalog.all/actions(in:)/find`。
- Produces: `tools()` 返回 4 个工具(`query_timeline`/`timeline_edit`/`clip_adjust`/`navigate`);`execute(name:args:)` 路由到 catalog。`toolsJSON()` 与 `timelineSummary()` 签名不变(`AgentService` 不需改)。

- [ ] **Step 1: 写失败测试**

```swift
// 追加
func testRegistryExposesFourTools() {
    let store = storeWith2Assets()
    let reg = AgentToolRegistry(store: store)
    let names = Set(reg.tools().map { $0.name })
    XCTAssertEqual(names, ["query_timeline", "timeline_edit", "clip_adjust", "navigate"])
}

func testDispatchToolRoutesToCatalog() {
    let store = storeWith2Assets()
    let reg = AgentToolRegistry(store: store)
    // 通过 timeline_edit 工具发 append
    let r = reg.execute(name: "timeline_edit", args: ["type": "append", "assetIndex": 0])
    XCTAssertFalse(r.contains("错误"), r)
    XCTAssertEqual(clipCount(store), 1)
    // query_timeline 返回摘要文本
    let q = reg.execute(name: "query_timeline", args: [:])
    XCTAssertTrue(q.contains("素材库"))
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: FAIL(旧 registry 暴露 13 个工具,`timeline_edit` 未知)

- [ ] **Step 3: 重构 tools() 与 execute()**

```swift
// 替换 AgentToolRegistry.tools():
func tools() -> [Tool] {
    [
        Tool(name: "query_timeline",
             description: "获取当前时间线与素材库的完整状态摘要(片段、时长、层级、播放头)。做任何编辑前先调用。",
             parameters: obj([:])),
        dispatchTool(name: "timeline_edit", domain: .timeline,
                     intro: "改时间线结构:增删/移动/裁剪/切割/拼接/间隙。"),
        dispatchTool(name: "clip_adjust", domain: .adjust,
                     intro: "改片段画面/音频参数:缩放/位置/裁剪/不透明度/音量。"),
        dispatchTool(name: "navigate", domain: .navigate,
                     intro: "导航/选择/工具/撤销重做/缩放/导入。"),
    ]
}

/// 从 catalog 的某 domain 生成一个 dispatch 工具:参数固定为 {type, params...},
/// description 内嵌该域所有 action 名 + 形参表(自包含,LLM 无需多查)。
private func dispatchTool(name: String, domain: ActionDomain, intro: String) -> Tool {
    let actions = AgentActionCatalog.actions(in: domain)
    var doc = intro + "\n用法:传 type=动作名,其余字段为该动作参数。可用动作:\n"
    for a in actions {
        let ps = a.params.map { p -> String in
            let req = p.required ? "" : "?"
            return "\(p.name)\(req)"
        }.joined(separator: ", ")
        doc += "  • \(a.type)(\(ps)) — \(a.doc)\n"
    }
    // 参数 schema:type 必填(枚举所有动作名),其余参数合并为开放属性。
    var props: [String: Any] = ["type": enm(actions.map { $0.type }, "要执行的动作名")]
    for a in actions {
        for p in a.params where props[p.name] == nil {
            switch p.kind {
            case .int: props[p.name] = int(p.doc)
            case .number: props[p.name] = num(p.doc)
            case .string: props[p.name] = str(p.doc)
            case .enumString(let vals): props[p.name] = enm(vals, p.doc)
            }
        }
    }
    return Tool(name: name, description: doc, parameters: obj(props, required: ["type"]))
}

// 替换 execute(name:args:):
func execute(name: String, args: [String: Any]) -> String {
    if name == "query_timeline" { return timelineSummary() }
    // 三个 dispatch 工具:取 type 查 catalog,domain 须匹配工具。
    guard let type = args["type"] as? String else { return "错误:缺 type" }
    guard let action = AgentActionCatalog.find(type) else { return "错误:未知动作 type=\(type)" }
    let expectedTool: String
    switch action.domain { case .timeline: expectedTool = "timeline_edit"; case .adjust: expectedTool = "clip_adjust"; case .navigate: expectedTool = "navigate" }
    guard name == expectedTool else { return "错误:动作 \(type) 属于 \(expectedTool),不该用 \(name)" }
    return action.apply(store, args)
}
```

> 删除旧的 13 个 `Tool(...)` 定义和 `execute` 里对应的 13 个 `case`。保留 `timelineSummary()`、`obj/str/int/num/enm`、`intArg/numArg`(可标记 `_ = `避免未用告警,或删除已迁移到 catalog 的私有副本)。若文件仍 >500 行,把 `timelineSummary()` 拆到 `AgentToolRegistry+Summary.swift`。

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: PASS

- [ ] **Step 5: 全量构建 + 回归测试**

Run: `swift build && swift test 2>&1 | tail -3`
Expected: Build complete;`Executed N tests, with 0 failures`(N ≥ 161)

- [ ] **Step 6: 提交**

```bash
git add Sources/FCPXLite/Agent/ Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
git commit -m "refactor(agent): 13工具→4个dispatch工具(query+3领域),catalog驱动"
```

---

### Task 6: 更新系统提示 + DEBUG 控制服务器透传(端到端可驱动)

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentService.swift`(系统提示说明 4 工具用法)
- Modify: `Sources/FCPXLite/DebugControlServer.swift`(新增 `dispatchAction` op:直接调 catalog,供自测不经 LLM 验证翻译层)

**Interfaces:**
- Consumes: `AgentActionCatalog.find`、`store`。
- Produces: `/cmd {op:"dispatchAction", path:<type>, ...}` 直接执行一个 catalog 动作(path 复用为 type 字段);harness 可不花 LLM token 验证每个动作。

- [ ] **Step 1: 改系统提示**

读 `AgentService.swift` 找到系统提示常量,在工具说明处替换为:

```swift
// 系统提示中描述工具的段落改为:
"""
你通过 4 个工具操作剪辑:
- query_timeline:先调它看当前素材库/时间线(片段用 0 基 index,时间用秒)。
- timeline_edit:改结构(insert/append/connect/delete/move/blade/trim/set_gap/position_move)。
- clip_adjust:改画面/音频(scale/position/crop/opacity/volume)。
- navigate:导航/选择/撤销/导入(playhead/zoom/tool/select/select_asset/undo/redo/import)。
每个编辑工具都传 type=动作名 + 该动作的参数。操作前先 query_timeline 确认最新 index。完成后用一句话总结你做了什么。
"""
```

- [ ] **Step 2: DebugControlServer 加 dispatchAction op**

在 `execute(body:)` 的 switch 里加(`Cmd` 结构体已有 `path`/`seconds`/`index`/`lane` 等字段;type 复用 `path`,其余参数从已有字段取并组装成字典):

```swift
case "dispatchAction":
    // 自测:直接执行一个 catalog 动作,不经 LLM。type 走 path 字段,参数从通用字段组装。
    if let type = cmd.path {
        var args: [String: Any] = ["type": type]
        if let i = cmd.index { args["clipIndex"] = i; args["assetIndex"] = i; args["spineIndex"] = i; args["fromClipIndex"] = i }
        if let s = cmd.seconds { args["atSeconds"] = s; args["seconds"] = s; args["value"] = s }
        if let l = cmd.lane { args["lane"] = l }
        if let w = cmd.width { args["value"] = w; args["pxPerSecond"] = w }
        if let action = AgentActionCatalog.find(type) { _ = action.apply(store, args) }
    }
```

> 注:此 op 仅作翻译层冒烟,字段是宽松复用;真正端到端仍走 `agentSend`(真实 LLM 路径)。

- [ ] **Step 3: 构建确认**

Run: `swift build 2>&1 | grep -E "error:|Build complete"`
Expected: Build complete

- [ ] **Step 4: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentService.swift Sources/FCPXLite/DebugControlServer.swift
git commit -m "feat(agent): 系统提示更新4工具 + DEBUG dispatchAction 自测op"
```

---

### Task 7: 端到端测试清单文档 + 真实工作流验证

**Files:**
- Create: `docs/agent-e2e-checklist.md`

**Interfaces:**
- Consumes: 运行中的 debug app(用户启动)+ DEBUG 控制服务器 8765。
- Produces: 一份对照表文档,记录每个动作的 LLM 端到端结果。

- [ ] **Step 1: 写清单骨架**

```markdown
# Agent 端到端测试清单

测试方式:用户 `bash scripts/run.sh` 启动 debug 版;Agent 经真实路径(agentSend)执行;
用 /state /preview /previewFrame 自省断言。测完即止,不留后台进程。

## 步骤 A:逐动作冒烟(广度)

| 域 | 动作 | 自然语言指令 | 期望 | 结果 |
|----|------|------------|------|------|
| timeline | append | "把素材0加到时间线末尾" | clipCount+1 | ⬜ |
| timeline | insert | "在2秒处插入素材1" | 片段右移 | ⬜ |
| timeline | connect | "把素材1叠到3秒处上层" | 出现连接片段 | ⬜ |
| timeline | blade | "在4秒切一刀" | clipCount+1 | ⬜ |
| timeline | trim | "把第0段尾部修到5秒" | duration变化 | ⬜ |
| timeline | delete | "删掉第1段" | clipCount-1 | ⬜ |
| timeline | move | "把第2段移到最前" | 顺序变化 | ⬜ |
| timeline | set_gap | "把间隙设成2秒" | gap时长变 | ⬜ |
| timeline | position_move | "用位置工具把第0段移到10秒" | 源处留gap | ⬜ |
| adjust | scale | "把第0段放大2倍" | scale=2 | ⬜ |
| adjust | crop | "把第0段左边裁15%" | crop.left>0 | ⬜ |
| adjust | opacity | "第0段半透明" | opacity=0.5 | ⬜ |
| adjust | volume | "把第0段原声压到20%" | volume=0.2 | ⬜ |
| adjust | position | "第0段右移100px" | position.x=100 | ⬜ |
| navigate | import | "导入这首音乐<路径>" | 素材库+1 | ⬜ |
| navigate | playhead | "跳到3秒" | playhead=3 | ⬜ |
| navigate | undo | "撤销" | 还原 | ⬜ |

## 步骤 B:真实工作流(深度)

任务:"导入 ~/Downloads/_temp/音乐风格 里的某首歌作为背景音乐连接到时间线,
把视频原声压到20%。" → 验证多步连贯 + 最终预览有声画。

结果记录:
```

- [ ] **Step 2: 提交清单骨架**

```bash
git add docs/agent-e2e-checklist.md
git commit -m "docs(agent): 端到端测试清单骨架"
```

- [ ] **Step 3: 执行端到端(需用户启动 server)**

向用户请求:`bash scripts/run.sh` 启动 debug 版。然后由 Agent 经 8765 `agentSend` 逐条发指令,
读 `/state` 断言,把结果填入清单。**用户启停 server,Agent 测完即止。**

- [ ] **Step 4: 回填结果并提交**

```bash
git add docs/agent-e2e-checklist.md
git commit -m "test(agent): 端到端逐动作冒烟结果回填"
```

---

## Self-Review

**Spec coverage:**
- §2.1 四工具 → Task 5 ✅
- §2.2 AgentActionCatalog 单一事实来源 → Task 1 ✅
- §2.3 扁平动作清单(timeline 9 / adjust 5 / navigate 8) → Task 2/3/4 ✅(volume/position_move/set_gap 均含)
- §2.4 数据流(translate→dispatch) → 各 apply 闭包 ✅
- §3 文件改动 → Task 1–7 覆盖 catalog/registry/service/tests/docs ✅
- §4 端到端两步 → Task 7 ✅
- §6 fail-fast 错误文本 → 各 apply 返回"错误:…",Task 2 有 `testTimelineBadIndexReturnsError` ✅

**Placeholder scan:** Task 1 故意用"占位"动作让骨架可编译,Task 2/3/4 各自替换——非计划失败,是 TDD 渐进。无 TBD/TODO。

**Type consistency:** `clipID/spineElementIndex/clipFromAsset/intArg/numArg/strArg` 在 Task 1 定义为 `AgentActionCatalog` static,Task 2–4 一致引用;`mutateAdjust` Task 3 定义并仅在 adjust 域用;`dispatchTool` Task 5 定义。

**已验证假设(写计划时核对源码):**
- `MediaImporter.importAsset(from: URL) throws -> Asset` 同步,Task 4 代码正确。
- `EditTool: String` rawValues 全小写 `select/trim/position/range/blade/zoom/hand`,与 `tool` 动作枚举匹配。
- `setAdjust` 整个 `Adjustments` 一起 dispatch,故 volume 走同一路径无需新 action。
