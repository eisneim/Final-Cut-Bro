import Foundation

/// 瞬时 UI 状态 —— 也放进 store(Redux 纪律:零本地 state)。
/// Codable 以便测试注入完整场景快照。
struct UIState: Codable, Equatable {
    var showInspector: Bool = false
    var showEffects: Bool = false
    var selectedClipID: ClipID? = nil
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
    var agentInput: String = ""
    var providerId: String = "stepfun"
    var showSettings: Bool = false
    var showExport: Bool = false
    var showProjectModal: Bool = false   // 创建项目弹窗
    var exportProgress: Double? = nil    // nil=未导出;0–1=进行中
    var exportError: String? = nil       // 最近一次导出失败的原因(nil=无错)
}
