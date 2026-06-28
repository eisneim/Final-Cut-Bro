# Plan 3:Agent 全链路收尾(特效/导出/停用动作 + position_move/set_gap 选择修正)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Agent 能通过对话完成整条链路里此前缺的环节——加/删/调特效、停用片段、导出 fcpxml/成片;并修正实测发现的 `position_move`/`set_gap` 被 LLM 误选成 blade 的问题。

**Architecture:** 在 `AgentActionCatalog` 的 adjust 域加特效动作(复用 `mutateEffects` 辅助)、加 `toggle_enabled`;在 navigate 域加 `export_fcpxml`/`export_movie`(调 store 导出);改进 position_move/set_gap 的 `doc` 让 LLM 选对。registry 的 dispatchTool 自动从 catalog 生成 schema,无需改 registry。

**Tech Stack:** Swift / XCTest。LLM 端到端走真实 agentSend(用户启动 server)。

## Global Constraints

- 单文件 < 500 行;`AgentActionCatalog.swift` 当前 251 行,加完仍须 < 500(若超则拆 `AgentActionCatalog+Effects.swift`)。
- Dev fail-fast:坏 index/缺参 → "错误:…" 字符串,不静默。
- LLM 只用 index + 名字/秒;内部翻译留 catalog。
- 现有 191 测试保持通过。

---

### Task 1: Agent 特效动作 + 停用动作(adjust 域)

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentActionCatalog.swift`(adjust 数组加动作 + `mutateEffects` 辅助)
- Test: `Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift`(追加)

**Interfaces:**
- Consumes: `Effect`/`EffectKind`、`store.dispatch(.setEffects(id,_))`、`.setEnabled(id,_)`、已有 `clipID`/`spineElementIndex`/`intArg`/`numArg`/`strArg`/`mutateAdjust`。
- Produces: adjust 域新增 `add_effect`/`remove_effect`/`set_effect_param`/`toggle_enabled`;静态辅助 `mutateEffects(_:clipIndex:_:) -> Bool`。

- [ ] **Step 1: 写失败测试**

```swift
// 追加到 AgentDispatchCatalogTests(已有 storeWith2Assets/clipCount 等辅助)
func testAddAndRemoveEffect() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    _ = AgentActionCatalog.find("add_effect")!.apply(store, ["clipIndex": 0, "kind": "blur"])
    guard case .clip(let c1) = store.document.sequence.spine[0] else { return XCTFail() }
    XCTAssertEqual(c1.effects.count, 1)
    XCTAssertEqual(c1.effects[0].kind, .blur)
    _ = AgentActionCatalog.find("remove_effect")!.apply(store, ["clipIndex": 0, "effectIndex": 0])
    guard case .clip(let c2) = store.document.sequence.spine[0] else { return XCTFail() }
    XCTAssertEqual(c2.effects.count, 0)
}

func testSetEffectParam() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    _ = AgentActionCatalog.find("add_effect")!.apply(store, ["clipIndex": 0, "kind": "color"])
    _ = AgentActionCatalog.find("set_effect_param")!.apply(store, ["clipIndex": 0, "effectIndex": 0, "key": "brightness", "value": 0.3])
    guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
    XCTAssertEqual(c.effects[0].params["brightness"], 0.3)
}

func testAddEffectBadKindErrors() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    let r = AgentActionCatalog.find("add_effect")!.apply(store, ["clipIndex": 0, "kind": "nonsense"])
    XCTAssertTrue(r.contains("错误"), r)
}

