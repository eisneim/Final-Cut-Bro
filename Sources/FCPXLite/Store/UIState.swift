import Foundation

/// 瞬时 UI 状态 —— 也放进 store(Redux 纪律:零本地 state)。
/// Codable 以便测试注入完整场景快照。
struct UIState: Codable, Equatable {
    var showInspector = false
    var showEffects = false
}
