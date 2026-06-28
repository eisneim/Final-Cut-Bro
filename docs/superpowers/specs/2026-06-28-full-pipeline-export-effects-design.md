# FCPX-lite 完整剪辑→导出链路 + 特效系统 + 100+ 端到端测试

日期:2026-06-28
分支:feat/agent-integration(后续可能开新分支)
状态:设计

## 0. 目标与完成定义

把 FCPX-lite 从"能剪能预览"推进到**完整产品链路**:导入 → 编辑(增删/裁剪/调序/多轨)→ 加音乐+调音量 → Inspector 调参 → **加特效(视频+音频)** → **导出(fcpxml 工程 + mp4 成片)**。手动链路与 **Agent 对话链路**都要能走完整条路。

**完成定义(三条全满足):**
1. 链路全部走通:手动 + Agent 都能从导入做到导出。
2. 产品文档(里程碑1 DoD)要求全部完成——含此前**从未落地的 fcpxml 导出**。
3. 端到端测试 ≥ 100 条(分层:单元 + harness 断言 + 少量真 LLM)。

**非目标(YAGNI):** 转场、字幕、关键帧动画、调色曲线/LUT、多特效预设库。特效只填充少量(调色+模糊+淡入淡出)以证明系统完整可扩展。

## 1. 现状盘点(brainstorm 探明)

- ✅ 磁性时间线引擎、预览合成、Inspector 调参、Agent 4-工具 dispatch(22 动作)、波形/缩略图 — 已就位。
- ❌ **fcpxml 导出**:文档 L21 标"✅"但 `Sources` 无 Export 目录、无导出代码 — **从未实现**。
- ❌ **mp4 渲染导出**:无 `AVAssetExportSession`。
- ❌ **特效**:模型无 `effects` 字段,合成器无滤镜,Inspector 无特效区,Agent 无特效动作。
- ⚠️ Agent 选择问题:实测 `position_move`/`set_gap` 被 LLM 误选成 blade(需改进 description/语义)。

## 2. 五个子系统(按依赖排序)

### ① 特效系统(最大、最高风险)

**模型**(`Models/Effect.swift`,新增):
```swift
enum EffectKind: String, Codable, CaseIterable {
    case color   // 视频:亮度/对比度/饱和度 (CIColorControls)
    case blur    // 视频:高斯模糊 (CIGaussianBlur)
    case fade    // 音频:淡入淡出 (AVAudioMix 音量斜坡)
}
struct Effect: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: EffectKind
    var enabled: Bool = true
    var params: [String: Double] = [:]   // 扁平参数袋:color→brightness/contrast/saturation; blur→radius; fade→inSeconds/outSeconds
}
```
挂载点:`Clip.effects: [Effect] = []`(主轴与连接子项均可)。列表顺序 = 视频滤镜链应用顺序。

**视频特效合成架构决策(关键)**:
当前 `CompositionBuilder` 用 `AVMutableVideoCompositionInstruction + layerInstructions` 做 transform/crop/opacity/多轨 z-order。Core Image 滤镜**无法**用 layerInstruction 表达。要支持 per-clip 视频特效 + 多轨,**必须自研 `AVVideoCompositing` 自定义合成器**(`Engine/Composition/CoreImageCompositor.swift`),用 Core Image 统一处理:对每个活跃源轨,按 z-order(lane)依次:套 preferred→fit→crop→transform→opacity→effects 滤镜链,合成到 renderSize。
- 这替换掉现有 layerInstruction 路径(transform/crop/opacity 改由 Core Image 矩阵/滤镜实现,几何公式复用 `fullTransform` 的数学)。
- **风险**:自定义合成器是本次最大改动;若实现受阻,**降级方案**=视频特效仅作用于主轴(单层),多轨仍走旧 layerInstruction(特效不叠加在连接片段上)。降级仍满足"系统完整"的演示需求。

**音频特效**:`fade` 通过 `AVMutableAudioMixInputParameters.setVolumeRamp(fromStartVolume:toEndVolume:timeRange:)` 实现淡入淡出,叠加在现有逐 clip 音量之上。无需自定义。

**Inspector 特效区**(`Views/InspectorView.swift` 扩展或新 `InspectorEffectsSection.swift`):选中 clip 显示 effects 列表,可 ➕加(选 kind)/🗑删/☑启停/调参(slider)。走命令层 `setEffects` action(可撤销)。

### ② 导出 fcpxml(A,纯逻辑)

`Export/FCPXMLExporter.swift`(新增):`static func export(_ document: Document) -> String`。
- 递归遍历 spine:`Clip→<asset-clip>` / `Gap→<gap>` / 连接片段→嵌套带 `lane`/`offset`。
- `Adjustments→<adjust-transform>/<adjust-crop>/<conform-rate>` 等;`effects→<filter-video>/<filter-audio>`(用通用 effect 名,真 FCP 不识别自定义 effect 时降级为注释或跳过——以"结构合法可打开"为准)。
- `Asset→<asset>/<format>` 资源声明 + `<resources>` 段。
- 输出符合 FCPXML DTD 的字符串。验证:结构快照测试 + 往返(导出文件用真 FCPX spot-check 打开)。

### ③ 导出渲染 mp4/m4a(B)