func testToggleEnabled() {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    _ = AgentActionCatalog.find("toggle_enabled")!.apply(store, ["clipIndex": 0, "enabled": false])
    guard case .clip(let c) = store.document.sequence.spine[0] else { return XCTFail() }
    XCTAssertFalse(c.enabled)
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: FAIL(add_effect 等未定义)

- [ ] **Step 3: 加 mutateEffects 辅助 + 4 个动作**

在 `AgentActionCatalog` 里(`mutateAdjust` 附近)加:
```swift
    /// 改某 clip 的 effects(走命令层,可撤销)。返回 false=clipIndex 无效。
    @MainActor static func mutateEffects(_ store: DocumentStore, clipIndex: Int, _ f: (inout [Effect]) -> Void) -> Bool {
        guard let id = clipID(store, clipIndex), let ei = spineElementIndex(store, clipIndex: clipIndex),
              case .clip(let c) = store.document.sequence.spine[ei] else { return false }
        var fx = c.effects; f(&fx); store.dispatch(.setEffects(id, fx)); return true
    }
```
在 `adjust` 数组末尾(`volume` 之后)加:
```swift
        AgentAction(type: "add_effect", domain: .adjust, doc: "给主轴第 clipIndex 个片段加特效。kind: color(调色) / blur(模糊) / fade(音频淡入淡出)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "kind", kind: .enumString(["color","blur","fade"]), required: true, doc: "特效种类")]) { store, a in
            guard let k = strArg(a, "kind").flatMap({ EffectKind(rawValue: $0) }) else { return "错误:未知特效 kind" }
            return mutateEffects(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.append(Effect.make(k)) }
                ? "已加特效 \(k.rawValue)" : "错误:clipIndex 无效"
        },
        AgentAction(type: "remove_effect", domain: .adjust, doc: "删除主轴第 clipIndex 个片段的第 effectIndex 个特效。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "effectIndex", kind: .int, required: true, doc: "特效索引,0基")]) { store, a in
            let ei = intArg(a, "effectIndex") ?? -1
            return mutateEffects(store, clipIndex: intArg(a, "clipIndex") ?? -1) { if $0.indices.contains(ei) { $0.remove(at: ei) } }
                ? "已删特效 \(ei)" : "错误:clipIndex 无效"
        },
        AgentAction(type: "set_effect_param", domain: .adjust, doc: "调主轴第 clipIndex 个片段第 effectIndex 个特效的参数 key=value。color: brightness/contrast/saturation; blur: radius; fade: inSeconds/outSeconds。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "effectIndex", kind: .int, required: true, doc: "特效索引"),
                             ParamSpec(name: "key", kind: .string, required: true, doc: "参数名"),
                             ParamSpec(name: "value", kind: .number, required: true, doc: "参数值")]) { store, a in
            let ei = intArg(a, "effectIndex") ?? -1
            guard let key = strArg(a, "key") else { return "错误:缺 key" }
            let v = numArg(a, "value") ?? 0
            return mutateEffects(store, clipIndex: intArg(a, "clipIndex") ?? -1) { if $0.indices.contains(ei) { $0[ei].params[key] = v } }
                ? "已设特效参数 \(key)=\(v)" : "错误:clipIndex 无效"
        },
        AgentAction(type: "toggle_enabled", domain: .adjust, doc: "停用/启用主轴第 clipIndex 个片段。enabled=false 停用(不参与预览/导出,时间线变暗)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "enabled", kind: .string, required: true, doc: "true/false")]) { store, a in
            guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            let on = boolArg(a, "enabled") ?? true
            store.dispatch(.setEnabled(id, on)); return on ? "已启用片段" : "已停用片段"
        },
```
(注:`boolArg` 已存在;`Effect`/`EffectKind`/`Effect.make` 在主 target 内可直接用。)

- [ ] **Step 4: 运行确认通过 + 回归**

Run: `swift test --filter AgentDispatchCatalogTests && swift test 2>&1 | tail -2`
Expected: 全过;全量 ≥195。

- [ ] **Step 5: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentActionCatalog.swift Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
git commit -m "feat(agent): 特效动作(add/remove/set_param)+toggle_enabled停用 接入catalog+测试"
```

---

### Task 2: Agent 导出动作 + position_move/set_gap 选择修正

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentActionCatalog.swift`(navigate 加 export 动作;改 position_move/set_gap doc)
- Test: `Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift`(追加)

**Interfaces:**
- Consumes: `store.exportFCPXML(to:)`(throws)、`store.exportMovie(to:)`。
- Produces: navigate 域 `export_fcpxml(path)`/`export_movie(path)`;position_move/set_gap doc 加判别提示。

- [ ] **Step 1: 写失败测试**

```swift
func testExportFCPXMLAction() throws {
    let store = storeWith2Assets()
    _ = AgentActionCatalog.find("append")!.apply(store, ["assetIndex": 0])
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID().uuidString).fcpxml")
    defer { try? FileManager.default.removeItem(at: out) }
    let r = AgentActionCatalog.find("export_fcpxml")!.apply(store, ["path": out.path])
    XCTAssertFalse(r.contains("错误"), r)
    XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    let content = try String(contentsOf: out, encoding: .utf8)
    XCTAssertTrue(content.contains("<fcpxml"))
}

func testExportActionsRegisteredInNavigate() {
    XCTAssertEqual(AgentActionCatalog.find("export_fcpxml")?.domain, .navigate)
    XCTAssertEqual(AgentActionCatalog.find("export_movie")?.domain, .navigate)
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter AgentDispatchCatalogTests`
Expected: FAIL(export_fcpxml 未定义)

- [ ] **Step 3: navigate 加 export 动作**

在 `navigate` 数组末尾(`import` 之后)加:
```swift
        AgentAction(type: "export_fcpxml", domain: .navigate, doc: "把当前剪辑导出为 .fcpxml 工程文件到磁盘绝对路径(可回真 FCP 继续剪)。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "目标 .fcpxml 绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            do { try store.exportFCPXML(to: URL(fileURLWithPath: p)); return "已导出 fcpxml 到 \(p)" }
            catch { return "错误:导出失败 \(error)" }
        },
        AgentAction(type: "export_movie", domain: .navigate, doc: "把当前剪辑渲染导出为成片(有视频→mp4,纯音频→m4a)到磁盘绝对路径。异步,返回已开始。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "目标文件绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            store.exportMovie(to: URL(fileURLWithPath: p)); return "已开始导出成片到 \(p)(渲染中)"
        },
```

- [ ] **Step 4: 改 position_move / set_gap 的 doc(消除与 blade 混淆)**

把 `set_gap` 的 doc 改为:
```swift
                    doc: "调整已存在的【间隙(gap)】时长 —— 不是切割也不是删除。spineIndex 必须指向一个间隙元素。要在片段间制造间隙请用 delete(ripple=false) 或 position_move。",
```
把 `position_move` 的 doc 改为:
```swift
                    doc: "【位置工具】把主轴第 clipIndex 个片段整体移到 atSeconds,源位置留下占位间隙(不像 blade 那样切开,也不像 move 那样调顺序)。用于在保持其它片段位置不变的前提下挪动一个片段。",
```

- [ ] **Step 5: 运行确认通过 + 回归**

Run: `swift test --filter AgentDispatchCatalogTests && swift test 2>&1 | tail -2`
Expected: 全过;全量 ≥197。

- [ ] **Step 6: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentActionCatalog.swift Tests/FCPXLiteTests/AgentDispatchCatalogTests.swift
git commit -m "feat(agent): 导出动作(export_fcpxml/export_movie)+修position_move/set_gap doc(消除与blade混淆)"
```

---

### Task 3: 系统提示更新 + 端到端清单回填

**Files:**
- Modify: `Sources/FCPXLite/Agent/AgentService.swift`(系统提示提到特效/导出/停用)
- Modify: `docs/agent-e2e-checklist.md`(补特效/导出/停用行 + 真实工作流终点=导出)

**Interfaces:** 无新类型;纯文本。

- [ ] **Step 1: 改系统提示**

在 `AgentService.swift` 描述 clip_adjust / navigate 的段落补:
```
- clip_adjust 现还支持:add_effect/remove_effect/set_effect_param(color/blur/fade 特效)、toggle_enabled(停用/启用片段)。
- navigate 现还支持:export_fcpxml(导出工程)、export_movie(渲染成片)。
完成一个完整任务时,若用户要"做完整条片子",记得最后用 export_movie 导出成片。
```

- [ ] **Step 2: 清单补行**

在 `docs/agent-e2e-checklist.md` 步骤 A 表追加:
```markdown
| adjust | add_effect | "给第0段加高斯模糊" | effects+1 | ⬜ |
| adjust | set_effect_param | "把模糊半径调到20" | params.radius=20 | ⬜ |
| adjust | toggle_enabled | "停用第1段" | enabled=false | ⬜ |
| navigate | export_fcpxml | "导出工程到~/Desktop/t.fcpxml" | 文件生成 | ⬜ |
| navigate | export_movie | "把成片导出到~/Desktop/out.mp4" | 渲染开始 | ⬜ |
```
并把步骤 B 真实工作流终点改为"…在第5秒切一刀删掉前半段,**最后导出成片到 ~/Desktop**"。

- [ ] **Step 3: 构建确认 + 回归**

Run: `swift build 2>&1 | grep -E "error:|Build complete" && swift test 2>&1 | tail -2`
Expected: Build complete;全量过。

- [ ] **Step 4: 提交**

```bash
git add Sources/FCPXLite/Agent/AgentService.swift docs/agent-e2e-checklist.md
git commit -m "docs(agent): 系统提示+e2e清单补特效/导出/停用 — Agent全链路可对话完成"
```

---

## Self-Review

**Spec coverage(对照 spec §2④):**
- add_effect/remove_effect/set_effect_param → Task 1 ✅
- toggle_enabled(停用)→ Task 1 ✅(spec 未明列但属链路"中间删除/停用"环节)
- export_fcpxml/export_movie → Task 2 ✅
- 修 position_move/set_gap 选择 → Task 2 ✅
- 系统提示 + 清单 → Task 3 ✅
- 100+ 测试:当前已 191,本 plan 再 +6 → ~197,**criterion 已满足**。

**Placeholder scan:** 无 TBD。

**Type consistency:** `mutateEffects(_:clipIndex:_:)`、`Effect.make`、`EffectKind(rawValue:)`、`boolArg`、`store.exportFCPXML/exportMovie`、`.setEffects/.setEnabled` —— 均已存在或本 plan 内定义,跨任务一致。

**注意:** export_movie 是异步(渲染耗时),catalog 动作返回"已开始"即可,不阻塞 LLM 循环;真实完成由 store.ui.exportProgress 反映。端到端真 LLM 验证由用户启动 server 后进行(测完即止)。
