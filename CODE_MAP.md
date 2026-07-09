# CODE_MAP · Final Cut Bro

> 导航索引:文件 → 职责 + 「功能 → 该看哪几个文件」速查。改功能先查下面第一张表。
> 维护约定:**某文件职责变了,就更新它对应的那一行**;新增子系统就在功能表加一行。
> 生成于 2026-07-06。

**Final Cut Bro**(原 FCPX-lite):SwiftUI + AppKit 的 macOS 14 Final Cut Pro 精简克隆,核心目标是给 AI Agent 一个「可被对话完整驱动 + 可自省测试」的剪辑环境。纯 SwiftPM,零外部依赖。

---

## 功能 → 文件(最高频速查)

| 功能 / 你想改什么 | 关键文件 |
|---|---|
| **加/改一种编辑操作**(剪、移、trim…) | `Store/EditorAction.swift`(加 case)→ `Store/DocumentStore.swift`(dispatch 路由)→ `Document/Magnetic/Mutations*.swift`(纯函数实现) |
| **磁性时间线算法**(insert/ripple/trim/blade/connect/relocate/slip/slide) | `Document/Magnetic/Mutations.swift` + `Mutations+Trim.swift` + `Mutations+Fields.swift` |
| **连接片段(字幕/配乐)trim 时长 + 拖拽跟手** | `Mutations.swift`(relocateConnected/setClipTiming)+ `Views/TimelineContentView+Drag.swift` + `Store/DocumentStore+Playhead.swift`(⌥[]) |
| **时间线绘制 / 鼠标交互** | `Views/TimelineContentView.swift` + `+Draw`/`+Drag`/`+Cursor`/`+GapDrag`/`+VolumeLine`/`+VolumeDrag`/`+Transition`/`+Invalidate` |
| **时间↔像素↔片段 坐标换算** | `Document/Magnetic/Layout.swift`(→ `[Placed]` 绝对坐标)+ `TimelineGeometry.swift` + `Views/TimelineCanvas.swift` |
| **加/改 Agent 能力(工具/动作)** | `Agent/AgentActionCatalog.swift` + `+Timeline`/`+Adjust`/`+Navigate`/`+System`(真源)→ `AgentToolRegistry.swift`(聚成 5 工具) |
| **Agent 对话循环 / 流式 / 确认卡片** | `Agent/AgentService.swift` + `AgentMessage.swift` + `StreamingOpenAIBackend.swift` |
| **LLM provider 配置** | `Agent/LLMProvider.swift` + `Views/SettingsView.swift` |
| **渲染 / 合成(预览+导出共用)** | `Engine/Composition/CompositionBuilder.swift` → `CoreImageCompositor.swift` + `CompositorInstruction.swift` + `TitleRenderer.swift` + `VideoEffectFilters.swift` |
| **导出成片 / FCPXML** | `Export/MovieExporter.swift`(⚠ 已知末尾卡死 bug)/ `FCPXMLExporter.swift` / `ExportSettings.swift` |
| **检查器调参(变换/裁剪/调色/字幕/特效)** | `Views/InspectorView.swift` + `InspectorTitleSection`/`InspectorEffectsSection`/`InspectorMetaSection` → 回 `DocumentStore.updateSelected*` |
| **素材池(胶片条/擦洗/右键)** | `Views/BrowserView.swift` + `AssetStripCell.swift` + `AssetStripLayout.swift` + `SkimFrameProvider.swift` |
| **skimming(划过时间轴预览帧)** | `Store/UIState.swift`(timelineSkimming/timelineSkimSeconds)+ `TimelineContentView+Cursor.swift` + `DocumentStore`(togglePlay 覆盖 skim,blade 在 skim 光标) |
| **工具切换 / 快捷键 / 菜单栏** | `AppDelegate.swift`(键码→store + NSMenu)+ `Store/EditTool.swift` + `Store/SpringTool.swift`(弹簧工具) |
| **界面多语言(运行时中/英切换)** | `i18n/Localization.swift` + `i18n/Strings.swift` + `Views/TitlebarAccessories.swift`(切换器)+ `AppDelegate`(菜单重建) |
| **导出面板 / 设置 / 项目 / 创建弹窗** | `Views/ExportPanel.swift` / `SettingsView.swift` / `ProjectBar.swift` / `ProjectCreationModal.swift` / `EffectsPanel.swift` / `ImportPanel.swift` |
| **自测 / 端到端(Agent 自驱 app)** | `DebugControlServer.swift`(DEBUG :8765,仅 loopback)+ `scripts/*_e2e*.py` |
| **性能测量** | `DebugSupport/PerfProbe.swift` + `Views/TimelineContentView+Invalidate.swift`(定向重画) |

