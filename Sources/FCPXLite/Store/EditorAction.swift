import Foundation

/// 可序列化的编辑动作 —— 命令层的"数据化"表示。
/// 手动 UI 与未来 Agent 工具都构造同一个 EditorAction 并 dispatch;
/// 因为 Codable,Agent 可直接发 JSON 驱动整个编辑器,也便于日志/重放/撤销。
enum EditorAction: Codable, Equatable {
    case insertClip(Clip, at: Int)
    case overwrite(Clip, atTime: Time)
    case rippleDelete(at: Int)
    case liftDelete(at: Int)
    case moveClip(from: Int, to: Int)
    case trimRight(at: Int, newDuration: Time, assetDuration: Time)
    case trimLeft(at: Int, deltaIn: Time)
    case blade(at: Int, localTime: Time)
    case removeConnected(ClipID)
    case bladeConnected(ClipID, localTime: Time)
    case connect(Clip, host: Int, lane: Int, offset: Time)
    case relocateClip(ClipID, lane: Int, time: Time)
    case positionMove(ClipID, time: Time)
    case positionMoveToLane(ClipID, lane: Int, time: Time)
    case setGapDuration(at: Int, duration: Time)
    case setInspector(Bool)
    case setShowEffects(Bool)
    case setShowExport(Bool)
    case createProject(Project)
    case selectProject(ProjectID)
    case removeProject(ProjectID)
    case renameProject(ProjectID, String)
    case setShowProjectModal(Bool)
    case importAsset(Asset)
    case selectClip(ClipID?)
    case selectGap(GapID?)
    case setGapDurationByID(GapID, Time)
    case moveGap(GapID, time: Time)
    case removeGap(GapID)
    case setTool(EditTool)
    case setZoom(Double)
    case setPlayhead(Time)
    case setTimelineFraction(Double)
    case selectAsset(AssetID?)
    case toggleAssetSelected(AssetID)   // ⌘-click:加入/移出多选集
    case selectAssetRange(AssetID)       // ⇧-click:从 anchor 到此 inclusive 区间选中
    case selectAllAssets                 // ⌘A:选中素材库全部
    case clearAssetSelection             // 清除多选
    case setPlaying(Bool)
    case togglePlay
    case toggleSnapping
    case setPanelWidth(PanelKind, Double)
    case setClipHeight(Double)
    case setVideoAudioRatio(Double)
    case setAssetStripZoom(Double)
    case setAdjust(ClipID, Adjustments)
    case setEffects(ClipID, [Effect])
    case setVolumeKeyframes(ClipID, [VolumeKeyframe])
    case setTransformKeyframes(ClipID, [TransformKeyframe])
    case slip(at: Int, delta: Time, assetDuration: Time)
    case slide(at: Int, delta: Time, prevAssetDuration: Time, nextAssetDuration: Time)
    case setCrossfade(at: Int, duration: Time)
    case selectTransition(ClipID?)
    case setEnabled(ClipID, Bool)
}

/// 可调宽度的面板。
enum PanelKind: String, Codable {
    case sidebar, browser, inspector, chat
}
