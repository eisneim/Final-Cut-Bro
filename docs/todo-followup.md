# FCPX-lite 待办清单(2026-06-29)

> 来源:对照设计文档 DoD + 代码 TODO + 测试覆盖盘点。按优先级分组,逐项做 + 端到端验证。
> 纪律:每项做完 build 绿 + 单测 + 可见处端到端(harness 驱动/截图)验证;server 用户启停,测完即止。

## P0 — 核心编辑语义缺失(影响"能不能正常剪")

- [ ] **T1 真覆盖(Overwrite / D 键)** — 现在 `overwriteAtPlayhead` 只当插入。实现真覆盖:在播放头处用所选素材覆盖目标区间(裁掉/分割被覆盖的片段),不改总时长。`Mutations.overwrite` + 单测(覆盖中段/跨片段/超尾)。
- [ ] **T2 时间轴交互纯逻辑单测** — 给 VolumeDrag/GapDrag/roll 的命中与几何补单测(关键帧 time↔x、yToVolume、roll clamp、gap 边缘命中、fade 秒数换算)。把"逻辑绕、肉眼难判"的部分用对照断言锁住。
- [ ] **T3 图片/静帧进合成** — `CompositionBuilder` 当前跳过 image。让图片素材作为静帧视频层参与预览/导出(用 CIImage/纯色层或 AVVideoComposition 静帧)。单测:图片 clip → item 非 nil + 有视频段。

## P1 — 常用功能补全

- [ ] **T4 项目删除 / 重命名** — ProjectBar 卡片右键或按钮:删项目(至少留 1 个或允许回到无项目门控)、双击改名。EditorAction `removeProject`/`renameProject` + dispatch + 单测。
- [ ] **T5 transform 关键帧动画** — 给 clip 的位移/缩放/不透明度支持关键帧(对齐音量关键帧模型)。模型 `transformKeyframes` + 合成器按时间插值(CoreImageCompositor 按 request time 求值)。先做位移+缩放,单测插值。
- [ ] **T6 时间轴 clip 复制/粘贴** — ⌘C/⌘V 对选中片段(主轴/连接)复制到播放头。store 剪贴板 + 单测。

## P2 — 端到端验证(需用户启动 server)

- [ ] **T7 Agent 20 条逐动作冒烟回填** — 启动 debug server,逐条真 LLM agentSend 跑 `docs/agent-e2e-checklist.md` 步骤 A,回填 ✅/❌。
- [ ] **T8 Agent 真实工作流(深度)** — 导入音乐+视频→拼→连接背景乐→压原声→切删→导出,一句话端到端,验证多步连贯 + 产物。
- [ ] **T9 导出矩阵验证** — H.264/H.265/ProRes × 720/1080 × 低/中/高,真实编码产物可读 + 编码/尺寸正确(CV 或 ffprobe 校验)。

## P3 — 打磨(低优先)

- [x] **T10 slip / slide 高级 trim** — slip(改入出点不改位置时长)、slide(移片段并调两侧)。✅ Mutations+catalog+8测试(aae6317)
- [x] **T11 转场(crossfade)** — 两相邻片段间叠化转场。✅ Clip.crossfadeIn重叠+合成器逐帧opacity斜坡+7测试含渲染混合(974de24)
- [x] **T12 效果/转场面板内容** — ⌘5 面板从占位变成可点击的特效/转场库。✅ EffectsPanel点击应用到选中片段+6测试(19c5f63)

---

## 进度
(逐项完成后在此记录 commit + 验证结果)

- ✅ **T1** 真覆盖(Overwrite/D)— `Mutations.overwrite` + 5 测试。
- ✅ **T2** 时间轴交互纯逻辑单测 — VolumeLineMath/几何 6 测试。
- ✅ **T3** 图片进合成 — CGImage 静帧层 + 纯图时间线用 1 帧 blank 视频 scaleTimeRange 撑时长;端到端渲染验证(commit 6ef5719)。
- ✅ **T4** 项目删除/重命名 — removeProject/renameProject + ProjectBar 右键+双击 + 7 测试(commit bd765f1)。
- ✅ **T5** transform 关键帧 — TransformKeyframe 模型 + 合成器按 request time 插值(containsTweening)+ inspector 加关键帧按钮 + 18 测试(含不透明度动画端到端渲染)(commit 052d6dc)。
- ✅ **T6** clip 复制/粘贴 ⌘C/⌘V — 深拷贝换新 id 粘贴到播放头最近编辑点 + 7 测试(commit c5d42af)。
- 🔸 额外:左侧栏整体滚动 + PNG 保留 alpha(commit 5c9d07d)。
- ⏳ **T7/T8** 需用户启动 server + 配置真实 LLkey,无法自动跑。
- ✅ **T9** 导出矩阵 — 编码 FourCC(avc1/hvc1/apcn)×分辨率(720/1080)正确 + 质量档码率绑定(高熵噪声内容)+ 码率单调性单测(commit 508b89f)。

### T7/T8 用户自跑手册(我已验证可自动化的部分)