`Export/MovieExporter.swift`(新增):`func export(document:, to url:, progress:, completion:)`。
- 复用 `CompositionBuilder.build` 产出的 `AVComposition + videoComposition + audioMix`。
- `AVAssetExportSession(asset:presetName:)`,有视频→`.mp4`(H.264,`AVAssetExportPresetHighestQuality`);纯音频→`.m4a`(`AVAssetExportPresetAppleM4A`)。
- 进度轮询 `session.progress` → UI 进度条;`completion` 处理成功/失败/取消。
- Edge:空时间线→禁用导出按钮;路径不可写→错误提示;导出中可取消。

### ④ Agent 全链路

新增 dispatch 动作(catalog):
- `clip_adjust` 域:`add_effect(clipIndex, kind)`、`remove_effect(clipIndex, effectIndex)`、`set_effect_param(clipIndex, effectIndex, key, value)`、`toggle_effect(clipIndex, effectIndex, enabled)`。
- 新 `export` 工具(第 5 个工具)或归入 navigate:`export_fcpxml(path)`、`export_movie(path)`。导出是异步,动作返回"导出已开始/已完成"。
- **修选择问题**:`position_move`/`set_gap` 的 `doc` 增加判别提示(如 position_move:"移动并在原位留占位间隙,与 blade 切割不同");必要时给 `set_gap` 增加"仅当已存在间隙时"前置说明。

### ⑤ 100+ 端到端测试

见 §4。

## 3. 文件改动总览

| 文件 | 改动 |
|------|------|
| `Models/Effect.swift` | 新增:EffectKind/Effect |
| `Models/Clip.swift` | 加 `effects: [Effect]` + Codable 迁移 |
| `Engine/Composition/CoreImageCompositor.swift` | 新增:AVVideoCompositing 自定义合成器(transform/crop/opacity/z-order/CIFilter) |
| `Engine/Composition/CompositionBuilder.swift` | 改:挂自定义 compositor;音频 fade ramp |
| `Export/FCPXMLExporter.swift` | 新增:Document→fcpxml |
| `Export/MovieExporter.swift` | 新增:AVAssetExportSession 渲染 |
| `Views/InspectorView.swift`(+特效子视图) | 特效列表 UI |
| `Views/ExportPanel.swift` | 新增:导出对话框(格式/路径/进度) |
| `Store/EditorAction.swift` | 加 `setEffects(ClipID, [Effect])` |
| `Agent/AgentActionCatalog.swift` | 加 effect/export 动作 + 修 position_move/set_gap doc |
| `Agent/AgentToolRegistry.swift` | export 工具/归类 |
| `DebugControlServer.swift` | 加 export/effect 自测 op |
| `Tests/...` | 新增大量单元 + harness 测试 |

## 4. 测试计划(≥100 条)

| 类型 | 驱动 | 量 |
|------|------|----|
| Effect 模型(Codable 往返/参数边界/启停) | XCTest | ~12 |
| CoreImageCompositor 几何(复用 fullTransform 断言 + 滤镜应用) | XCTest | ~10 |
| FCPXMLExporter 结构(各元素映射/嵌套 lane/effects/往返解析) | XCTest 快照 | ~15 |
| MovieExporter(空时间线拒绝/纯音频→m4a/有视频→mp4/产物可读时长) | XCTest(短合成) | ~8 |
| Catalog 翻译(新 effect/export 动作 + 全 27 动作 index→内部) | XCTest | ~30 |
| Edge cases(§列表:越界/空/参数极值/重锚/换音乐/淡入超长) | XCTest+harness | ~25 |
| Agent 真 LLM 关键链路(全链路一句话/换音乐/加特效+导出/越界自纠) | agentSend | ~10 |
| **合计** | | **110+** |

纪律:绝大多数确定性快测试;真 LLM 仅关键链路。server 永远用户启停,测完即止。

## 5. 实现顺序(每块可独立验证)

1. **特效模型 + Clip.effects**(纯模型,Codable 迁移,测试)
2. **CoreImageCompositor**(自定义合成器,先实现 transform/crop/opacity/z-order 等价旧行为 → 回归;再加 CIFilter)
3. **音频 fade**(AVAudioMix ramp)
4. **Inspector 特效区**(手动可加特效看预览)
5. **FCPXMLExporter**(导出工程文件 + 往返)
6. **MovieExporter**(渲染成片 + 进度)
7. **ExportPanel UI**(手动导出)
8. **Agent effect/export 动作 + 修选择问题**
9. **100+ 测试补齐 + 真 LLM 链路验证**

## 6. 风险

- **CoreImageCompositor 是最大风险**:自定义合成器要正确处理多轨 z-order + 每层滤镜 + 性能。降级方案=单层特效(已述)。先做"等价替换旧行为"的回归,确保不破坏现有预览,再加滤镜。
- **fcpxml 往返**:真 FCP 对自定义 effect 不识别 → 以"结构合法能打开+基础剪辑信息正确"为验收线,effect 映射尽力而为。
- **真 LLM 测试不稳/慢**:限制在 ~10 条关键链路,其余确定性测试兜底。
- **mp4 编码耗时**:测试用短合成(2-3s),避免 CI 超时。
