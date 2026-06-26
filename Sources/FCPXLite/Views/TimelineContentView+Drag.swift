import AppKit

/// TimelineContentView 的鼠标交互:选择 / 拖动片段换轨换位 / 切割 / 擦洗播放头。
/// 拖动语义:按下命中片段 → 记录抓取偏移并选中;移动超过阈值 → 进入"真拖动",
/// 画 ghost(x 吸附到附近片段边/播放头/0,lane 由光标 y 决定);抬起 → relocate 到
/// (目标 lane, 吸附后时间)。Blade 工具仍是切割;空白/标尺仍是擦洗播放头。
extension TimelineContentView {

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
        let inRuler = pt.y < Self.rulerHeight

        // Blade 工具:命中片段即切割,不进入拖动。
        if currentTool == .blade, !inRuler, let p = hitTestClip(at: pt) {
            if let spineIdx = TimelineGeometry.spineIndex(ofClipID: p.clipID, in: sequence) {
                let localT = max(0, t - p.absStart.seconds)
                dispatch?(.blade(at: spineIdx, localTime: Time.seconds(localT)))
            }
            dragClipID = nil
            return
        }

        // Select / Position 工具:命中片段 → 准备拖动 + 选中。
        if !inRuler, let p = hitTestClip(at: pt) {
            dragClipID = p.clipID
            let clipStartX = TimelineGeometry.x(forSeconds: p.absStart.seconds, pxPerSecond: pxPerSecond)
            dragGrabDX = pt.x - clipStartX
            dragStartPoint = pt
            dragCurrentPoint = pt
            dispatch?(.selectClip(p.clipID))
            return
        }

        // 空白区或标尺 → 移动播放头(并确保不在拖动态)。
        dragClipID = nil
        dispatch?(.setPlayhead(Time.seconds(t)))
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if dragClipID != nil {
            // 拖动片段:更新 ghost。
            dragCurrentPoint = pt
            needsDisplay = true
            return
        }
        // 否则擦洗播放头。
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
        dispatch?(.setPlayhead(Time.seconds(t)))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            // 拖动态总是清掉,避免残留 ghost。
            dragClipID = nil
            dragStartPoint = nil
            dragCurrentPoint = nil
            needsDisplay = true
        }
        guard let id = dragClipID else { return }

        let pt = convert(event.locationInWindow, from: nil)

        // 位移过小 → 视为单纯点选,不 relocate(避免误微移)。
        if let start = dragStartPoint {
            let moved = hypot(pt.x - start.x, pt.y - start.y)
            if moved <= Self.dragThresholdPx { return }
        }

        let snappedSeconds = snappedTargetSeconds(forCursorX: pt.x)
        let lane = TimelineGeometry.lane(forY: pt.y,
                                         rulerHeight: Self.rulerHeight,
                                         laneHeight: Self.laneHeight,
                                         laneGap: Self.laneGap,
                                         contentHeight: bounds.height)
        dispatch?(.relocateClip(id, lane: lane, time: Time.seconds(snappedSeconds)))
    }

    // MARK: - 吸附

    /// 目标起点时间(秒):cursorX − 抓取偏移 → 秒,再吸附到附近候选边(8px 阈值)。
    func snappedTargetSeconds(forCursorX cursorX: CGFloat) -> Double {
        let rawSeconds = TimelineGeometry.seconds(forX: cursorX - dragGrabDX, pxPerSecond: pxPerSecond)
        let target = Time.seconds(rawSeconds)
        let thresholdSeconds = pxPerSecond > 0 ? Double(8.0 / pxPerSecond) : 0
        let threshold = Time.seconds(thresholdSeconds)
        let snapped = Snapping.snap(target, candidates: snapCandidates(), threshold: threshold)
        return max(0, snapped.seconds)
    }

    /// 吸附候选:除被拖片段外每个片段的起点与终点 + 播放头 + 0。
    private func snapCandidates() -> [Time] {
        var out: [Time] = [Time.zero, Time.seconds(playheadSeconds)]
        for p in placed where p.clipID != dragClipID {
            out.append(p.absStart)
            out.append(p.absStart + p.duration)
        }
        return out
    }
}
