import Foundation

/// 时间线片段。引用 asset,自己只存 in/out。
/// connected/lane/offset 仅用于连接片段(L2/L3);spine 上的 clip lane 恒为 0。
struct Clip: Identifiable, Codable, Equatable {
    let id: ClipID
    var assetID: AssetID
    var sourceIn: Time
    var duration: Time
    var connected: [Clip]
    var lane: Int
    var offset: Time          // 相对【宿主 clip 起点】
    var adjust: Adjustments

    init(id: ClipID = ClipID(), assetID: AssetID, sourceIn: Time, duration: Time,
         connected: [Clip] = [], lane: Int = 0, offset: Time = .zero,
         adjust: Adjustments = Adjustments()) {
        self.id = id; self.assetID = assetID
        self.sourceIn = sourceIn; self.duration = duration
        self.connected = connected; self.lane = lane
        self.offset = offset; self.adjust = adjust
    }
}
