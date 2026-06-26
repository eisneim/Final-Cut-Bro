# FCPX-lite 里程碑 1 设计文档

> 日期:2026-06-26
> 状态:设计已逐节确认,待用户最终评审
> 配套文件:`design/style.md`(实采配色规范)、`design/fcpx_ui.jpg`(参考截图)、`.superpowers/brainstorm/.../layout-v4.html`(布局定稿 mockup)

---

## 0. 项目愿景与本里程碑范围

**愿景**:做一个简化版、可控的 FCPX 复刻品,核心目的是为 AI Agent 提供一个"可装工具的剪辑环境"——最终实现人机结合的创作:Agent 通过对话驱动剪辑流程,用户随时手动接管修改。原生 FCPX 无法接入 AI(只能靠 AXAPI 受限控制),所以自建。

**总构建顺序**:UI 外壳 → 资源管理器 → 时间线 + 预览 → AI chat(最后)。先把"可手动操作的环境"建好,Agent 才有工具可调。

**里程碑 1 范围**:一个手动可用的极简 FCPX。
- ✅ 五区布局外壳(含 Chat 空占位面板)
- ✅ 资源管理器 + 媒体导入
- ✅ 全套磁性时间线(L1 主轴 + L2 连接片段 + L3 泳道)
- ✅ 实时预览播放
- ✅ 基础 Inspector(变换/裁切/不透明度/音量)
- ✅ 导出 `.fcpxml` 回真 FCPX
- ⬜ Chat 面板留空(命令层就绪,M2 接 Agent 零重构)
- ⬜ 特效/转场:UI 留位,不实现
- ⬜ 导出渲染(编码成片):后置里程碑

**里程碑 1 完成定义(DoD)**:导入素材 → 拖进磁性时间线编辑(磁吸/ripple/连接片段/lane 全可用)→ 预览播放拼接结果 → 基础 Inspector 调参实时反映 → 导出 `.fcpxml` 真 FCPX 能打开。

---

## 1. 架构总览

三层 + 一个 Agent 预留口:

```
UI 层 (SwiftUI 外壳 + AppKit 自绘时间线 + AVPlayerLayer 预览)
   └─ 只读渲染文档状态;只通过命令层发起修改
命令层 / Mutation API   ← ★唯一修改入口,也是 Agent 预留口
   insertClip / moveClip / trimClip / blade / connectClip / ...
   (手动 UI 调它;未来 Agent 工具也调它 —— 同一个口)
文档模型 Document (单一数据源, FCPXML-aligned, @Observable)
   Project → Sequence → Spine[Element] + connected[Clip](lane/offset)
引擎层 Engine
   ① 磁性布局引擎 (纯逻辑, 无 UI, 可单测)
   ② 合成/预览引擎 (Document → AVMutableComposition → AVPlayer)
   ③ 媒体/资源 (AVAsset 导入, 缩略图, 元数据)
```

**三条核心原则:**
1. **文档是唯一数据源,UI 是它的纯函数**。任何 UI 都不藏状态;手动改和 Agent 改看到同一个世界。
2. **所有修改只走命令层 —— 这就是 Agent 预留口**。手动拖拽底层调具名命令;Agent 工具未来包一层 schema 暴露同一批命令,零重构。命令层也是 undo/redo 落点。
3. **磁性逻辑是纯数据计算,与绘制彻底分离**。最绕的联动是 `[Element]→[Element]` 纯函数,不碰 UI / 不碰 AVFoundation,可穷举测试。

**混合栈分工:**

| 区域 | 技术 | 理由 |
|------|------|------|
| 外壳 / 资源管理器 / Inspector / Chat | SwiftUI(`NSHostingView` 托管) | 布局/列表/表单开发快 |
| 时间线画布 | AppKit `NSView` 自绘(Core Animation)+ `NSViewRepresentable` | 像素级拖拽/吸附命中/多 lane 滚动需完全控制;后期可平滑升级 Metal |
| 预览区 | `AVPlayerLayer` + `AVPlayer` | AVFoundation 负责解码/同步/实时合成,不造 codec |

**栈与工程约定**(沿用用户既有 Swift 项目 `meetingAssitant` / `feishu_msg`):
- SwiftPM(`Package.swift` + `.executableTarget`,`.macOS(.v14)`),不用 Xcode project
- AppKit 入口(`main.swift` + `AppDelegate`)+ SwiftUI 视图托管
- `scripts/make_app.sh` 打包 `.app`,**由用户自己启停,测试后关闭**
- 单文件 ≤ 500 行,超了拆分;`.swift` 不混大样式;Token 集中在 DesignSystem