---

## 顶层 / 生命周期

| 文件 | 职责 |
|---|---|
| `Sources/FCPXLite/main.swift` | 入口 |
| `AppDelegate.swift` | NSApp 生命周期 + 系统菜单栏(NSMenu,`t()` 本地化,语言切换重建)+ 全局快捷键(键码→store)+ NSToolbar(语言/面板/导出)+ 自定义关于面板 + DEBUG 起自测 server |
| `DebugControlServer.swift` | DEBUG :8765 自测服务器(仅 127.0.0.1):`/state` `/cmd` `/agent` `/screenshot`,让 Agent 自驱 + 自省 |
| `Package.swift` | SwiftPM 清单(swift-tools 5.9,无外部依赖) |

## Store(编辑状态与命令层)—— 改剪辑逻辑先看这里

| 文件 | 职责 |
|---|---|
| `Store/DocumentStore.swift` | 顶层单一 @Observable store:dispatch/apply/snapshot/transaction + beginInteractiveEdit(手势级 undo 合并) |
| `Store/DocumentStore+Editing.swift` | 高层编辑操作(工具栏按钮 + 快捷键共用):connect/insert/append/overwrite/updateSelected*/createProject(fromAsset) 等 |
| `Store/DocumentStore+Playhead.swift` | 播放头 / 切割 / 删除 / ⌥[]trim(含选中连接片段)/ nudge / 头尾 |
| `Store/EditorAction.swift` | 可 Codable 动作枚举 —— 命令的「数据化」表示(新操作先加 case) |
| `Store/UIState.swift` | 选择态 + 面板宽度 + 播放头 + 缩放 + skimming(timelineSkimming/timelineSkimSeconds)+ Inspector 聚焦跟随 |
| `Store/EditTool.swift` | 工具枚举(select/trim/position/range/blade/zoom/hand) |
| `Store/SpringTool.swift` | 弹簧工具状态机(纯值,可测):按住临时切、短按永久切 |

## Document(数据模型 + 磁性算法)

| 文件 | 职责 |
|---|---|
| `Document/Spine.swift` | `Document` / `Project` / `Sequence` 三个顶层结构;主时间线 = 有序元素数组 |
| `Document/Spine+Lookup.swift` | 按 id 查 clip / 素材的单一真源(消除散落各处的重复扫描) |
| `Document/Clip.swift` | 片段模型(sourceIn/duration/connected/lane/offset/title/adjust/effects/关键帧/crossfade/enabled) |
| `Document/Element.swift` | 主轴元素:`.clip \| .gap`(gap 带 id,可选中/拖动/修剪) |
| `Document/Magnetic/Mutations.swift` | **所有序列纯函数变换的唯一入口**(insert/rippleDelete/relocate/relocateConnected/setClipTiming…) |
| `Document/Magnetic/Mutations+Trim.swift` | trim / blade / roll / slip / slide 变换 |
| `Document/Magnetic/Mutations+Fields.swift` | 字段级变换(setAdjust/setTitle/setEffects/关键帧…) |
| `Document/Magnetic/Layout.swift` | Sequence → `[Placed]`(绝对坐标,预览/绘制/命中都用) |
| `Document/Magnetic/TimelineGeometry.swift` | 纯函数:像素坐标 ↔ 主轴下标 / spineIndex(ofClipID:) |
| `Document/Magnetic/Snapping.swift` | 纯函数吸附(阈值 = 像素÷缩放,引擎不碰像素) |
| `Document/Magnetic/Invariants.swift` | 磁性不变量校验(spine 首尾相接等) |
| `Document/Magnetic/ExperimentReport.swift` | 对照实验数据导出(布局摊平成可比对位置表 / CSV) |

## Models

| 文件 | 职责 |
|---|---|
| `Models/Time.swift` | 有理数时间(CMTime 语义),避免浮点累积 |
| `Models/Ids.swift` | Asset/Clip/Project/GapID |
| `Models/Asset.swift` | 素材 + MediaKind |
| `Models/Adjustments.swift` | Transform/Crop/Adjustments/Volume + 关键帧 |
| `Models/TitleSpec.swift` | 标题/字幕规格(clip.title 非 nil = 标题片段) |
| `Models/Effect.swift` | 特效种类(color/blur 视频滤镜;fade 音频淡入淡出) |

