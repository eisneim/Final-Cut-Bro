import Foundation

/// 可序列化的编辑动作 —— 命令层的"数据化"表示。
/// 手动 UI 与未来 Agent 工具都构造同一个 EditorAction 并 dispatch;
/// 因为 Codable,Agent 可直接发 JSON 驱动整个编辑器,也便于日志/重放/撤销。
enum EditorAction: Codable, Equatable {
    case insertClip(Clip, at: Int)
    case rippleDelete(at: Int)
    case liftDelete(at: Int)
    case moveClip(from: Int, to: Int)
    case trimRight(at: Int, newDuration: Time, assetDuration: Time)
    case trimLeft(at: Int, deltaIn: Time)
    case blade(at: Int, localTime: Time)
    case connect(Clip, host: Int, lane: Int, offset: Time)
    case relocateClip(ClipID, lane: Int, time: Time)
    case positionMove(ClipID, time: Time)
    case setGapDuration(at: Int, duration: Time)
    case setInspector(Bool)
    case setEffects(Bool)
    case importAsset(Asset)
    case selectClip(ClipID?)
    case setTool(EditTool)
    case setZoom(Double)
    case setPlayhead(Time)
    case setTimelineHeight(Double)
    case selectAsset(AssetID?)
    case setPlaying(Bool)
    case togglePlay
    case toggleSnapping
    case setPanelWidth(PanelKind, Double)
}

/// 可调宽度的面板。
enum PanelKind: String, Codable {
    case sidebar, browser, inspector, chat
}