**目录:**
```
Sources/FCPXLite/
  main.swift, AppDelegate.swift
  Document/        # 纯逻辑: 模型 + 命令层 + 磁性引擎(无 UI, 重单测)
    Magnetic/      # layout + mutation + snapping
  Engine/
    Composition/   # CompositionBuilder + PreviewController
    Media/         # MediaImporter + 缩略图缓存
  Views/           # RootView(五区) / Browser / Inspector / ChatPanel(占位)
  Timeline/        # AppKit 自绘画布 + NSViewRepresentable 桥
  Models/          # 跨层共享值类型
  Store/           # @Observable 顶层 store
  DesignSystem/    # Tokens(落 style.md) / Controls
  Export/          # FCPXML 导出器
Tests/             # 磁性引擎为重点
scripts/           # make_app.sh / make_icon.sh
```

---

## 2. 文档模型(FCPXML-aligned JSON)

概念与 FCPXML 一一对应,使导出近乎字段平移。

```
Project
 ├─ format        分辨率/帧率           → <format>
 ├─ assetLibrary  [Asset] 引用表
 └─ Sequence
     └─ Spine = [Element]               ← 主时间线(primary storyline, L1)
         Element = Clip | Gap           顺序排列, 首尾相接, 无重叠
         每个 spine 上的 Clip 可挂:
           connected: [Clip]            ← 连接片段(L2), 各带 {lane, offset}
                                          lane>0 上方 / <0 下方(L3 泳道)
                                          offset = 相对【宿主 clip 起点】的锚点
```

**关键设计点:**

1. **有理数时间,不用浮点**:`struct Time { value: Int64; timescale: Int32 }`(= CMTime 语义)。避免浮点累积导致帧不对齐——剪辑中最致命的 bug。UI 显示时转时间码。

2. **Clip 引用 asset,自己只存 in/out**:
```swift
struct Clip {
    let id: ClipID
    var assetID: AssetID
    var sourceIn: Time        // 素材内入点
    var duration: Time        // 时间线上占用时长
    var connected: [Clip]     // L2
    var lane: Int             // 仅 connected 用; spine 上恒 0
    var offset: Time          // 仅 connected 用; 相对宿主起点
    var adjust: Adjustments
}
```
一个 asset 可被多个 clip 引用(切多段),互不影响。

3. **Spine 元素的绝对起点是算出来的,不存储**:第 N 个起点 = 前面所有 duration 之和。存绝对 start 会与磁性规则打架。绝对位置由磁性引擎实时算 —— 这是磁性正确性的根。

4. **Inspector 参数挂 clip**:
```swift
struct Adjustments {
    var transform = Transform()  // position/scale/rotation/anchor → <adjust-transform>
    var crop = Crop()            // → <adjust-crop>
    var opacity = 1.0            // → <adjust-blend> / video opacity
    var volume = 1.0             // → <adjust-volume>
}
```

5. **值类型 + 顶层 @Observable**:`Document` 内部全 `struct`(值语义,易快照 undo、易测);最外 `@Observable final class DocumentStore { var document: Document }` 供 SwiftUI 观察,命令层修改它。

**FCPXML 映射**:`Spine→<spine>`、`Clip→<asset-clip>/<video>`、`Gap→<gap>`、`lane/offset→`连接片段属性、`Time→"value/timescaleS"`、`Adjustments→<adjust-*>`。导出器是递归遍历 + 字符串拼装,无语义转换。

---

## 3. 磁性引擎(纯逻辑核心)

`Document/Magnetic/`,无 UI、无 AVFoundation。两件事:Layout(算绝对位置给画布)、Mutation(保持不变量地改文档)。

**建模 = 方案 A:有序 spine 数组(位置隐式)**。磁性隐含在数组顺序,绝对起点 = 前缀和。(否决方案 B 约束求解器:偏离 FCPXML、隐藏复杂度、非确定性,对 v1 过度设计。)

**三条不变量(测试的核心断言):**
1. **主轴连续**:lane 0 元素首尾相接、无重叠、按位置有序(空隙用显式 Gap)。
2. **连接跟随**:connected clip 绝对位置 = `宿主.absStart + offset`;宿主 ripple 移动时自动跟随。
3. **泳道隔离**:同一时间区间内多个 connected clip 只能在不同 lane。

