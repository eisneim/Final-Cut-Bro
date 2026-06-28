import AppKit

/// TimelineContentView 鼠标交互,按当前工具分支:
/// - select:拖片段边缘 → trim/roll;拖中部 → relocate(磁吸)
/// - position:拖片段 → positionMove(不吸附,原处留灰 gap)
/// - trim:拖片段首/尾 → rippleTrimLeft/Right(光标 resizeLeftRight)
/// - hand:拖动 → 横向滚动(光标 openHand)
/// - zoom:拖动 → 改 pxPerSecond(光标 crosshair)
/// - blade:点片段 → 切割
/// 空白/标尺 → 移动播放头。光标随工具切换(resetCursorRects)。
extension TimelineContentView {

    // MARK: - 命中辅助

    /// 取主轴 clip(及其 spine 下标)by id。
    func spineClipAndIndex(_ id: ClipID) -> (clip: Clip, index: Int)? {
        for (i, el) in sequence.spine.enumerated() {
            if case .clip(let c) = el, c.id == id { return (c, i) }
        }
        return nil
    }

    func assetDuration(of clip: Clip) -> Time {
        assetLibrary.first(where: { $0.id == clip.assetID })?.duration ?? clip.duration
    }

    /// 命中某主轴 clip 的首/尾边缘(lane 0,edgeHitPx 内)。
    func edgeHit(at pt: NSPoint) -> (clipID: ClipID, index: Int, edge: TrimEdge)? {
        for p in placed where p.lane == 0 {
            let r = clipRect(p)
            guard pt.y >= r.minY, pt.y <= r.maxY else { continue }
            if abs(pt.x - r.minX) <= Self.edgeHitPx,
               let s = spineClipAndIndex(p.clipID) { return (p.clipID, s.index, .head) }
            if abs(pt.x - r.maxX) <= Self.edgeHitPx,
               let s = spineClipAndIndex(p.clipID) { return (p.clipID, s.index, .tail) }
        }
        return nil
    }

    /// 命中两片段间切点(lane 0 相邻 clip,尾紧接头,无 gap)→ roll 编辑。
    /// 若命中,优先使用 roll(不走单边 edge trim)。
    func rollHit(at pt: NSPoint) -> (leftIndex: Int, rightIndex: Int, leftClipID: ClipID, rightClipID: ClipID)? {
        // 收集 lane-0 clips,按 absStart 排序
        let lane0 = placed.filter { $0.lane == 0 }.sorted { $0.absStart < $1.absStart }
        guard lane0.count >= 2 else { return nil }
        for i in 0..<(lane0.count - 1) {
            let left  = lane0[i]
            let right = lane0[i + 1]
            let leftR  = clipRect(left)
            let rightR = clipRect(right)
            // 必须在同一 y 区间(两者 lane 均为 0,高度相同)
            guard pt.y >= leftR.minY, pt.y <= leftR.maxY else { continue }
            // 两片段必须紧邻(无 gap):left.maxX ≈ right.minX
            guard abs(leftR.maxX - rightR.minX) < 2 else { continue }
            // 光标在切点附近
            let cutX = leftR.maxX
            guard abs(pt.x - cutX) <= Self.edgeHitPx else { continue }
            guard let ls = spineClipAndIndex(left.clipID),
                  let rs = spineClipAndIndex(right.clipID) else { continue }
            return (ls.index, rs.index, left.clipID, right.clipID)
        }
        return nil
    }

    // MARK: - mouseDown

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
        // ruler 钉在视口顶部(随竖滚移动),命中判定必须用同一钉顶坐标,否则竖滚后
        // 可视 ruler 在 viewport 顶、而 pt.y<rulerHeight 仍指内容顶 → 点 ruler 会落到上层 clip 上(无反应)。
        let visibleTop = enclosingScrollView?.documentVisibleRect.minY ?? 0
        let inRuler = pt.y >= visibleTop && pt.y < visibleTop + Self.rulerHeight

