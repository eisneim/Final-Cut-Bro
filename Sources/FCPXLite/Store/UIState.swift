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
    var timelineHeight: Double = 220
    var selectedAssetID: AssetID? = nil
}
