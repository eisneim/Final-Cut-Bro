import Foundation

/// Inspector 当前聚焦的对象类型 —— 跟随【最后一次选择】的对象(FCP 行为:
/// 点素材→显素材信息,点时间轴片段→显片段编辑项,点/建项目→显项目信息)。
enum InspectorFocus: String, Codable {
    case none, project, asset, clip
}

/// 瞬时 UI 状态 —— 也放进 store(Redux 纪律:零本地 state)。
/// Codable 以便测试注入完整场景快照。
struct UIState: Codable, Equatable {
    var showInspector: Bool = false
    var showEffects: Bool = false
    var showBrowser: Bool = true    // 素材库(左)显隐,顶栏按钮切换
    var showChat: Bool = true       // Agent 面板(右)显隐,顶栏按钮切换
    var selectedClipID: ClipID? = nil
    var selectedClipIDs: Set<ClipID> = []   // 框选多选集合;selectedClipID 作为 anchor(inspector 取值显示)
    var inspectorFocus: InspectorFocus = .none   // Inspector 显示哪类对象(跟随最后选择)
    var selectedGapID: GapID? = nil      // 选中的空隙(gap 可像 clip 一样选中/修剪/拖动/删除)
    var selectedTransitionClipID: ClipID? = nil   // 选中的转场(归属于带 crossfadeIn 的那个片段)
    var currentTool: EditTool = .select
    var pxPerSecond: Double = 60
    var playhead: Time = .zero
    var timelineFraction: Double = 0.5   // 时间轴占【预览+时间轴】可用高度的比例(窗口缩放时两者联动)
    var selectedAssetID: AssetID? = nil
    var selectedAssetIDs: Set<AssetID> = []   // 多选集合;selectedAssetID 作为 anchor
    var isPlaying: Bool = false
    var snappingEnabled: Bool = true
    var sidebarWidth: Double = 120
    var browserWidth: Double = 280
    var inspectorWidth: Double = 320
    var chatWidth: Double = 320
    var effectsWidth: Double = 288   // 效果/转场面板宽(默认比原 360 窄 20%);可拖拽调整
    var clipHeight: Double = 72
    var videoAudioRatio: Double = 0.6
    var assetStripZoom: Double = 6   // 素材池 strip 外观缩放(px/秒);小=网格小方块,大=长胶片条
    // Skimming:鼠标在素材池某素材上划过时,viewer 显示该素材在 skimSeconds 处的帧(不动播放器,纯覆盖层)。
    var skimAssetID: AssetID? = nil
    var skimSeconds: Double = 0
    // 主时间轴 skimming(FCP 逻辑):开启后鼠标在时间轴上划过 → skimmer 竖线跟随光标 +
    // 预览显示该时间点的【合成帧】(不移动播放头)。timelineSkimSeconds=nil 表示当前未在时间轴上划过。
    var timelineSkimming: Bool = false
    var timelineSkimSeconds: Double? = nil
    var agentInput: String = ""
    var providerId: String = "stepfun"
    var showSettings: Bool = false
    var showExport: Bool = false
    var showProjectModal: Bool = false   // 创建项目弹窗
    var exportProgress: Double? = nil    // nil=未导出;0–1=进行中
    var exportError: String? = nil       // 最近一次导出失败的原因(nil=无错)
}
