import AppKit

/// TimelineContentView 光标(NSTrackingArea + cursorUpdate)、skimming 命中、吸附 —— 从 +Drag 拆出。
extension TimelineContentView {
    // MARK: - 光标(随工具 + 边缘热区)—— 用 NSTrackingArea + cursorUpdate/mouseMoved,
    // 而非 addCursorRect(后者在 NSScrollView 的 document view 里不可靠,是"切工具光标不变"的根因)。

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: .zero,
                                options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursorForPoint(convert(event.locationInWindow, from: nil)).set()
    }
    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        cursorForPoint(pt).set()
        updateSkim(at: pt)
    }
    /// 鼠标离开时间轴:清除 skimmer,预览回到播放头。
    override func mouseExited(with event: NSEvent) {
        if let old = skimmerX {
            skimmerX = nil
            setNeedsDisplay(NSRect(x: old - 5, y: 0, width: 10, height: bounds.height))
        }
        if timelineSkimming { dispatch?(.setTimelineSkim(nil)) }
    }

    /// skimming 开启时:把 skimmer 移到光标 x,定向失效(只重画旧+新窄条),并驱动预览 seek 到该时间。
    func updateSkim(at pt: NSPoint) {
        guard timelineSkimming, !isPlaying else { return }   // 播放优先:播放中不 skim
        let sec = max(0, TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond))
        let newX = TimelineGeometry.x(forSeconds: sec, pxPerSecond: pxPerSecond)
        if let old = skimmerX, abs(old - newX) < 0.5 { return }   // 没动到下一个像素,跳过
        let old = skimmerX
        skimmerX = newX
        let lo = min(old ?? newX, newX) - 5
        let hi = max(old ?? newX, newX) + 5
        setNeedsDisplay(NSRect(x: lo, y: 0, width: hi - lo, height: bounds.height))
        dispatch?(.setTimelineSkim(sec))
    }

    /// 按当前工具 + 光标位置决定光标。
    func cursorForPoint(_ pt: NSPoint) -> NSCursor {
        switch currentTool {
        case .hand:     return .openHand
        case .zoom:     return TimelineCursors.zoom          // 放大镜
        case .trim:     return .resizeLeftRight
        case .blade:    return TimelineCursors.blade         // 剃刀
        case .position: return TimelineCursors.move          // 四向移动
        case .range:    return TimelineCursors.range         // [|]
        case .select:
            // 主轴/连接片段边缘、roll 切点 → 双箭头(可 trim);否则箭头。
            if edgeHit(at: pt) != nil || connectedEdgeHit(at: pt) != nil || rollHit(at: pt) != nil {
                return .resizeLeftRight
            }
            return .arrow
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