**Layout(纯函数,前缀和):**
```
t = 0
for el in spine:
  el.absStart = t; t += el.duration
  for c in el.connected:
    c.absStart = el.absStart + c.offset
```

**操作 → 磁性涌现:**

| 操作 | 实现 | 磁性来源 |
|------|------|---------|
| 插入到主轴第 i 位 | 数组 insert | 后续 absStart 自动右移(前缀和) |
| 删除(ripple delete,默认) | 数组 remove | 后续自动左移合拢 |
| 删除留洞(lift) | 替换为 Gap | 显式保留空隙 |
| 主轴内移动/换序 | remove + insert | = 一次 ripple |
| 拖到上/下方变连接片段 | 设 lane(按落点垂直位置)、宿主=落点所在主轴 clip、offset=落点start−宿主absStart | 之后宿主一动即跟随 |
| ripple trim(默认,拖边缘) | 改 duration(右)或 sourceIn+duration(左),夹在素材边界内 | 后续跟前缀和移动 |
| blade 切割 @T | 拆成两共享 asset 的 clip(按比例分 sourceIn/duration);connected 按各自 offset 归左/右半 | — |

**红利**:offset 锚在宿主起点(第 2 节决策),主轴怎么 ripple 只需重算宿主 absStart,连接片段全自动跟随,无额外联动代码。这化解了项目最绕的部分。

**吸附(纯函数)**:`snap(t, candidates, threshold)`,candidates = 其它 clip 边缘 + 播放头 + 序列起点 + 标记;threshold 由画布把"像素阈值 ÷ 缩放"换算成时间传入。引擎不碰像素。

**硬边界:**
- 宿主被删:connected 子节点重锚到删除后占据该时间的主轴 clip,重算 offset 保持绝对位置不变;该处为 Gap/无 clip 则锚到最近主轴 clip。
- trim 越界:夹紧 `sourceIn≥0` 且 `sourceIn+duration≤asset.duration`。
- 空主轴:第一个 clip 落 t=0。

**v1 不做**:roll / slip / slide 等高级 trim。

---

## 4. 预览/合成引擎

**不重新编码时间线**:`AVMutableComposition` 是虚拟剪辑配方,`AVPlayer` 实时解码源帧 + 实时合成,无中间文件。编码只在导出(后置)发生。

**方案 = 纯 AVFoundation 内建合成**(否决自研 Metal 合成器,留给后续特效里程碑)。关键:v1 的 Inspector 参数内建 API 全覆盖——`AVMutableVideoCompositionLayerInstruction`(setTransform/setCropRectangle/setOpacity)+ `AVAudioMix`(逐 clip 音量)。**v1 不写自定义合成器**。

**文档 → 合成映射**(lane 摊平成轨道):

| 文档 | AVFoundation |
|------|--------------|
| 主轴 spine | 基础视频轨 track 0 |
| 每条 lane | 各分配视频轨(同时刻重叠的 clip 必在不同轨) |
| Clip | 往对应轨 `insertTimeRange(sourceIn..+duration, at: absStart)` |
| lane 顺序(z 序) | videoComposition instruction 中 layer 叠放次序 |
| Adjustments transform/crop/opacity | 该 clip 时段 layerInstruction |
| Adjustments volume | audioMix 输入参数 |
| project.format | videoComposition `renderSize` + `frameDuration` |

不同帧率/分辨率素材统一缩放到 renderSize。

**模块** `Engine/Composition/`:
- `CompositionBuilder`:纯函数 `Document → (AVComposition, AVVideoComposition, AVAudioMix)`,可单测。
- `PreviewController`:持 `AVPlayer`+`AVPlayerLayer`,负责 rebuild/seek/play-pause/周期时间观察(驱动播放头)。
- `PreviewView`:`NSViewRepresentable` 托管 `AVPlayerLayer`。

**重建/同步策略(v1 务实版):**
- 文档 commit 一次修改后重建合成,`replaceCurrentItem` 并保持当前时间。
- 拖拽进行中**不重建**,画布只画 ghost;落下(commit)才重建。
- 拖播放头:进行中容忍 seek(流畅),松手精确 seek(`.zero` 容忍,帧准)。
- `addPeriodicTimeObserver` 驱动画布播放头;点击时间线 → `player.seek`。

---

## 5. 资源管理器 + 媒体导入

**素材库 = 引用表**:
```swift
struct Asset {
    let id: AssetID
    var url: URL          // 只引用源文件, 不拷贝/不转码
    var kind: MediaKind   // video/audio/image
    var duration: Time    // 图片为约定时长(如 5s)
    var naturalSize: CGSize
    var frameRate: Double?
    var hasAudio: Bool
}
```
只引用源文件(像 FCPX"留在原位");删被引用素材先警告。

