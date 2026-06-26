import Foundation

/// 命令层:唯一的文档修改入口。手动 UI 与未来 Agent 工具都只调这里。
/// 每个命令是 Sequence → Sequence 纯函数,执行后断言三条不变量(fail fast)。
///
/// 命令层错误约定:目标元素索引(at/index/from/toHostIndex)越界或类型不符 → 原样返回(no-op),不崩溃;
/// 插入/移动的【目标落点】(insert position / move `to`)做 clamp(支持末尾追加);
/// 数值参数(duration/sourceIn)夹到素材边界内。Agent/UI 调用方据此推理。
enum Mutations {

    static func insertClip(_ clip: Clip, at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        let i = max(0, min(index, s.spine.count))
        s.spine.insert(.clip(clip), at: i)
        assertInvariants(s)
        return s
    }

    /// ripple 删除(默认):移除元素,后续自动左移合拢。
    /// 宿主 clip 的 connected 子节点将重锚到删除后占据该时间的主轴 clip,保持绝对位置不变。
    static func rippleDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }

        // 提取待重锚的 orphan children 及其绝对位置
        let orphansWithAbs = orphansAbsolutePositions(at: index, in: s)

        s.spine.remove(at: index)

        if !orphansWithAbs.isEmpty {
            s = reanchor(orphans: orphansWithAbs, into: s)
        }

        assertInvariants(s)
        return s
    }

    /// lift 删除:替换为等长 gap,保留空隙。
    /// 宿主 clip 的 connected 子节点将重锚到最近的主轴 clip,保持绝对位置不变。
    static func liftDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }

        // 提取待重锚的 orphan children 及其绝对位置
        let orphansWithAbs = orphansAbsolutePositions(at: index, in: s)

        let d = s.spine[index].duration
        s.spine[index] = .gap(duration: d)

        if !orphansWithAbs.isEmpty {
            s = reanchor(orphans: orphansWithAbs, into: s)
        }

        assertInvariants(s)
        return s
    }

    /// 主轴内移动/换序 = remove + insert(等价于一次 ripple)。
    /// connected children 随宿主一起移动(Invariant 2: connected follows host),这是预期的 FCPX 行为。
    static func moveClip(from: Int, to: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(from) else { return s }
        let el = s.spine.remove(at: from)
        let dest = max(0, min(to, s.spine.count))
        s.spine.insert(el, at: dest)
        assertInvariants(s)
        return s
    }

    // MARK: - Private: re-anchoring helpers

    /// 计算 spine[index] 上各 connected child 的绝对起始时间。
    private static func orphansAbsolutePositions(at index: Int, in seq: Sequence) -> [(clip: Clip, absStart: Time)] {
        guard case .clip(let host) = seq.spine[index], !host.connected.isEmpty else { return [] }
        // 宿主的 absStart = spine[0..<index] 的时长之和
        let hostAbsStart = seq.spine[0..<index].reduce(Time.zero) { $0 + $1.duration }
        return host.connected.map { child in
            (clip: child, absStart: hostAbsStart + child.offset)
        }
    }

    /// 将各孤儿 connected clip 重锚到 seq 中最合适的主轴 clip,保持 absStart 不变。
    private static func reanchor(orphans: [(clip: Clip, absStart: Time)], into seq: Sequence) -> Sequence {
        // 收集剩余主轴 clips 及其 absStart
        var spineClipsWithAbs: [(index: Int, absStart: Time, duration: Time)] = []
        var t = Time.zero
        for (i, el) in seq.spine.enumerated() {
            if case .clip = el {
                spineClipsWithAbs.append((index: i, absStart: t, duration: el.duration))
            }
            t = t + el.duration
        }

        // 若没有任何 spine clip,孤儿只能丢弃
        guard !spineClipsWithAbs.isEmpty else { return seq }

        var s = seq
        for orphan in orphans {
            // 找包含此绝对时间的主轴 clip
            var bestIdx = spineClipsWithAbs[0].index
            var bestDist: Time? = nil

            for entry in spineClipsWithAbs {
                let end = entry.absStart + entry.duration
                if orphan.absStart >= entry.absStart && orphan.absStart < end {
                    // 完全包含,直接选
                    bestIdx = entry.index
                    bestDist = .zero
                    break
                }
                // 否则按距离选最近
                let dist: Time
                if orphan.absStart < entry.absStart {
                    dist = entry.absStart - orphan.absStart
                } else {
                    dist = orphan.absStart - end + Time(value: 1, timescale: orphan.absStart.timescale)
                }
                if bestDist == nil || dist < bestDist! {
                    bestDist = dist
                    bestIdx = entry.index
                }
            }

            // 计算新宿主的 absStart
            let newHostAbsStart = spineClipsWithAbs.first(where: { $0.index == bestIdx })!.absStart
            var reanchored = orphan.clip
            reanchored.offset = orphan.absStart - newHostAbsStart

            guard case .clip(var newHost) = s.spine[bestIdx] else { continue }
            newHost.connected.append(reanchored)
            s.spine[bestIdx] = .clip(newHost)
        }

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
    /// lane 0 为主轴保留,connected clip 不得使用 lane 0 → 原样返回(no-op)。
    static func connectClip(_ clip: Clip, toHostIndex: Int, lane: Int, offset: Time,
                            in seq: Sequence) -> Sequence {
        var s = seq
        guard lane != 0 else { return s }                              // lane 0 reserved for spine
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