        switch currentTool {
        case .hand:
            handLastX = pt.x
            return
        case .zoom:
            zoomStartX = pt.x
            zoomStartPx = pxPerSecond
            return
        case .blade:
            if !inRuler, let p = hitTestClip(at: pt),
               let s = TimelineGeometry.spineIndex(ofClipID: p.clipID, in: sequence) {
                dispatch?(.blade(at: s, localTime: Time.seconds(max(0, t - p.absStart.seconds))))
            }
            return
        case .trim:
            if let e = edgeHit(at: pt) {
                trimDrag = e
                dispatch?(.selectClip(e.clipID))
                return
            }
            // 修剪工具点空白也移播放头
            dispatch?(.setPlayhead(Time.seconds(t)))
            return
        case .select, .position, .range:
            if !inRuler {
                // Volume level 线优先拦截(select 工具)
                if volumeMouseDown(with: event, at: pt) { return }
                // 1. roll hit 优先(两片段切点)
                if currentTool == .select, let roll = rollHit(at: pt) {
                    rollDrag = (roll.leftIndex, roll.rightIndex,
                                roll.leftClipID, roll.rightClipID, pt.x)
                    dispatch?(.selectClip(roll.leftClipID))
                    return
                }
                // 2. 边缘 trim(select 工具也支持)
                if currentTool == .select, let e = edgeHit(at: pt) {
                    trimDrag = e
                    dispatch?(.selectClip(e.clipID))
                    return
                }
                // 3. 普通片段拖动/选择
                if let p = hitTestClip(at: pt) {
                    dragClipID = p.clipID
                    let clipStartX = TimelineGeometry.x(forSeconds: p.absStart.seconds, pxPerSecond: pxPerSecond)
                    dragGrabDX = pt.x - clipStartX
                    dragStartPoint = pt
                    dragCurrentPoint = pt
                    dispatch?(.selectClip(p.clipID))
                    return
                }
            }
            dragClipID = nil
            dispatch?(.setPlayhead(Time.seconds(t)))
        }
    }

    // MARK: - mouseDragged

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        // Volume level 线拖拽优先
        if volumeMouseDragged(with: event, at: pt) { return }

        // 手工具:横向滚动
        if currentTool == .hand, let last = handLastX, let sv = enclosingScrollView {
            let dx = pt.x - last
            let clip = sv.contentView
            var newX = clip.bounds.origin.x - dx
            newX = max(0, min(newX, bounds.width - clip.bounds.width))
            clip.scroll(to: NSPoint(x: newX, y: 0))
            sv.reflectScrolledClipView(clip)
            handLastX = pt.x   // 注意:scroll 后坐标系变,简单近似
            return
        }
        // 缩放工具:拖动改缩放
        if currentTool == .zoom, let sx = zoomStartX {
            let factor = 1.0 + Double(pt.x - sx) / 200.0
            dispatch?(.setZoom(Double(zoomStartPx) * factor))
            return
        }
        // Roll 编辑:拖动切点,左 clip 向右 / 右 clip 向左等量调整
        if let rd = rollDrag {
            guard let (leftClip, _)  = spineClipAndIndex(rd.leftClipID),
                  let (rightClip, _) = spineClipAndIndex(rd.rightClipID) else { return }
            let deltaSec = Double(pt.x - rd.startX) / Double(pxPerSecond)
            let leftAssetDur = assetDuration(of: leftClip)

            // clamp:左不超素材;右不低于 1 帧(约 0.04s)
            let maxExtendLeft  = leftAssetDur.seconds - (leftClip.sourceIn.seconds + leftClip.duration.seconds)
            let maxShrinkRight = rightClip.duration.seconds - 0.04
            let clampedDelta = max(-maxShrinkRight, min(maxExtendLeft, deltaSec))

            let newLeftDur  = leftClip.duration.seconds  + clampedDelta
            let newRightIn  = clampedDelta   // trimLeft deltaIn = 正值收头

            dispatch?(.trimRight(at: rd.leftIndex,
                                 newDuration: .seconds(max(0.04, newLeftDur)),
                                 assetDuration: leftAssetDur))
            dispatch?(.trimLeft(at: rd.rightIndex, deltaIn: .seconds(newRightIn)))
            return
        }
        // 修剪工具 / select 工具边缘 trim:实时 trim
        if let td = trimDrag {
            guard let (clip, _) = spineClipAndIndex(td.clipID) else { return }
            let clipStartSec = (placed.first { $0.clipID == td.clipID }?.absStart.seconds) ?? 0
            let cursorSec = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
            let assetDur = assetDuration(of: clip)
            if td.edge == .tail {
                let newDur = max(0.04, cursorSec - clipStartSec)
                dispatch?(.trimRight(at: td.index, newDuration: .seconds(newDur), assetDuration: assetDur))
            } else {
                let deltaIn = cursorSec - clipStartSec   // 正=向右收头
                dispatch?(.trimLeft(at: td.index, deltaIn: .seconds(deltaIn)))
            }
            return
        }
        // 片段拖动:所见即所得 —— 实时 relocate(不画 ghost,空缺立即合拢,FCPX 丝滑磁性)。
        if let id = dragClipID {
            dragCurrentPoint = pt
            if let start = dragStartPoint, hypot(pt.x - start.x, pt.y - start.y) <= Self.dragThresholdPx { return }
            let lane = TimelineGeometry.lane(forY: pt.y, rulerHeight: Self.rulerHeight,
                                             laneHeight: laneH, laneGap: Self.laneGap,
                                             contentHeight: bounds.height)
            if currentTool == .position {
                // 位置工具:拖拽中只画 ghost 跟随光标(不 dispatch)。positionMove 会在源处留 gap,
                // 若每个 tick 都发就会叠出多个 gap("两个黑条")且坐标失效跳变 → 改为松手一次性 commit。
                needsDisplay = true
            } else {
                let snapped = snappedTargetSeconds(forCursorX: pt.x)
                dispatch?(.relocateClip(id, lane: lane, time: Time.seconds(snapped)))
            }
            return
        }
        // 空白擦洗播放头
        dispatch?(.setPlayhead(Time.seconds(TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond))))
    }

    // MARK: - mouseUp

    override func mouseUp(with event: NSEvent) {
        volumeMouseUp()
        // 位置工具:松手时一次性 commit positionMove(源处留 gap,目标落点 = 光标,不吸附)。
        if currentTool == .position, let id = dragClipID, let cur = dragCurrentPoint,
           let start = dragStartPoint, hypot(cur.x - start.x, cur.y - start.y) > Self.dragThresholdPx {
            let lane = TimelineGeometry.lane(forY: cur.y, rulerHeight: Self.rulerHeight,
                                             laneHeight: laneH, laneGap: Self.laneGap,
                                             contentHeight: bounds.height)
            let raw = max(0, TimelineGeometry.seconds(forX: cur.x - dragGrabDX, pxPerSecond: pxPerSecond))
            if lane == 0 { dispatch?(.positionMove(id, time: Time.seconds(raw))) }
            else { dispatch?(.relocateClip(id, lane: lane, time: Time.seconds(raw))) }
        }
        // 其余工具的片段拖动已在 mouseDragged 中实时完成(所见即所得),这里只清状态。
        dragClipID = nil; dragStartPoint = nil; dragCurrentPoint = nil
        trimDrag = nil; rollDrag = nil; handLastX = nil; zoomStartX = nil
        needsDisplay = true
    }

    // MARK: - 光标(随工具 + select 工具边缘热区)

    override func resetCursorRects() {
        discardCursorRects()
        switch currentTool {
        case .hand:
            addCursorRect(bounds, cursor: .openHand)
        case .zoom:
            addCursorRect(bounds, cursor: .crosshair)
        case .trim:
            addCursorRect(bounds, cursor: .resizeLeftRight)
        case .select:
            // 默认箭头覆盖全区
            addCursorRect(bounds, cursor: .arrow)
            addVolumeLineCursorRects()
            // lane-0 clip 的首/尾边缘热区 + roll 切点热区 → 双箭头光标
            let lane0 = placed.filter { $0.lane == 0 }.sorted { $0.absStart < $1.absStart }
            for p in lane0 {
                let r = clipRect(p)
                // 尾边缘
                let tailRect = NSRect(x: r.maxX - Self.edgeHitPx, y: r.minY,
                                     width: Self.edgeHitPx * 2, height: r.height)
                addCursorRect(tailRect, cursor: .resizeLeftRight)
                // 首边缘(不包含 roll 切点,若下一片段紧跟则那里已被 roll 热区覆盖)
                let headRect = NSRect(x: r.minX - Self.edgeHitPx, y: r.minY,
                                     width: Self.edgeHitPx * 2, height: r.height)
                addCursorRect(headRect, cursor: .resizeLeftRight)
            }
            // roll 切点:两相邻片段交界处单独设一次(与首/尾重叠也没关系,覆盖即可)
            for i in 0..<(lane0.count - 1) {
                let left  = lane0[i]
                let right = lane0[i + 1]
                let leftR  = clipRect(left)
                let rightR = clipRect(right)
                // 仅当两片段紧邻(无 gap)
                guard abs(leftR.maxX - rightR.minX) < 2 else { continue }
                let cutX = leftR.maxX
                let rollRect = NSRect(x: cutX - Self.edgeHitPx, y: leftR.minY,
                                     width: Self.edgeHitPx * 2, height: leftR.height)
                addCursorRect(rollRect, cursor: .resizeLeftRight)
            }
        default:
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    // MARK: - 吸附

    func snappedTargetSeconds(forCursorX cursorX: CGFloat) -> Double {
        let rawSeconds = TimelineGeometry.seconds(forX: cursorX - dragGrabDX, pxPerSecond: pxPerSecond)
        guard snappingEnabled else { return max(0, rawSeconds) }
        let target = Time.seconds(rawSeconds)
        let thresholdSeconds = pxPerSecond > 0 ? Double(8.0 / pxPerSecond) : 0
        let snapped = Snapping.snap(target, candidates: snapCandidates(), threshold: Time.seconds(thresholdSeconds))
        return max(0, snapped.seconds)
    }

    private func snapCandidates() -> [Time] {
        var out: [Time] = [Time.zero, Time.seconds(playheadSeconds)]
        for p in placed where p.clipID != dragClipID {
            out.append(p.absStart)
            out.append(p.absStart + p.duration)
        }
        return out
    }
}