**v1 输入格式白名单**(AVFoundation 原生):`.mov/.mp4/.m4v`(H.264/HEVC/ProRes)、`.wav/.mp3/.m4a/.aac`、`.png/.jpg/.heic`。非原生(VP9/MKV/AVI)v1 不碰。

**导入流程** `Engine/Media/MediaImporter`:
1. 拖入/菜单导入 → 校验 UTType;不支持**立即明确报错**(fail fast,不静默跳过)。
2. `AVAsset` 异步读时长/尺寸/帧率/音轨。
3. `AVAssetImageGenerator` 抽首帧缩略图(异步 + 缓存,沿用 feishu `AvatarCache` 思路)。
4. 入库,Browser 刷新。

**UI**(SwiftUI,贴 style.md):Libraries 侧栏(两级:库/项目+片段,智能精选先桩)→ Browser 缩略图网格(分组标题、16:9 卡片、选中黄框 `#FFD754`、可拖出携带 AssetID)→ 底部状态条(已选 N/总时长)。

**v1 砍掉**:列表/胶片双视图、skimming、关键词/评分、智能精选逻辑(位置留)。

---

## 6. UI 外壳布局(定稿)

参考截图 `design/fcpx_ui.jpg`,配色全部用 `design/style.md` 实采 Token(视图只引 Token、不写裸 hex)。

**结构:**
```
┌─────────────────────────────────────────────────────────────┐
│ 顶部状态栏(通栏): 红绿灯 · 项目名 · [Inspector开关⌘4] · ...     │  ← 全窗通栏
├──────────────────────────────────────────────┬──────────────┤
│ 左 = 完整 FCPX 工作区                           │ 右 = Chat     │
│  ├ 格式工具栏(所有片段/格式/适合/显示)          │   Panel       │
│  ├ 主区: 边栏 | 资源管理器 | 预览 |(Inspector)  │  (整窗高,    │
│  ├ 时间线工具栏(... · [效果开关⌘5][转场⌃⌘5])    │   固定最右,   │
│  └ 磁性时间线(标尺 + 主轴 + lane +(效果面板))   │   v1 空占位)  │
└──────────────────────────────────────────────┴──────────────┘
```

**折叠逻辑(严格复刻 FCPX,经截图核对):**
- **Inspector**:默认**完全隐藏**;靠顶部状态栏最右的**三滑块按钮(⌘4)**显隐;出现时在预览右侧,**只在左工作区内部,不挤占 Chat**。
- **效果面板**:默认**完全隐藏**;靠**时间线工具栏右上角的两叠放矩形按钮(⌘5)**显隐(旁转场 ⌃⌘5);出现时在时间线右侧。
- **不发明窄条/竖排折叠条**——折叠就是消失,按钮控制显隐。

**Chat Panel**:整窗高(顶端与左工作区对齐,贯穿到底),固定最右第五列;v1 空占位(标题 + 占位对话气泡 + 输入框,不接逻辑)。

**度量**(详见 style.md):Libraries 200pt | Browser ~280pt | Viewer 弹性 | Inspector 320pt(显示时)| Chat 默认 ~320pt;时间线区 Effects 360pt(显示时);各分隔可拖拽,带最小宽约束。

---

## 7. 错误处理与测试

**错误处理(fail fast,dev 阶段不写兜底):**
- 不支持格式导入 → 立即明确报错,不静默跳过。
- asset 丢失/无法解码 → clip 标红 + 明确提示,不静默播黑场。
- 命令层每次 mutation 后断言三条磁性不变量(debug `assert`),违反即崩,早暴露。
- AVFoundation 异步失败走 `Result`/`throws` 显式上抛 UI,不吞异常。
- 调试期保留 try/except 让异常 raise,看到真实错误后再精简。

**测试分层:**
- **磁性引擎**:唯一高覆盖单测模块,表驱动 + 属性测试,每步断言三不变量。
- **CompositionBuilder**:纯函数,断言生成轨道数/时段/instruction 数。
- **FCPXML 导出器**:往返(文档→fcpxml→真 FCPX 打开 spot check)+ 结构快照。
- **UI/预览**:v1 不自动化,用户手动跑 `.app` 验证(app 由用户启停)。
- 沿用 feishu `Tests/` + SwiftPM testTarget。

---