## Agent —— 改 Agent 能力先看这里

| 文件 | 职责 |
|---|---|
| `Agent/AgentActionCatalog.swift` | **所有 agent 动作真源** + 领域枚举(加/改动作在此及下面 4 个分片) |
| `Agent/AgentActionCatalog+Timeline.swift` | timeline 域动作 |
| `Agent/AgentActionCatalog+Adjust.swift` | adjust 域动作 |
| `Agent/AgentActionCatalog+Navigate.swift` | navigate 域动作 |
| `Agent/AgentActionCatalog+System.swift` | system / file_ops 域动作 |
| `Agent/AgentToolRegistry.swift` | 按 domain 聚成 5 个 LLM function-tool,execute 按 type 路由回 catalog |
| `Agent/AgentService.swift` | 流式对话循环:工具调用→执行→喂回→最终文本;危险操作走确认卡片轮询 |
| `Agent/AgentMessage.swift` | 消息 / AgentConfirm / 线协议 / ThinkSplitter |
| `Agent/StreamingOpenAIBackend.swift` | OpenAI 兼容 SSE Chat Completions + function calling 后端 |
| `Agent/LLMProvider.swift` | provider 配置持久化(`~/Library/Application Support/FCPXLite/providers.json`) |

## Engine(渲染 / 媒体)

| 文件 | 职责 |
|---|---|
| `Engine/Composition/CompositionBuilder.swift` | Sequence → AVMutableComposition + VideoComposition + AudioMix(预览+导出共用) |
| `Engine/Composition/CoreImageCompositor.swift` | 自定义 compositor(变换/不透明/特效/字幕合成) |
| `Engine/Composition/CompositorInstruction.swift` | compositor 每帧指令 |
| `Engine/Composition/TitleRenderer.swift` | TitleSpec → CIImage |
| `Engine/Composition/VideoEffectFilters.swift` | 视频特效滤镜(Core Image) |
| `Engine/Composition/TransformKeyframeMath.swift` | 变换关键帧纯数学(可单测) |
| `Engine/Media/MediaImporter.swift` | 文件 → Asset(探测时长/尺寸/音轨) |

## Export

| 文件 | 职责 |
|---|---|
| `Export/MovieExporter.swift` | 导出成片(AVAssetReader/Writer,视频/音频分离 reader)⚠ 多段+多字幕末尾卡死 |
| `Export/FCPXMLExporter.swift` | 导出 FCPXML(可进 Final Cut Pro 继续剪) |
| `Export/ExportSettings.swift` | 编解码 / 质量 / 分辨率枚举 |

## Views(SwiftUI + 关键 AppKit 画布)

