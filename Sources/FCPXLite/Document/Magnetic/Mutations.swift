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

    /// 把某个 clip(可能在主轴,也可能是某宿主的 connected 子项)移动到 (目标lane, 目标绝对时间)。
    /// lane==0 → 放回主轴:从原处移除,按目标时间插入主轴对应下标(磁性,无缝)。
    /// lane!=0 → 作为连接片段:从原处移除,挂到目标时间所在的主轴 clip 上,offset=目标时间−宿主起点。
    static func relocate(clipID: ClipID, toLane lane: Int, atTime t: Time, in seq: Sequence) -> Sequence {
        var s = seq

        // 1) 按 id 定位并提取 clip 值(主轴元素或某宿主的连接子项)。
        guard let extracted = extractClip(clipID, from: &s) else { return seq } // 未知 id → no-op

        if lane == 0 {
            // 2a) 放回主轴:按目标时间在缩减后的主轴里算插入下标(prefix-sum,磁性)。
            var clip = extracted
            clip.lane = 0
            clip.offset = .zero
            let idx = spineInsertionIndex(forTime: t, in: s)
            s.spine.insert(.clip(clip), at: idx)
        } else {
            // 2b) 作为连接片段挂到目标时间所在的主轴 clip 上。
            guard let host = hostSpineIndex(forTime: t, in: s) else { return seq } // 无主轴 clip → no-op
            let hostAbsStart = s.spine[0..<host.index].reduce(Time.zero) { $0 + $1.duration }
            var clip = extracted
            // 轨道磁吸:不悬空在拖到的原始 lane;按方向从 ±1 向外找第一个不冲突的层级(中间空则弹回 ±1)。
            clip.lane = magneticLane(direction: lane, start: t, duration: extracted.duration, in: s)
            let off = t - hostAbsStart
            clip.offset = off < .zero ? .zero : off   // clamp offset ≥ 0
            guard case .clip(var hostClip) = s.spine[host.index] else { return seq }
            hostClip.connected.append(clip)
            s.spine[host.index] = .clip(hostClip)
        }

        assertInvariants(s)
        return s
    }

    /// 轨道磁吸:给定拖拽方向(正/负)与目标时间区间,返回该侧从 ±1 起第一个不与现有
    /// 连接片段时间重叠的层级。中间层级空 → 落在 ±1(贴着主轴),不悬空。
    private static func magneticLane(direction: Int, start: Time, duration: Time, in seq: Sequence) -> Int {
        let dir = direction >= 0 ? 1 : -1
        let end = start + duration
        let connected = Layout.compute(seq).filter { $0.isConnected }
        for step in 1...8 {
            let lane = dir * step
            let collides = connected.contains { p in
                p.lane == lane && p.absStart < end && start < (p.absStart + p.duration)
            }
            if !collides { return lane }
        }
        return dir * 8
    }

    /// 从 spine(直接元素或某宿主的 connected 列表)按 id 找到并移除该 clip,返回其值。
    /// 找不到返回 nil(调用方据此 no-op)。
    private static func extractClip(_ id: ClipID, from s: inout Sequence) -> Clip? {
        // 主轴直接元素
        for (i, el) in s.spine.enumerated() {
            if case .clip(let c) = el, c.id == id {
                s.spine.remove(at: i)
                return c
            }
        }
        // 某宿主的连接子项
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var host) = el else { continue }
            if let j = host.connected.firstIndex(where: { $0.id == id }) {
                let child = host.connected.remove(at: j)
                s.spine[i] = .clip(host)
                return child
            }
        }
        return nil
    }

    /// 目标时间 t 在主轴里的插入下标 = 累计起点 < t 的 spine 元素数量(clamp 到 [0, count])。
    private static func spineInsertionIndex(forTime t: Time, in seq: Sequence) -> Int {
        var acc = Time.zero
        var count = 0
        for el in seq.spine {
            if acc < t { count += 1 }
            acc = acc + el.duration
        }
        return max(0, min(count, seq.spine.count))
    }

    /// 找到半开区间 [absStart, absStart+duration) 包含 t 的主轴 clip;无包含则取最近;无 spine clip 返回 nil。
    private static func hostSpineIndex(forTime t: Time, in seq: Sequence) -> (index: Int, absStart: Time)? {
        var entries: [(index: Int, absStart: Time, duration: Time)] = []
        var acc = Time.zero
        for (i, el) in seq.spine.enumerated() {
            if case .clip = el {
                entries.append((index: i, absStart: acc, duration: el.duration))
            }
            acc = acc + el.duration
        }
        guard !entries.isEmpty else { return nil }

        var best = entries[0]
        var bestDist: Time? = nil
        for e in entries {
            let end = e.absStart + e.duration
            if t >= e.absStart && t < end {
                return (e.index, e.absStart)   // 完全包含
            }
            let dist: Time = t < e.absStart ? (e.absStart - t) : (t - end)
            if bestDist == nil || dist < bestDist! {
                bestDist = dist
                best = e
            }
        }
        return (best.index, best.absStart)
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
                         adjust: c.adjust,
                         effects: c.effects,    // 切割保留特效(否则第二段静默丢特效)
                         enabled: c.enabled)    // 切割保留启用状态(否则停用片段切后右半被重新启用)

        s.spine.replaceSubrange(index...index, with: [.clip(left), .clip(right)])
        assertInvariants(s)
        return s
    }

    /// 删除一个连接片段(按 id 从其宿主的 connected 里移除)。主轴片段不在此处理。
    static func removeConnected(clipID id: ClipID, in seq: Sequence) -> Sequence {
        var s = seq
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var host) = el else { continue }
            if let j = host.connected.firstIndex(where: { $0.id == id }) {
                host.connected.remove(at: j); s.spine[i] = .clip(host)
                assertInvariants(s); return s
            }
        }
        return s
    }

    /// 在连接片段(id)内部 localTime 处切两半,两半都作为同宿主的连接片段(第二段 offset 右移)。
    static func bladeConnected(clipID id: ClipID, localTime: Time, in seq: Sequence) -> Sequence {
        var s = seq
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var host) = el,
                  let j = host.connected.firstIndex(where: { $0.id == id }) else { continue }
            let c = host.connected[j]
            guard localTime > .zero, localTime < c.duration else { return s }
            var left = c; left.duration = localTime
            let right = Clip(assetID: c.assetID, sourceIn: c.sourceIn + localTime,
                             duration: c.duration - localTime, connected: [],
                             lane: c.lane, offset: c.offset + localTime,
                             adjust: c.adjust, effects: c.effects, enabled: c.enabled)
            host.connected.replaceSubrange(j...j, with: [left, right])
            s.spine[i] = .clip(host)
            assertInvariants(s); return s
        }
        return s
    }

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

    /// Position-move: lift a spine clip, replace its slot with .gap(duration:),
    /// insert the clip at target time in lane 0 (no magnetic snap).
    /// If clipID refers to a connected child, falls back to relocate(lane:0) since there's
    /// no spine slot to leave a gap in.
    /// Returns seq unchanged if clipID not found.
    static func positionMove(clipID: ClipID, atTime t: Time, in seq: Sequence) -> Sequence {
        var s = seq
        // Check if it's a spine-direct element first
        guard let spineIdx = s.spine.firstIndex(where: {
            if case .clip(let c) = $0 { return c.id == clipID }
            return false
        }) else {
            // Not a spine clip — try connected child fallback via relocate lane 0
            let isConnectedChild = s.spine.contains { el in
                guard case .clip(let c) = el else { return false }
                return c.connected.contains { $0.id == clipID }
            }
            guard isConnectedChild else { return seq } // truly unknown id → no-op
            return relocate(clipID: clipID, toLane: 0, atTime: t, in: seq)
        }
        // Extract clip value, replace with gap of same duration
        guard case .clip(let extracted) = s.spine[spineIdx] else { return seq }
        let gapDuration = extracted.duration
        s.spine[spineIdx] = .gap(duration: gapDuration)
        // Insert at target time in the now-gap-containing sequence
        let idx = spineInsertionIndex(forTime: t, in: s)
        var placed = extracted
        placed.lane = 0
        placed.offset = .zero
        s.spine.insert(.clip(placed), at: idx)
        assertInvariants(s)
        return s
    }

    /// Resize a .gap at spine[index] to new duration.
    /// Clamps to minimum 1 tick. No-op if spine[index] is a clip or index is out of bounds.
    static func setGapDuration(at index: Int, duration: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        guard case .gap(let id, _) = s.spine[index] else { return s }   // 保留原 id
        let ts = duration.timescale > 0 ? duration.timescale : 600
        let minDur = Time(value: 1, timescale: ts)
        let clamped = duration < minDur ? minDur : duration
        s.spine[index] = .gap(id: id, duration: clamped)
        assertInvariants(s)
        return s
    }

    /// 按 GapID 改时长(供 UI 选中 gap 后修剪)。
    static func setGapDurationByID(_ gapID: GapID, duration: Time, in seq: Sequence) -> Sequence {
        guard let i = seq.spine.firstIndex(where: { $0.gapID == gapID }) else { return seq }
        return setGapDuration(at: i, duration: duration, in: seq)
    }

    /// 删除一个 gap(按 id,后续合拢)。
    static func removeGap(_ gapID: GapID, in seq: Sequence) -> Sequence {
        var s = seq
        guard let i = s.spine.firstIndex(where: { $0.gapID == gapID }) else { return s }
        s.spine.remove(at: i)
        assertInvariants(s)
        return s
    }

    /// 把 gap 移到目标绝对时间处(从原位移除,按时间插回主轴)。
    static func moveGap(_ gapID: GapID, toTime t: Time, in seq: Sequence) -> Sequence {
        var s = seq
        guard let from = s.spine.firstIndex(where: { $0.gapID == gapID }) else { return s }
        let el = s.spine.remove(at: from)
        let idx = spineInsertionIndex(forTime: t, in: s)
        s.spine.insert(el, at: idx)
        assertInvariants(s)
        return s
    }

    /// 设置某 clip(主轴或连接子项)的 Adjustments(inspector 调参)。
    static func setAdjust(clipID: ClipID, _ adjust: Adjustments, in seq: Sequence) -> Sequence {
        var s = seq
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var c) = el else { continue }
            if c.id == clipID { c.adjust = adjust; s.spine[i] = .clip(c); return s }
            if let j = c.connected.firstIndex(where: { $0.id == clipID }) {
                c.connected[j].adjust = adjust; s.spine[i] = .clip(c); return s
            }
        }
        return s
    }

    /// 设置某 clip(主轴或连接子项)的 effects 列表。纯函数，调用方负责 commit。
    static func setEffects(clipID: ClipID, _ effects: [Effect], in seq: Sequence) -> Sequence {
        var s = seq
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var c) = el else { continue }
            if c.id == clipID { c.effects = effects; s.spine[i] = .clip(c); return s }
            if let j = c.connected.firstIndex(where: { $0.id == clipID }) {
                c.connected[j].effects = effects; s.spine[i] = .clip(c); return s
            }
        }
        return s
    }

    /// 设置某 clip(主轴或连接子项)的音量关键帧列表。纯函数，调用方负责 commit。
    static func setVolumeKeyframes(clipID: ClipID, _ kfs: [VolumeKeyframe], in seq: Sequence) -> Sequence {
        var s = seq
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var c) = el else { continue }
            if c.id == clipID { c.volumeKeyframes = kfs; s.spine[i] = .clip(c); return s }
            if let j = c.connected.firstIndex(where: { $0.id == clipID }) {
                c.connected[j].volumeKeyframes = kfs; s.spine[i] = .clip(c); return s
            }
        }
        return s
    }

    /// 设置某 clip(主轴或连接子项)的启用状态(V 键停用/启用)。纯函数,调用方负责 commit。
    static func setEnabled(clipID: ClipID, _ enabled: Bool, in seq: Sequence) -> Sequence {
        var s = seq
        for (i, el) in s.spine.enumerated() {
            guard case .clip(var c) = el else { continue }
            if c.id == clipID { c.enabled = enabled; s.spine[i] = .clip(c); return s }
            if let j = c.connected.firstIndex(where: { $0.id == clipID }) {
                c.connected[j].enabled = enabled; s.spine[i] = .clip(c); return s
            }
        }
        return s
    }

    private static func assertInvariants(_ seq: Sequence) {
        #if DEBUG
        do { try Invariants.check(seq) }
        catch { assertionFailure("磁性不变量被破坏: \(error)") }
        #endif
    }
}
