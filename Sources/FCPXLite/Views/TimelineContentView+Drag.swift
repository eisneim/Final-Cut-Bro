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

    /// 命中某【连接片段】(lane≠0,字幕/连接音频)的首/尾边缘,edgeHitPx 内。
    func connectedEdgeHit(at pt: NSPoint) -> (clipID: ClipID, edge: TrimEdge)? {
        for p in placed where p.lane != 0 {
            let r = clipRect(p)
            guard pt.y >= r.minY, pt.y <= r.maxY else { continue }
            if abs(pt.x - r.minX) <= Self.edgeHitPx { return (p.clipID, .head) }
            if abs(pt.x - r.maxX) <= Self.edgeHitPx { return (p.clipID, .tail) }
        }
        return nil
    }

    /// 在各宿主的 connected 列表里按 id 找连接片段值。
    func connectedClipValue(_ id: ClipID) -> Clip? {
        for el in sequence.spine {
            if case .clip(let c) = el {
                if let child = c.connected.first(where: { $0.id == id }) { return child }
            }
        }
        return nil
    }

    /// 命中某 clip 边缘的 x 坐标(head=clip 左缘,tail=clip 右缘)。供抓取偏移用。
    func trimEdgeX(_ clipID: ClipID, _ edge: TrimEdge) -> CGFloat {
        guard let p = placed.first(where: { $0.clipID == clipID }) else { return 0 }
        let r = clipRect(p)
        return edge == .head ? r.minX : r.maxX
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
                let cutAbs = snapSeconds(t)   // 切割点吸附到邻近编辑点/光标
                dispatch?(.blade(at: s, localTime: Time.seconds(max(0, cutAbs - p.absStart.seconds))))
            }
            return
        case .trim:
            if !inRuler, transitionMouseDown(at: pt) { return }   // 转场优先(选中/调宽)
            if let e = edgeHit(at: pt) {
                trimDrag = (e.clipID, e.index, e.edge, pt.x - trimEdgeX(e.clipID, e.edge))
                dispatch?(.selectClip(e.clipID))
                return
            }
            if let ce = connectedEdgeHit(at: pt) {   // 连接片段(字幕/音乐)首尾 → trim 时长
                connTrimDrag = (ce.clipID, ce.edge, pt.x - trimEdgeX(ce.clipID, ce.edge))
                dispatch?(.selectClip(ce.clipID))
                return
            }
            // 中段(非边缘):slip(默认)/ slide(⌥)。命中主轴 clip 即开始。
            if !inRuler, let p = hitTestClip(at: pt), p.lane == 0,
               let idx = TimelineGeometry.spineIndex(ofClipID: p.clipID, in: sequence) {
                let isSlide = event.modifierFlags.contains(.option)
                slipDrag = (index: idx, startX: pt.x, isSlide: isSlide, origin: sequence, firstTick: true)
                dispatch?(.selectClip(p.clipID))
                return
            }
            // 修剪工具点空白也移播放头
            dispatch?(.setPlayhead(Time.seconds(t)))
            return
        case .select, .position, .range:
            if !inRuler {
                // 转场标记最优先(小而具体的区域,点它就是选/调转场,别被音量线/clip 抢走)。
                if transitionMouseDown(at: pt) { return }
                // Volume level 线拦截(select 工具)
                if volumeMouseDown(with: event, at: pt) { return }
                // gap(灰条)最优先:在 gap 上(含边界)就处理 gap,避免被相邻 clip 的 trim/roll 抢走。
                if gapMouseDown(at: pt) { return }
                // 1. roll hit(两片段切点)
                if currentTool == .select, let roll = rollHit(at: pt) {
                    rollDrag = (roll.leftIndex, roll.rightIndex,
                                roll.leftClipID, roll.rightClipID, pt.x)
                    dispatch?(.selectClip(roll.leftClipID))
                    return
                }
                // 2. 边缘 trim(select 工具也支持)
                if currentTool == .select, let e = edgeHit(at: pt) {
                    trimDrag = (e.clipID, e.index, e.edge, pt.x - trimEdgeX(e.clipID, e.edge))
                    dispatch?(.selectClip(e.clipID))
                    return
                }
                // 2b. 连接片段(字幕/音乐)边缘 trim(在拖动前判定,抓边=改时长)
                if currentTool == .select, let ce = connectedEdgeHit(at: pt) {
                    connTrimDrag = (ce.clipID, ce.edge, pt.x - trimEdgeX(ce.clipID, ce.edge))
                    dispatch?(.selectClip(ce.clipID))
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
            // 兜底(未命中任何片段/gap/边缘):决定是擦洗播放头还是框选。
            // 用户要求:只有 ruler 上、或 hover 到播放头线上拖才移播放头;空白处拖 = 框选。
            if inRuler || currentTool == .position {
                dispatch?(.setPlayhead(Time.seconds(t)))            // ruler / 位置工具:擦洗播放头
            } else if nearPlayhead(pt) {
                scrubbingPlayhead = true
                dispatch?(.setPlayhead(Time.seconds(t)))            // 播放头线上:擦洗
            } else {
                dispatch?(.setPlayhead(Time.seconds(t)))            // 空白:立即移播放头(响应点击)
                marqueeStart = pt; marqueeCurrent = pt              // 同时准备框选(拖动才生效)
            }
        }
    }

    /// pt.x 是否落在播放头竖线附近(±4px),用于区分"擦洗播放头"与"框选"。
    func nearPlayhead(_ pt: NSPoint) -> Bool {
        let x = TimelineGeometry.x(forSeconds: playheadSeconds, pxPerSecond: pxPerSecond)
        return abs(pt.x - x) <= 4
    }

    /// 框选矩形(两对角点 → NSRect)命中的片段 id(主轴+连接+标题,矩形相交即选中)。
    func clipsInMarquee(_ rect: NSRect) -> [ClipID] {
        placed.filter { clipRect($0).intersects(rect) }.map { $0.clipID }
    }

    // MARK: - mouseDragged

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        // 框选进行中:更新矩形,实时选中框内片段。
        if let start = marqueeStart {
            marqueeCurrent = pt
            let rect = NSRect(x: min(start.x, pt.x), y: min(start.y, pt.y),
                              width: abs(pt.x - start.x), height: abs(pt.y - start.y))
            let ids = clipsInMarquee(rect)
            dispatch?(.selectClips(Set(ids), anchor: ids.first))
            needsDisplay = true
            return
        }
        // 播放头线擦洗
        if scrubbingPlayhead {
            dispatch?(.setPlayhead(Time.seconds(TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond))))
            return
        }

        // Volume level 线拖拽优先
        if volumeMouseDragged(with: event, at: pt) { return }
        // 转场调宽
        if transitionMouseDragged(at: pt) { return }
        // gap 修剪/拖动
        if gapMouseDragged(at: pt) { return }

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
        // Slip/Slide:修剪工具拖片段中段。每 tick 从拖拽起点序列按总位移重算(幂等,不累积)。
        if var sd = slipDrag {
            let deltaSec = Double(pt.x - sd.startX) / Double(pxPerSecond)
            let origin = sd.origin
            let idx = sd.index
            guard origin.spine.indices.contains(idx), case .clip(let c) = origin.spine[idx] else {
                slipDrag = nil; return
            }
            let first = sd.firstTick
            if sd.isSlide {
                // slide:正 delta(右)→ 前片段延长、后片段头部裁掉。需前后片段的素材时长。
                guard origin.spine.indices.contains(idx - 1), origin.spine.indices.contains(idx + 1),
                      case .clip(let prev) = origin.spine[idx - 1],
                      case .clip(let next) = origin.spine[idx + 1] else { return }
                let prevAD = assetDuration(of: prev), nextAD = assetDuration(of: next)
                dragEdit?(first) { _ in
                    Mutations.slide(at: idx, delta: .seconds(deltaSec),
                                    prevAssetDuration: prevAD, nextAssetDuration: nextAD, in: origin)
                }
            } else {
                // slip:正 deltaSec(右拖)→ sourceIn 减少(显示更早画面,内容随光标右移),贴近 FCP 习惯。
                let assetDur = assetDuration(of: c)
                dragEdit?(first) { _ in
                    Mutations.slip(at: idx, delta: .seconds(-deltaSec), assetDuration: assetDur, in: origin)
                }
            }
            sd.firstTick = false
            slipDrag = sd
            return
        }
        // 修剪工具 / select 工具边缘 trim:实时 trim
        if let td = trimDrag {
            guard let (clip, _) = spineClipAndIndex(td.clipID) else { return }
            let clipStartSec = (placed.first { $0.clipID == td.clipID }?.absStart.seconds) ?? 0
            // 减去抓取偏移 → 边缘精确停在"指哪打哪"处(不跳到光标中心),完全跟手。
            let cursorSec = snapSeconds(TimelineGeometry.seconds(forX: pt.x - td.grabDX, pxPerSecond: pxPerSecond))
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
        // 连接片段(字幕/音乐)边缘 trim:改 offset/sourceIn/duration(不动主轴)。
        if let cd = connTrimDrag,
           let p = placed.first(where: { $0.clipID == cd.clipID }),
           let clip = connectedClipValue(cd.clipID) {
            let absStart = p.absStart.seconds
            let isMedia = clip.title == nil
            let cursorSec = snapSeconds(TimelineGeometry.seconds(forX: pt.x - cd.grabDX, pxPerSecond: pxPerSecond))
            if cd.edge == .tail {
                var newDur = max(0.1, cursorSec - absStart)
                if isMedia {   // 媒体:不超出素材尾
                    let maxDur = max(0.1, assetDuration(of: clip).seconds - clip.sourceIn.seconds)
                    newDur = min(newDur, maxDur)
                }
                dispatch?(.setConnectedTiming(cd.clipID, offset: nil, sourceIn: nil, duration: .seconds(newDur)))
            } else {
                let deltaIn = cursorSec - absStart               // 正=向右收头
                let newOffset = max(0, clip.offset.seconds + deltaIn)
                let newDur = max(0.1, clip.duration.seconds - deltaIn)
                let newSourceIn = isMedia ? max(0, clip.sourceIn.seconds + deltaIn) : nil
                dispatch?(.setConnectedTiming(cd.clipID, offset: .seconds(newOffset),
                                              sourceIn: newSourceIn.map { .seconds($0) },
                                              duration: .seconds(newDur)))
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
            let dragged = placed.first { $0.clipID == id }
            if dragged?.isConnected == true {
                // 连接片段(字幕/音乐):平滑重定位 —— 用请求 lane(0 则贴回原侧 ±1),永不变主轴、不跳。
                let snapped = snappedTargetSeconds(forCursorX: pt.x)
                let laneForDrag = lane != 0 ? lane : ((dragged?.lane ?? 1) >= 0 ? 1 : -1)
                dispatch?(.relocateConnected(id, lane: laneForDrag, time: Time.seconds(snapped)))
            } else if currentTool == .position {
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
        // 框选收尾:纯点击空白(位移极小)= 取消选择;有拖动则选中集已在 mouseDragged 设好。
        if let start = marqueeStart {
            let pt = convert(event.locationInWindow, from: nil)
            if hypot(pt.x - start.x, pt.y - start.y) < Self.dragThresholdPx {
                dispatch?(.selectClips([], anchor: nil))
            }
            marqueeStart = nil; marqueeCurrent = nil
            needsDisplay = true
            return
        }
        scrubbingPlayhead = false
        volumeMouseUp()
        gapMouseUp()
        transitionMouseUp()
        // 位置工具:松手时一次性 commit positionMove(源处留 gap,目标落点 = 光标,不吸附)。
        if currentTool == .position, let id = dragClipID, let cur = dragCurrentPoint,
           let start = dragStartPoint, hypot(cur.x - start.x, cur.y - start.y) > Self.dragThresholdPx {
            let lane = TimelineGeometry.lane(forY: cur.y, rulerHeight: Self.rulerHeight,
                                             laneHeight: laneH, laneGap: Self.laneGap,
                                             contentHeight: bounds.height)
            let raw = max(0, TimelineGeometry.seconds(forX: cur.x - dragGrabDX, pxPerSecond: pxPerSecond))
            if lane == 0 { dispatch?(.positionMove(id, time: Time.seconds(raw))) }
            else { dispatch?(.positionMoveToLane(id, lane: lane, time: Time.seconds(raw))) }   // 向上拖:源处留灰条
        }
        // 其余工具的片段拖动已在 mouseDragged 中实时完成(所见即所得),这里只清状态。
        dragClipID = nil; dragStartPoint = nil; dragCurrentPoint = nil
        trimDrag = nil; rollDrag = nil; handLastX = nil; zoomStartX = nil
        slipDrag = nil; connTrimDrag = nil
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
            addGapCursorRects()
            addTransitionCursorRects()
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
            if lane0.count >= 2 {
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
            }
            // 连接片段(字幕/音乐)首尾边缘 → 双箭头(可 trim 时长)
            for p in placed where p.lane != 0 {
                let r = clipRect(p)
                addCursorRect(NSRect(x: r.minX - Self.edgeHitPx, y: r.minY, width: Self.edgeHitPx * 2, height: r.height), cursor: .resizeLeftRight)
                addCursorRect(NSRect(x: r.maxX - Self.edgeHitPx, y: r.minY, width: Self.edgeHitPx * 2, height: r.height), cursor: .resizeLeftRight)
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

    /// 把一个【绝对时间(秒)】吸附到邻近编辑点(片段首尾/播放头/0),阈值=几像素。snapping 关时原样返回。
    /// 供 blade(切割吸光标)、trim(修剪边吸邻近边)共用。
    func snapSeconds(_ rawSeconds: Double) -> Double {
        guard snappingEnabled else { return max(0, rawSeconds) }
        let threshold = pxPerSecond > 0 ? Double(8.0 / pxPerSecond) : 0
        let snapped = Snapping.snap(Time.seconds(rawSeconds), candidates: snapCandidates(),
                                    threshold: Time.seconds(threshold))
        return max(0, snapped.seconds)
    }
}
