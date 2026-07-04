import Foundation

extension Mutations {
    private static func mutatingClip(_ id: ClipID, in seq: Sequence,
                                     _ f: (_ clip: inout Clip, _ isConnected: Bool) -> Void) -> Sequence {
        var s = seq
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var c) = el else { continue }
            if c.id == id { f(&c, false); s.spine[i] = .clip(c); return s }
            if let j = c.connected.firstIndex(where: { $0.id == id }) {
                f(&c.connected[j], true); s.spine[i] = .clip(c); return s
            }
        }
        return s
    }

    /// 设置某 clip(主轴或连接子项)的 Adjustments(inspector 调参)。
    static func setAdjust(clipID: ClipID, _ adjust: Adjustments, in seq: Sequence) -> Sequence {
        mutatingClip(clipID, in: seq) { c, _ in c.adjust = adjust }
    }

    /// 设置某 clip(主轴或连接子项)的 effects 列表。纯函数，调用方负责 commit。
    static func setEffects(clipID: ClipID, _ effects: [Effect], in seq: Sequence) -> Sequence {
        mutatingClip(clipID, in: seq) { c, _ in c.effects = effects }
    }

    /// 设置某 clip(主轴或连接子项)的音量关键帧列表。纯函数，调用方负责 commit。
    static func setVolumeKeyframes(clipID: ClipID, _ kfs: [VolumeKeyframe], in seq: Sequence) -> Sequence {
        mutatingClip(clipID, in: seq) { c, _ in c.volumeKeyframes = kfs }
    }

    /// 设置某 clip(主轴或连接子项)的变换关键帧。纯函数,调用方负责 commit。
    static func setTransformKeyframes(clipID: ClipID, _ kfs: [TransformKeyframe], in seq: Sequence) -> Sequence {
        mutatingClip(clipID, in: seq) { c, _ in c.transformKeyframes = kfs }
    }

    /// 设置主轴第 index 个片段的交叉叠化时长(与前一片段 dissolve)。0=取消。
    static func setCrossfade(at index: Int, duration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index), case .clip(var c) = s.spine[index] else { return s }
        c.crossfadeIn = duration < .zero ? .zero : duration
        s.spine[index] = .clip(c)
        assertInvariants(s)
        return s
    }

    /// 设置某 clip(主轴或连接子项)的标题规格(文字/字体/颜色/位置)。
    static func setTitle(clipID: ClipID, _ spec: TitleSpec, in seq: Sequence) -> Sequence {
        mutatingClip(clipID, in: seq) { c, _ in c.title = spec }
    }

    /// 设置某 clip 的时间线定位:offset(连接片段相对宿主起点的偏移)和/或 duration(时长)。
    /// 用于给【字幕/连接片段】改起止时间(set_title 的 startSeconds/durationSeconds)。
    /// 主轴 clip 的 offset 在磁性布局里无意义,只应用 duration。纯函数,调用方负责 commit。
    static func setClipTiming(clipID: ClipID, offset: Time?, sourceIn: Time?, duration: Time?, in seq: Sequence) -> Sequence {
        mutatingClip(clipID, in: seq) { c, isConnected in
            if isConnected {                                  // 连接:offset + sourceIn + 时长
                if let o = offset { c.offset = .seconds(max(0, o.seconds)) }
                if let si = sourceIn { c.sourceIn = .seconds(max(0, si.seconds)) }
                if let d = duration { c.duration = .seconds(max(0.1, d.seconds)) }
            } else if let d = duration {                      // 主轴:只改时长
                c.duration = d
            }
        }
    }

    /// 设置某 clip(主轴或连接子项)的启用状态(V 键停用/启用)。纯函数,调用方负责 commit。
    static func setEnabled(clipID: ClipID, _ enabled: Bool, in seq: Sequence) -> Sequence {
        mutatingClip(clipID, in: seq) { c, _ in c.enabled = enabled }
    }
}
