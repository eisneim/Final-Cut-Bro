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
    var volumeKeyframes: [VolumeKeyframe]
    var transformKeyframes: [TransformKeyframe]
    var crossfadeIn: Time      // >0 = 与【前一个主轴片段】交叉叠化(dissolve)的时长,本片段头部与前片段尾部重叠
    var title: TitleSpec?      // 非 nil = 标题片段(渲染文字,不引用真实媒体)
    var enabled: Bool          // 停用(V 键)→ 不参与预览/导出,时间线上变暗

    init(id: ClipID = ClipID(), assetID: AssetID, sourceIn: Time, duration: Time,
         connected: [Clip] = [], lane: Int = 0, offset: Time = .zero,
         adjust: Adjustments = Adjustments(), effects: [Effect] = [],
         volumeKeyframes: [VolumeKeyframe] = [], transformKeyframes: [TransformKeyframe] = [],
         crossfadeIn: Time = .zero, title: TitleSpec? = nil, enabled: Bool = true) {
        self.id = id; self.assetID = assetID
        self.sourceIn = sourceIn; self.duration = duration
        self.connected = connected; self.lane = lane
        self.offset = offset; self.adjust = adjust; self.effects = effects
        self.volumeKeyframes = volumeKeyframes; self.transformKeyframes = transformKeyframes
        self.crossfadeIn = crossfadeIn; self.title = title; self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, assetID, sourceIn, duration, connected, lane, offset, adjust, effects, volumeKeyframes, transformKeyframes, crossfadeIn, title, enabled
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
        volumeKeyframes = try c.decodeIfPresent([VolumeKeyframe].self, forKey: .volumeKeyframes) ?? []
        transformKeyframes = try c.decodeIfPresent([TransformKeyframe].self, forKey: .transformKeyframes) ?? []
        crossfadeIn = try c.decodeIfPresent(Time.self, forKey: .crossfadeIn) ?? .zero
        title = try c.decodeIfPresent(TitleSpec.self, forKey: .title)
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
        try c.encode(volumeKeyframes, forKey: .volumeKeyframes)
        try c.encode(transformKeyframes, forKey: .transformKeyframes)
        try c.encode(crossfadeIn, forKey: .crossfadeIn)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(enabled, forKey: .enabled)
    }

    /// 是否标题片段(渲染文字、无真实媒体)。
    var isTitle: Bool { title != nil }

    /// 深拷贝并给自身+所有连接子项换新 ClipID(用于复制/粘贴,避免 id 撞车)。
    /// 保留全部参数(adjust/effects/关键帧),只换 id。
    func duplicatedWithNewIDs() -> Clip {
        Clip(id: ClipID(), assetID: assetID, sourceIn: sourceIn, duration: duration,
             connected: connected.map { $0.duplicatedWithNewIDs() },
             lane: lane, offset: offset, adjust: adjust, effects: effects,
             volumeKeyframes: volumeKeyframes, transformKeyframes: transformKeyframes,
             crossfadeIn: crossfadeIn, title: title, enabled: enabled)
    }
}
