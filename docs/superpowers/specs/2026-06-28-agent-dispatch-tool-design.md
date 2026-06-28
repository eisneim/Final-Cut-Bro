# FCPX-lite:单一 dispatch 工具 + 全流程 Agent 端到端测试

日期:2026-06-28
分支:feat/agent-integration

## 1. 背景与目标

当前 Agent 通过 13 个独立的 OpenAI function-calling 工具驱动剪辑(`AgentToolRegistry`)。
这套设计有两个问题:

1. **工具数随能力线性增长**——模型/命令层有 25 个 `EditorAction`,但只暴露了 13 个;
   音量、`positionMove`、`liftDelete`、`setGapDuration` 等 LLM 根本调不了。
2. **每加一个能力要写一个工具**——重复样板,维护成本高。

**核心洞察(用户提出)**:既然手动 UI 和 Agent 都只发同一个 `EditorAction` 并 `dispatch`,
那就把 **action 这一层本身作为数据暴露给 LLM**:一个 `dispatch` 工具 + 一张带注释的 action 清单,
LLM 直接发 `{ type, params }`,走与手动 UI 完全相同的 `store.dispatch` 路径。

**但有一个现实约束**:`EditorAction` 的参数用内部 `ClipID`(UUID)/`Time`(有理数)/嵌套 `Clip`,
LLM 看不到也构造不出。因此需要一层**薄翻译**:LLM 发"扁平动作"(用 index + seconds),
`dispatch` 工具内部翻译成真正的 `EditorAction`。

**本设计目标**:
- 把 13 个工具收敛成 **3 个领域 dispatch 工具 + 1 个只读 query 工具**。
- 用一张**带注释的扁平动作清单**(单一事实来源)驱动 LLM 与翻译层。
- 拆解**完整剪辑流程**为操作清单,让 Agent 端到端跑一遍,产出"哪些通/哪些断"对照表。

非目标(YAGNI):不做调色/转场/字幕(模型层尚无);不改撤销/预览引擎;不做多 clip 批量选择。

## 2. 架构

### 2.1 四个工具(领域分发器,方案 B)

| 工具 | 职责 | 形参 |
|------|------|------|
| `query_timeline` | 只读:返回素材库 + 时间线摘要(index/秒/lane) | 无 |
| `timeline_edit` | 改时间线**结构**:增删移裁切拼接、gap、顺序 | `{ type, params }` |
| `clip_adjust` | 改片段**画面/音频**:缩放/位置/裁剪/不透明度/音量 | `{ type, params }` |
| `navigate` | 导航/选择/工具/撤销重做/缩放/播放头 | `{ type, params }` |

每个分发器的 `description` 内嵌它所辖的 action 名 + 参数表(自包含,LLM 无需多查一轮)。

### 2.2 单一事实来源:`AgentActionCatalog`

新增 `Sources/FCPXLite/Agent/AgentActionCatalog.swift`——一张 action 元数据表:

```
struct AgentAction {
  let type: String           // LLM 发的 type,如 "insert"
  let domain: Domain         // .timeline / .adjust / .navigate
  let doc: String            // 一句话注释:做什么、何时用
  let params: [ParamSpec]    // 形参名/类型/是否必填/注释
  let apply: (Store, Args) -> String   // 翻译成 EditorAction 并 dispatch,返回结果摘要
}
```

- 工具的 `description`(给 LLM)由 catalog 按 domain **自动生成**——加动作只改一处。
- 翻译逻辑(index→ClipID、seconds→Time)也住在每个 action 的 `apply` 闭包里。
- 这样"清单"与"执行"永远一致,杜绝文档/代码漂移。

### 2.3 扁平动作清单(LLM 可见,index + seconds)

按 domain 列出全部动作(✅=本次必须可用)。索引语义:`clipIndex`=主轴第几个片段(0基),
`assetIndex`=素材库第几个,`atSeconds`=合成时间轴秒。

**timeline_edit**
- ✅ `insert(assetIndex, atSeconds?)` — 把素材插到主轴(默认末尾/播放头)
- ✅ `append(assetIndex)` — 追加到主轴末尾
- ✅ `connect(assetIndex, atSeconds, lane?)` — 作为叠加层连接到主轴(画中画/多轨)
- ✅ `delete(clipIndex, ripple?)` — 删片段(ripple=true 磁性吸合,false 留 gap)
- ✅ `move(fromClipIndex, toClipIndex)` — 调整主轴顺序
- ✅ `blade(clipIndex, atSeconds)` — 在某秒切一刀
- ✅ `trim(clipIndex, edge:"head"|"tail", seconds)` — 修剪首/尾
- ✅ `set_gap(gapIndex, seconds)` — 调整间隙时长
- ✅ `position_move(clipIndex, atSeconds)` — 位置工具:源处留 gap,移到目标

