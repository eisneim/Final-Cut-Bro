import Foundation

/// 瞬时 UI 状态 —— 也放进 store(Redux 纪律:零本地 state)。
/// Codable 以便测试注入完整场景快照。
struct UIState: Codable, Equatable {
    var showInspector: Bool = false
    var showEffects: Bool = false
    var selectedClipID: ClipID? = nil
    var currentTool: EditTool = .select
    var pxPerSecond: Double = 60
    var playhead: Time = .zero
    var timelineFraction: Double = 0.5   // 时间轴占【预览+时间轴】可用高度的比例(窗口缩放时两者联动)
    var selectedAssetID: AssetID? = nil
    var isPlaying: Bool = false
    var snappingEnabled: Bool = true
    var sidebarWidth: Double = 120
    var browserWidth: Double = 280
    var inspectorWidth: Double = 320
    var chatWidth: Double = 320
    var clipHeight: Double = 72
    var videoAudioRatio: Double = 0.6
    var agentInput: String = ""
    var providerId: String = "stepfun"
    var showSettings: Bool = false
    var showExport: Bool = false
    var exportProgress: Double? = nil    // nil=未导出;0–1=进行中
}
