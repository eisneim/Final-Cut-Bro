import Foundation

/// 命令层:唯一的文档修改入口。手动 UI 与未来 Agent 工具都只调这里。
/// 每个命令是 Sequence → Sequence 纯函数,执行后断言三条不变量(fail fast)。
enum Mutations {

    static func insertClip(_ clip: Clip, at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        let i = max(0, min(index, s.spine.count))
        s.spine.insert(.clip(clip), at: i)
        assertInvariants(s)
        return s
    }

    /// ripple 删除(默认):移除元素,后续自动左移合拢。
    static func rippleDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        s.spine.remove(at: index)
        assertInvariants(s)
        return s
    }

    /// lift 删除:替换为等长 gap,保留空隙。
    static func liftDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        let d = s.spine[index].duration
        s.spine[index] = .gap(duration: d)
        assertInvariants(s)
        return s
    }

    /// 主轴内移动/换序 = remove + insert(等价于一次 ripple)。
    static func moveClip(from: Int, to: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(from) else { return s }
        let el = s.spine.remove(at: from)
        let dest = max(0, min(to, s.spine.count))
        s.spine.insert(el, at: dest)
        assertInvariants(s)
        return s
    }

    /// ripple trim 右边缘:改 duration,夹在 (0, assetDuration - sourceIn]。
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
    static func rippleTrimLeft(at index: Int, deltaIn: Time,
                               assetDuration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        guard case .clip(var c) = s.spine[index] else { return s }
        // 新 sourceIn 不得 < 0,也不得使 duration ≤ 0
        // 注:左边缘约束由 sourceIn≥0 与 duration≥1tick 决定;assetDuration 暂为与 trimRight 对称保留
        let newSourceIn = (c.sourceIn + deltaIn).clamped(
            to: Time.zero...(c.sourceIn + c.duration - Time(value: 1, timescale: c.duration.timescale)))
        let consumed = newSourceIn - c.sourceIn
        c.sourceIn = newSourceIn
        c.duration = c.duration - consumed
        s.spine[index] = .clip(c)
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
                         adjust: c.adjust)

        s.spine.replaceSubrange(index...index, with: [.clip(left), .clip(right)])
        assertInvariants(s)
        return s
    }

    /// 把 clip 作为连接片段挂到主轴第 toHostIndex 个 clip 上。
    static func connectClip(_ clip: Clip, toHostIndex: Int, lane: Int, offset: Time,
                            in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(toHostIndex) else { return s }
        guard case .clip(var host) = s.spine[toHostIndex] else { return s }
        var conn = clip
        conn.lane = lane
        conn.offset = offset
        host.connected.append(conn)
        s.spine[toHostIndex] = .clip(host)
        assertInvariants(s)
        return s
    }

    private static func assertInvariants(_ seq: Sequence) {
        #if DEBUG
        do { try Invariants.check(seq) }
        catch { assertionFailure("磁性不变量被破坏: \(error)") }
        #endif
    }
}