## 8. 调试方法论:控制变量对照实验(一等要求)

> 适用全程,尤其磁性引擎——这类"逻辑绕、肉眼难判对错"的模块,盯 UI 看不出对错,**必须用控制变量的对照实验 + 可导出数据来证明代码 working、定位 bug 根因**。杜绝猜测,批量实验,数据驱动,CV/断言优先而非人工肉眼。

**铁律:**
1. **杜绝猜测,变量参数化**:面对参数(如吸附阈值 0.02 vs 0.04)或流程顺序(先 A 还是先 B)的不确定,不靠感觉改完等人工验证——把变量做成可配置参数,批量跑。
2. **网格实验,对比数据**:一次跑遍所有组合(阈值 0.01~0.09、顺序 ABC/BCA/CBA…),生成多组结果。
3. **自动分析,找梯度**:用断言/CV/数值对比(而非肉眼或 VLM)看指标随参数的变化趋势(变大/变小/不变),据此判断参数是否有效、影响方向,定位 bug。

**落到磁性引擎的具体实验设计(实现期必须产出):**

引擎是 `[Element]→[Element]` 纯函数,可程序化跑实验、导出结果数据(JSON/CSV),自动断言而非肉眼。

- **A/B 对照(加 vs 不加)**:同一组素材,操作序列相同,唯一区别是"是否启用某规则/参数"(如吸附 on/off、ripple vs lift),对比两次输出的 `[absStart, duration, lane]` 表,差异必须可解释。
- **顺序对照(ABC vs BCA vs CBA)**:同一批操作的不同执行顺序,断言最终文档状态的等价性/差异性是否符合预期(如"插入后删除" vs "删除后插入"应得不同但可预测的结果)。
- **参数扫描(1,2,…,10)**:把吸附阈值、lane 间距等做成参数,从小到大扫一遍,记录输出指标(如吸附命中次数、clip 最终位置),验证单调性/拐点是否符合直觉——突变点往往就是 bug。
- **多维矩阵跑素材**:一组素材在**不同位置 × 不同类型(视频/音频/图片)× 不同轨道(主轴/上 lane/下 lane)**全跑一遍,对每个组合断言三条不变量 + 导出位置表,找规律定位 bug 由哪个维度引起。
- **可重现 + 可导出**:每个实验固定随机种子,结果导出成数据文件,失败用例能最小化复现并回归。

这套实验框架本身作为 `Tests/` 的一部分实现(可命令行批量跑、输出对照表),是证明磁性引擎正确性的主要手段,优先级高于 UI 手测。

---

## 9. 未来里程碑(非本次范围,仅记录方向)

- **M2 Agent 接入**:把命令层包装成工具 schema 暴露给 Agent;Chat 面板接对话与工具调用;人机结合编辑。
- **M3 特效/转场**:换 `AVVideoCompositing` 自研 Metal 合成器,实现特效/转场。
- **M4 导出渲染**:`AVAssetExportSession` 编码成片。
- 高级 trim(roll/slip/slide)、媒体管理、关键帧动画等。

---

## 附:里程碑 1 实现顺序(可独立验证的小阶段)

| 阶段 | 内容 | 验证 |
|------|------|------|
| M1.0 脚手架 | SwiftPM 包、AppKit 入口、Tokens(落 style.md)、空五区外壳 | app 起,五区骨架+配色对 |
| M1.1 文档模型 | Time/Asset/Clip/Spine/Document + DocumentStore | 单测:构造/序列化 |
| M1.2 磁性引擎 | layout + 全 mutation + snapping(纯逻辑)+ 第 8 节实验框架 | 属性测试:三不变量恒成立;对照实验通过 |
| M1.3 资源管理器 | 媒体导入、缩略图缓存、Browser、可拖出 | 导入素材,缩略图显示 |
| M1.4 时间线画布 | AppKit 自绘 clip/lane/标尺/播放头 + 拖拽/trim/blade + 吸附,接命令层 | 手动拖入/移动/裁剪/切割,磁吸生效 |
| M1.5 预览引擎 | CompositionBuilder + PreviewController + AVPlayerLayer,commit 后重建 | 拼接结果能预览播放 |
| M1.6 Inspector 基础 | 变换/裁切/不透明度/音量,⌘4 开关 | 改参数预览实时反映 |
| M1.7 串联打磨 | 五区联动、效果留位 + ⌘5 开关、Chat 空占位、FCPXML 导出器 | 端到端:导入→剪→预览→导出 fcpxml |
