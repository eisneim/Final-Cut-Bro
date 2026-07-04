import Foundation

extension Mutations {
    static func rippleTrimRight(at index: Int, newDuration: Time,
                                assetDuration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        guard case .clip(var c) = s.spine[index] else { return s }
        let maxDur = assetDuration - c.sourceIn
        let minDur = Time(value: 1, timescale: maxDur.timescale) // 至少 1 个 timescale 单位
        guard minDur <= maxDur else { return s }                 // 素材已无可用余量,放弃
        c.duration = newDuration.clamped(to: minDur...maxDur)
        s.spine[index] = .clip(c)
        assertInvariants(s)
        return s
    }

    /// ripple trim 左边缘:同时调 sourceIn(+delta)与 duration(-delta),夹在素材内。
    /// 注:左边缘不需要 assetDuration(右边缘不变,无上界溢出风险);trimRight 才需要。
    static func rippleTrimLeft(at index: Int, deltaIn: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        guard case .clip(var c) = s.spine[index] else { return s }
        // 新 sourceIn 不得 < 0,也不得使 duration ≤ 0
        // 左边缘约束由 sourceIn≥0 与 duration≥1tick 决定
        let newSourceIn = (c.sourceIn + deltaIn).clamped(
            to: Time.zero...(c.sourceIn + c.duration - Time(value: 1, timescale: c.duration.timescale)))
        let consumed = newSourceIn - c.sourceIn
        c.sourceIn = newSourceIn
        c.duration = c.duration - consumed
        s.spine[index] = .clip(c)
        assertInvariants(s)
        return s
    }

    /// Slip(滑移):改主轴第 index 个 clip 的入/出点(sourceIn += delta),【位置与时长都不变】。
    /// 只改"看到素材的哪一段"。约束:sourceIn ∈ [0, assetDuration - duration]。
    static func slip(at index: Int, delta: Time, assetDuration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        guard case .clip(var c) = s.spine[index] else { return s }
        let maxIn = assetDuration - c.duration            // 入点上界,保证 out=in+dur ≤ 素材尾
        let hi = maxIn < .zero ? .zero : maxIn
        c.sourceIn = (c.sourceIn + delta).clamped(to: Time.zero...hi)
        s.spine[index] = .clip(c)
        assertInvariants(s)
        return s
    }

    /// Slide(滑动):把主轴第 index 个 clip 沿时间线移动 delta,【自身入出/时长不变】,
    /// 由相邻两片段吸收:前一片段尾部 +delta(延长),后一片段头部 +delta(裁掉,sourceIn+delta/duration-delta)。
    /// 总时长不变。要求前后都是 clip(非 gap)。delta 被夹在前后片段的素材余量内。
    static func slide(at index: Int, delta: Time,
                      prevAssetDuration: Time, nextAssetDuration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        let prevIdx = index - 1, nextIdx = index + 1
        guard s.spine.indices.contains(prevIdx), s.spine.indices.contains(nextIdx) else { return s }
        guard case .clip(var prev) = s.spine[prevIdx],
              case .clip(let cur)  = s.spine[index],   // 当前片段自身不变,仅校验是 clip
              case .clip(var next) = s.spine[nextIdx] else { return s }
        _ = cur
        let tick = Time(value: 1, timescale: 600)
        // 正 delta:前片段延长(需素材余量),后片段头部裁掉(需时长余量)。
        // 负 delta:前片段缩短(需时长余量),后片段头部回退(需 sourceIn 余量)。
        // 上界(delta>0):min(prev 素材余量, next 时长余量-1tick)
        let prevRoom = prevAssetDuration - (prev.sourceIn + prev.duration)   // 前片段还能延长多少
        let nextDurRoom = next.duration - tick                               // 后片段头最多裁多少
        let hi = min(prevRoom, nextDurRoom)
        // 下界(delta<0):-(min(prev 时长余量-1tick, next 头部回退余量=next.sourceIn))
        let prevDurRoom = prev.duration - tick
        let nextHeadRoom = next.sourceIn
        let lo = Time.zero - min(prevDurRoom, nextHeadRoom)
        let d = delta.clamped(to: lo...hi)
        prev.duration = prev.duration + d
        next.sourceIn = next.sourceIn + d
        next.duration = next.duration - d
        s.spine[prevIdx] = .clip(prev)
        s.spine[nextIdx] = .clip(next)
        assertInvariants(s)
        return s
    }

    /// 在主轴第 index 个 clip 内部 localTime(相对该 clip 起点)处切两半。
    static func blade(at index: Int, localTime: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        guard case .clip(let c) = s.spine[index] else { return s }
        guard localTime > .zero, localTime < c.duration else { return s } // 边界不切
        var left = c
        left.duration = localTime
        left.connected = c.connected.filter { $0.offset < localTime }

        let right = Clip(assetID: c.assetID,
                         sourceIn: c.sourceIn + localTime,
                         duration: c.duration - localTime,
                         connected: c.connected
                            .filter { $0.offset >= localTime }
                            .map { var x = $0; x.offset = x.offset - localTime; return x },
                         adjust: c.adjust,
                         effects: c.effects,    // 切割保留特效(否则第二段静默丢特效)
                         enabled: c.enabled)    // 切割保留启用状态(否则停用片段切后右半被重新启用)

        s.spine.replaceSubrange(index...index, with: [.clip(left), .clip(right)])
        assertInvariants(s)
        return s
    }

    /// 删除一个连接片段(按 id 从其宿主的 connected 里移除)。主轴片段不在此处理。
}