**clip_adjust**(对 clipIndex 片段)
- ✅ `scale(clipIndex, value)` — 缩放 0.1–4
- ✅ `position(clipIndex, x, y)` — 画面位移 px
- ✅ `crop(clipIndex, left?, right?, top?, bottom?)` — 各边裁剪比例 0–1
- ✅ `opacity(clipIndex, value)` — 不透明度 0–1
- ✅ `volume(clipIndex, value)` — 音量 0–2(音乐/音频素材关键)

**navigate**
- ✅ `select(clipIndex)` / `select_asset(assetIndex)` — 选中(供 inspector)
- ✅ `playhead(atSeconds)` — 移播放头
- ✅ `tool(name)` — 切工具(select/trim/position/blade/...)
- ✅ `zoom(pxPerSecond)` — 时间线缩放
- ✅ `undo` / `redo`
- ✅ `import(path)` — 导入磁盘文件到素材库(视频/音乐)

> `volume` 需 `setAdjust` 已支持 `volume`(模型层已有 `Adjustments.volume`,确认 dispatch 路径通)。

### 2.4 数据流

```
LLM → dispatch 工具(type, params)
    → AgentActionCatalog.find(type)
    → action.apply(store, args):  index→ClipID, seconds→Time
    → store.dispatch(EditorAction)   ← 与手动 UI 完全相同的路径
    → 返回结果摘要给 LLM
```

`AgentService` 的工具循环不变;只是 `toolsJSON()` 现在产出 4 个工具,`execute` 改为查 catalog。

## 3. 文件改动

| 文件 | 改动 |
|------|------|
| `Agent/AgentActionCatalog.swift` | **新增**:action 元数据表 + 翻译/执行闭包(单一事实来源) |
| `Agent/AgentToolRegistry.swift` | **重构**:4 个工具的 schema 由 catalog 生成;`execute` 查 catalog;保留 `timelineSummary()`。若超 500 行拆分。 |
| `Agent/AgentService.swift` | 系统提示更新:说明 4 个工具 + 引用 query 先看状态 |
| `Tests/.../AgentDispatchCatalogTests.swift` | **新增**:每个 catalog action 的翻译正确性(纯单测,不连 LLM) |
| `docs/agent-e2e-checklist.md` | **新增**:剪辑全流程操作清单 + Agent 端到端测试结果表 |

## 4. 端到端测试方案(数据驱动,自测 harness)

分两步,均由 **Agent 自己**通过真实路径执行(`store.ui.agentInput` + `sendAgentMessage`),
不绕过 UI;每步用 `/state`、`/preview`、`/previewFrame`、`/layout` 自省断言。

**步骤 A:逐动作冒烟(广度)**
对 2.3 每个 ✅ 动作,构造一条自然语言指令,确认:
(1) LLM 选对工具+type;(2) 翻译正确;(3) `/state` 反映预期变化。
产出对照表:动作 | 指令 | 结果(✅通过 / ❌断 + 原因)。

**步骤 B:真实工作流(深度)**
用 `~/Downloads/_temp/音乐风格` 的真实音乐 + 测试视频,跑一个完整任务,例如:
"导入这3段视频按顺序拼到主轴,导入某首音乐连接为背景音乐并把视频原声压到20%,
在第5秒把第二段切开删掉前半段"。验证多步连贯 + 最终预览。

**测试纪律**(用户铁律):server 永远由用户启动(`bash scripts/run.sh`),
Agent 测完即止,不留后台进程。

## 5. 测试与验证

- **单测**:`AgentDispatchCatalogTests` 覆盖每个 action 的 index→ID / seconds→Time 翻译 + dispatch 后状态。
- **端到端**:步骤 A/B 经 DEBUG 控制服务器 `agentSend` 真实驱动。
- **回归**:现有 151 测试保持通过。

## 6. 风险与权衡

- **LLM 传错 type / 缺参**:catalog 的 `apply` fail-fast 返回明确错误文本给 LLM(它能自纠),不静默兜底。
- **description 膨胀**:4 个工具的总 description 仍远短于 25 个独立工具;按 domain 分散后每个聚焦。
- **index 漂移**:删/移片段后 index 变化——query_timeline 始终给最新 index,提示 LLM 操作前先查。
