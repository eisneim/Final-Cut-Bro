# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Final Cut Bro**（原 FCPX-lite）：SwiftUI + SwiftPM 的 macOS 14 Final Cut Pro 精简克隆，核心目标是给 AI Agent 一个「可被对话完整驱动 + 可自省测试」的剪辑环境。纯 SwiftPM，无外部依赖。

## 常用命令

```bash
# 构建
swift build                       # debug
swift build -c release            # release

# 测试（全量约 350+）
swift test
swift test --filter RetimeAndBatchDeleteTests            # 单个测试类
swift test --filter RetimeAndBatchDeleteTests/testSetTitleDurationOnly  # 单个测试方法

# 运行（server 永远由【用户】启动/关闭，见下方铁律）
bash scripts/run.sh               # debug 版：含 127.0.0.1:8765 调试/自测服务器
bash scripts/run.sh release       # release 版：无服务器，日常使用
bash scripts/stop.sh              # 关闭所有实例 + 释放 8765 端口
bash scripts/make_app.sh          # 打包成 .build/Final Cut Bro.app
```

## 核心架构（跨文件的「大图」）

**1. Redux 单向数据流。** 一切编辑都是 `store.dispatch(EditorAction)`：
- `EditorAction`（`Store/EditorAction.swift`）是 Codable 枚举 —— 命令的「数据化」表示，手动 UI 和 Agent 工具构造的是同一个 action。加新编辑操作 = 先在这里加 case。
- `DocumentStore`（`Store/DocumentStore.swift`，@Observable 单一 store）的 `dispatch` 是中央 switch，把 action 路由到 `Mutations` 的纯函数。`apply { }` 负责 snapshot（撤销）+ 提交；`transaction { }` 把多次 dispatch 折叠成**单次 undo**（批量动作/多选删除用）。高层编辑方法（`deleteSelected` / `updateSelectedAdjust` / `updateSelectedTitle` / `addTitleAtPlayhead` / `trim*` 等）也都在 store 上。
- `Document/Magnetic/Mutations.swift` 是**所有序列变换的纯函数**（insert / rippleDelete / trim / blade / connect / positionMove / setAdjust / setTitle / setClipTiming …），无副作用、可单测。改「剪辑行为」基本都落在这里 + 对应 EditorAction case + dispatch。

**2. 磁性时间线模型。** `Sequence { spine: [Element] }`，`Element = .clip(Clip) | .gap(GapID, Time)`。`Clip` 自己只存 `sourceIn/duration`，连接片段（字幕/叠加，L2/L3）用 `lane` + `offset`（相对宿主起点）。时间用有理数 `Time { value, timescale }`。`Layout.compute(sequence)` 把 spine 展开成带绝对坐标的 `[Placed]`（预览/绘制/命中都用它）；`TimelineGeometry` 提供 `spineIndex(ofClipID:)` 等几何查询。

**3. Agent 三层。**
- `Agent/AgentActionCatalog.swift` = **所有 agent 动作的唯一真源**。每个 `AgentAction` = `type` + `domain`(.timeline/.adjust/.navigate/.system) + `params`(ParamSpec) + `apply` 闭包（闭包内调 `store.dispatch`）。**加/改 Agent 能力就改这个文件。**
- `Agent/AgentToolRegistry.swift` 按 domain 把 catalog 聚成 **5 个** LLM function-tool（timeline_edit / clip_adjust / navigate / query_timeline / file_ops），`execute` 按 type 路由回 catalog。
- `Agent/AgentService.swift` 跑流式对话循环：工具调用 → 执行 → 结果喂回 → 最终文本。危险操作（write/edit/run）走**确认卡片**机制：apply 返回 `__PENDING_CONFIRM__` 哨兵 → service 轮询 `store.agentConfirm` → 用户在 chat 里点「允许/拒绝」（`AgentConfirm` 持一个 `@MainActor (Bool)->String` 闭包）。

**4. 渲染 / 导出管线。** `Engine/Composition/CompositionBuilder.swift` 把 `Sequence` 编译成 `AVMutableComposition + VideoComposition + AudioMix`，**预览和导出共用**。`CoreImageCompositor` 是自定义 compositor（变换/不透明度/特效/字幕合成），`TitleRenderer` 把 `TitleSpec` 渲成 CIImage。预览 `PreviewView`(AVPlayer)，导出 `Export/MovieExporter.swift`（成片）或 `FCPXMLExporter.swift`（导 FCPXML）。

**5. 调试/自测服务器。** `DebugControlServer.swift`（仅 DEBUG，:8765）暴露 `/state` `/cmd` `/agent` `/screenshot` 等，让 Agent 能自己驱动 app + 自省结果做端到端测试。`scripts/*_e2e*.py` 是配套的真实-LLM 驱动脚本。

## 文件索引（改哪个功能 → 看哪几个文件）

**顶层 / 生命周期**
- `main.swift` — 入口
- `AppDelegate.swift` — NSApp 生命周期 + **系统菜单栏** + 全局快捷键（键码 → store 方法）
- `DebugControlServer.swift` — DEBUG :8765 自测服务器（加自测钩子、新 `/cmd` op 在此）

**Store（编辑状态与命令层）** — 改剪辑逻辑先看这里
- `Store/DocumentStore.swift` — 中央 store：dispatch/apply/snapshot/transaction + 所有高层编辑方法
- `Store/EditorAction.swift` — 可 Codable 动作枚举（新操作先加 case）
- `Store/UIState.swift` — 选择态（selectedClipID/selectedClipIDs/selectedAssetIDs）、面板宽度、播放头、缩放
- `Store/EditTool.swift` — 工具枚举（select/trim/position/range/blade/zoom/hand）
- `Store/SpringTool.swift` — 弹簧工具状态机（按住临时切换、短按永久切换）

