import AppKit

/// TimelineContentView 鼠标交互,按当前工具分支:
/// - select:拖片段 → relocate(磁吸)
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

    // MARK: - mouseDown

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
        let inRuler = pt.y < Self.rulerHeight

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
            if !inRuler, let p = hitTestClip(at: pt) {
                dragClipID = p.clipID
                let clipStartX = TimelineGeometry.x(forSeconds: p.absStart.seconds, pxPerSecond: pxPerSecond)
                dragGrabDX = pt.x - clipStartX
                dragStartPoint = pt
                dragCurrentPoint = pt
                dispatch?(.selectClip(p.clipID))
                return
            }
            dragClipID = nil
            dispatch?(.setPlayhead(Time.seconds(t)))
        }
    }

    // MARK: - mouseDragged

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

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
        // 修剪工具:实时 trim
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
        // 片段拖动:更新 ghost
        if dragClipID != nil {
            dragCurrentPoint = pt
            needsDisplay = true
            return
        }
        // 空白擦洗播放头
        dispatch?(.setPlayhead(Time.seconds(TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond))))
    }

    // MARK: - mouseUp

    override func mouseUp(with event: NSEvent) {
        defer {
            dragClipID = nil; dragStartPoint = nil; dragCurrentPoint = nil
            trimDrag = nil; handLastX = nil; zoomStartX = nil
            needsDisplay = true
        }
        guard let id = dragClipID else { return }
        let pt = convert(event.locationInWindow, from: nil)

        if let start = dragStartPoint {
            let moved = hypot(pt.x - start.x, pt.y - start.y)
            if moved <= Self.dragThresholdPx { return }   // 微移视为点选
        }

        let lane = TimelineGeometry.lane(forY: pt.y, rulerHeight: Self.rulerHeight,
                                         laneHeight: laneH, laneGap: Self.laneGap,
                                         contentHeight: bounds.height)
        if currentTool == .position {
            // 位置工具:不吸附 + 原处留 gap(仅当落回主轴 lane 0)。
            let raw = max(0, TimelineGeometry.seconds(forX: pt.x - dragGrabDX, pxPerSecond: pxPerSecond))
            if lane == 0 {
                dispatch?(.positionMove(id, time: Time.seconds(raw)))
            } else {
                dispatch?(.relocateClip(id, lane: lane, time: Time.seconds(raw)))
            }
        } else {
            // select:吸附 + 磁性 relocate
            let snapped = snappedTargetSeconds(forCursorX: pt.x)
            dispatch?(.relocateClip(id, lane: lane, time: Time.seconds(snapped)))
        }
    }

    // MARK: - 光标(随工具)

    override func resetCursorRects() {
        let cursor: NSCursor
        switch currentTool {
        case .hand:  cursor = .openHand
        case .zoom:  cursor = .crosshair
        case .trim:  cursor = .resizeLeftRight
        default:     cursor = .arrow
        }
        addCursorRect(bounds, cursor: cursor)
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
