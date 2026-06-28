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
    var effects: [Effect]
    var enabled: Bool          // 停用(V 键)→ 不参与预览/导出,时间线上变暗

    init(id: ClipID = ClipID(), assetID: AssetID, sourceIn: Time, duration: Time,
         connected: [Clip] = [], lane: Int = 0, offset: Time = .zero,
         adjust: Adjustments = Adjustments(), effects: [Effect] = [], enabled: Bool = true) {
        self.id = id; self.assetID = assetID
        self.sourceIn = sourceIn; self.duration = duration
        self.connected = connected; self.lane = lane
        self.offset = offset; self.adjust = adjust; self.effects = effects; self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, assetID, sourceIn, duration, connected, lane, offset, adjust, effects, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ClipID.self, forKey: .id)
        assetID = try c.decode(AssetID.self, forKey: .assetID)
        sourceIn = try c.decode(Time.self, forKey: .sourceIn)
        duration = try c.decode(Time.self, forKey: .duration)
        connected = try c.decode([Clip].self, forKey: .connected)
        lane = try c.decode(Int.self, forKey: .lane)
        offset = try c.decode(Time.self, forKey: .offset)
        adjust = try c.decode(Adjustments.self, forKey: .adjust)
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []   // 旧 JSON 缺字段 → []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true      // 旧 JSON 缺字段 → 启用
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(sourceIn, forKey: .sourceIn)
        try c.encode(duration, forKey: .duration)
        try c.encode(connected, forKey: .connected)
        try c.encode(lane, forKey: .lane)
        try c.encode(offset, forKey: .offset)
        try c.encode(adjust, forKey: .adjust)
        try c.encode(effects, forKey: .effects)
        try c.encode(enabled, forKey: .enabled)
    }
}