**Document（数据模型 + 磁性算法）**
- `Document/Spine.swift` — `Document` / `Project` / `Sequence` 三个顶层结构
- `Document/Clip.swift` — 片段模型（sourceIn/duration/connected/lane/offset/title/adjust/effects/关键帧/crossfadeIn/enabled）
- `Document/Element.swift` — `.clip | .gap`
- `Document/Magnetic/Mutations.swift` — **所有序列纯函数变换**（改剪辑行为的核心）
- `Document/Magnetic/Layout.swift` — Sequence → `[Placed]`（绝对坐标）
- `Document/Magnetic/TimelineGeometry.swift` — spineIndex / 时间↔片段 查询
- `Document/Magnetic/{Invariants,Snapping,ExperimentReport}.swift` — 不变量校验 / 吸附 / 布局对照报告

**Models**
- `Models/Time.swift` — 有理数时间；`Models/Ids.swift` — Asset/Clip/Project/GapID
- `Models/Asset.swift` — 素材 + MediaKind；`Models/Adjustments.swift` — Transform/Crop/Adjustments/Volume+Transform 关键帧
- `Models/TitleSpec.swift` — 标题/字幕规格；`Models/Effect.swift` — 特效

**Agent** — 改 Agent 能力先看这里
- `Agent/AgentActionCatalog.swift` — **所有 agent 动作真源**（加/改动作在此）
- `Agent/AgentToolRegistry.swift` — 5 个 LLM 工具的聚合与路由
- `Agent/AgentService.swift` — 流式对话循环 + 确认卡片轮询
- `Agent/AgentMessage.swift` — 消息 / `AgentConfirm` / 线协议 / ThinkSplitter
- `Agent/StreamingOpenAIBackend.swift` — OpenAI 兼容 SSE 后端
- `Agent/LLMProvider.swift` — provider 配置持久化（`~/Library/Application Support/FCPXLite/providers.json`）

**Engine（渲染/媒体）**
- `Engine/Composition/CompositionBuilder.swift` — Sequence → AV 合成（预览+导出共用）
- `Engine/Composition/CoreImageCompositor.swift` — 自定义 compositor（变换/不透明/特效/字幕）
- `Engine/Composition/{CompositorInstruction,TitleRenderer,VideoEffectFilters,TransformKeyframeMath}.swift`
- `Engine/Media/MediaImporter.swift` — 文件 → Asset（探测时长/尺寸/音轨）

**Export**
- `Export/MovieExporter.swift` — 导出成片；`Export/FCPXMLExporter.swift` — 导 FCPXML；`Export/ExportSettings.swift` — 编解码/质量/分辨率枚举

**Views（SwiftUI + 关键 AppKit 画布）**
- `Views/RootView.swift` — 顶层布局（左工作区 + 右 Chat + sheet 门控）
- `Views/TimelineContentView.swift` (+`+Drag`/`+VolumeLine`/`+VolumeDrag`/`+GapDrag`/`+Transition`) — **AppKit NSView 时间轴**：绘制 + 鼠标交互（框选多选 / trim / blade / 擦洗播放头 / 音量线 / 间隙拖拽 / 转场）
- `Views/TimelineCanvas.swift` — 把上面的 NSView 包成 SwiftUI + 注入 State
- `Views/TimelineToolbar.swift` / `TimelineIcons.swift` / `TimelineColors.swift` / `TimelineMediaCache.swift`（缩略图/波形异步缓存）
- `Views/BrowserView.swift` + `AssetStripCell.swift` + `AssetStripLayout.swift` + `SkimFrameProvider.swift` — 素材池（胶片条 / 擦洗预览 / 右键删除）
- `Views/InspectorView.swift` (+`InspectorTitleSection`/`InspectorEffectsSection`) — 检查器，调参回 `store.updateSelected*`
- `Views/PreviewView.swift` — AVPlayer 预览（`ViewerView`）
- `Views/ChatPanelView.swift` — Agent 对话 UI + 确认卡片
- `Views/{ExportPanel,SettingsView,ProjectBar,ProjectCreationModal,EffectsPanel,ImportPanel}.swift` — 面板/弹窗
- `DesignSystem/Tokens.swift`（调色板/字号/间距）、`DesignSystem/Color+Hex.swift`

**Tests** — 与源码同结构，命名 `<被测主题>Tests.swift`。Mutations/几何/Agent-catalog 都是纯函数，优先在此层加测试；Agent 动作可用 `AgentActionCatalog.find(type)!.apply(store, args)` 直接驱动。

## 项目铁律（务必遵守）

- **server 永远由用户控制。** 测试用的 server 每次必须由用户启动/关闭，你**不能自己开后台进程**（否则用户无法自己重启、发现不了问题）。需要用户跑命令时，提示他用 `! <cmd>` 或 `bash scripts/run.sh`。
- **单文件不超过 500 行**，超了就按职责拆分。React 式：组件 `.swift` 与其样式/子节放一起，不要塞进一个大文件。
- **fail fast / fail early。** dev 阶段不写 fallback/兜底，尽早暴露 bug；调试时不要删 try/except，让异常 raise 看到真实错误。
- **对照实验优先。** 参数/流程不确定时不要凭感觉改+等人工验证；把变量做成启动参数、批量跑网格、用 CV/数据对比找规律（见记忆 `debug-controlled-experiments`）。
- **已知未修 bug：** 多段+多字幕成片导出末尾卡在 audio reader finalize（见记忆 `fcpx-lite-export-audio-stall`）。
- 从 HuggingFace 下模型要加代理前缀：`https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890`；本地 ASR 脚本需 `conda run -n mlx`。