| 文件 | 职责 |
|---|---|
| `Views/RootView.swift` | 顶层布局(左工作区 + 右 Chat + sheet 门控) |
| `Views/TimelineContentView.swift` | AppKit 自定义画布主文件:标尺/片段/播放头 + 鼠标分发 |
| `Views/TimelineContentView+Draw.swift` | 绘制层(draw(_:) 及所有 draw* 方法) |
| `Views/TimelineContentView+Drag.swift` | 鼠标交互按工具分支:框选/trim/blade/擦洗/移动/连接片段 trim+拖拽 |
| `Views/TimelineContentView+Cursor.swift` | 光标(NSTrackingArea/cursorUpdate)+ skimming 命中 + 吸附 |
| `Views/TimelineContentView+GapDrag.swift` | 主轴 gap 的选中/修剪/拖动/删除 |
| `Views/TimelineContentView+VolumeLine.swift` | 音量 level 线绘制(fade 三角手柄 + 关键帧点) |
| `Views/TimelineContentView+VolumeDrag.swift` | 音量 level 线拖拽交互 |
| `Views/TimelineContentView+Transition.swift` | 转场(交叉叠化)选中 / 边缘拖拽改时长 |
| `Views/TimelineContentView+Invalidate.swift` | 定向失效矩形数学(只重画一小块,避开 92ms 全画) |
| `Views/TimelineCanvas.swift` | 把上面 NSView 包成 SwiftUI(NSScrollView + 注入 State) |
| `Views/TimelineToolbar.swift` / `TimelineIcons.swift` / `TimelineColors.swift` / `TimelineCursors.swift` | 时间线工具栏 / 图标 / AppKit 画布颜色 / 自定义光标(放大镜/剃刀/范围/移动) |
| `Views/TimelineMediaCache.swift` | 缩略图 / 波形异步缓存 |
| `Views/BrowserView.swift` + `AssetStripCell.swift` + `AssetStripLayout.swift` + `SkimFrameProvider.swift` | 素材池(胶片条 / 擦洗预览 / 布局数学 / 右键) |
| `Views/InspectorView.swift` + `InspectorTitleSection` / `InspectorEffectsSection` / `InspectorMetaSection` | 检查器(变换/裁剪/调色/字幕/特效/只读元信息),调参回命令层 |
| `Views/PreviewView.swift` + `TitleOverlay.swift` | AVPlayer 预览 + 标题画面内可拖框 |
| `Views/ChatPanelView.swift` + `ChunkedStreamingView.swift` | Agent 对话 UI + 确认卡片 + 分块流式文本(避 O(N²) 卡死) |
| `Views/ExportPanel.swift` / `SettingsView.swift` / `ProjectBar.swift` / `ProjectCreationModal.swift` / `EffectsPanel.swift` / `ImportPanel.swift` | 面板 / 弹窗 |
| `Views/TitlebarAccessories.swift` + `ToolbarIcons.swift` | 标题栏按钮(语言切换器 / 面板切换 / 导出)+ 顶栏矢量图标 |
| `Views/EditableNumberField.swift` / `WidthDragHandle.swift` / `VolumeLineMath.swift` | 双击编辑数值字段 / 面板分隔线拖拽 / 音量线纯数学 |

## i18n

| 文件 | 职责 |
|---|---|
| `i18n/Localization.swift` | Language 枚举 + @Observable 单例(运行时切换,发 `.fcbLanguageChanged`)+ 全局 `t()` + 持久化 |
| `i18n/Strings.swift` | 中文源串 → { 语言: 译文 } 查表(仅用户界面串,⚠ 勿重复 key 否则字面量初始化崩) |

## DesignSystem / DebugSupport

| 文件 | 职责 |
|---|---|
| `DesignSystem/Tokens.swift` | 设计令牌(调色板/字号/间距,源自 style.md 实采,视图禁裸 hex) |
| `DesignSystem/Color+Hex.swift` | Color/NSColor hex 扩展 |
| `DebugSupport/PerfProbe.swift` | 轻量性能探针(按 name 聚合次数/耗时,可 dump/reset) |

## scripts(自测 / 实验,Python)

| 文件 | 职责 |
|---|---|
| `scripts/run.sh` / `stop.sh` / `make_app.sh` | 启动(debug 含 server / release)/ 关闭所有实例+释放 8765 / 打包 .app |
| `scripts/agent_e2e_smoke.py` / `agent_e2e_workflow.py` | Agent 端到端(真实 LLM 发指令,轮询 /state 断言) |
| `scripts/subtitle_e2e_720x1280.py` / `subtitle_e2e_raw.py` | 口播字幕剪辑端到端 |
| `scripts/asr_edit_experiment.py` / `perf_streaming_experiment.py` / `fileops_e2e.py` | ASR→Agent 剪辑实验 / 流式性能对照 / file_ops 确认卡片端到端 |

---

## 关键事实

- **入口**:`Sources/FCPXLite/main.swift`(纯 SwiftPM 可执行,无 storyboard)。
- **构建**:`swift build`(debug)/ `swift build -c release`。
- **测试**:`swift test`(约 350+,与源码同结构,`<主题>Tests.swift`);单类 `swift test --filter <类名>`。纯函数(Mutations/几何/Agent-catalog/i18n)优先在此层加测试。
- **运行**:`bash scripts/run.sh`(debug,含 127.0.0.1:**8765** 自测服务器)/ `bash scripts/run.sh release`(无 server,日常用)/ `bash scripts/stop.sh`(关全部+释放端口)。**server 永远由用户启停,不开后台进程。**
- **打包**:`bash scripts/make_app.sh` → `.build/Final Cut Bro.app`。
- **配置持久化**:`~/Library/Application Support/FCPXLite/`(providers.json / language.json,不入库)。
- **架构主线**:Redux 单向流(EditorAction 数据化命令 → dispatch → Mutations 纯函数),手动 UI 与 Agent 工具走同一条路。
