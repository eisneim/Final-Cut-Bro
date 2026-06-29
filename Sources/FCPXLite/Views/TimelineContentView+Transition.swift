import AppKit

/// 转场(交叉叠化)交互:点击选中、首尾边缘拖拽改时长、hover 显示光标。
/// 转场标记由 drawTransitions 画在带 crossfadeIn 的主轴片段【左接缝】处,宽=时长×px,跨缝居中。
extension TimelineContentView {

    /// 某主轴片段的转场标记矩形(无 crossfade 返回 nil)。
    func transitionRect(for p: Placed) -> CGRect? {
        guard p.lane == 0, let clip = clipByID(p.clipID), clip.crossfadeIn > .zero else { return nil }
        let laneY = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                              laneHeight: laneH, laneGap: Self.laneGap,
                                              contentHeight: bounds.height)
        let seamX = clipRect(p).minX
        return TimelineGeometry.transitionRect(seamX: seamX, crossfadeSecs: clip.crossfadeIn.seconds,
                                               pxPerSecond: pxPerSecond, laneY: laneY, laneHeight: laneH)
    }

    /// 命中转场:返回 (spine下标, 接缝x, 是否在边缘)。
    func transitionHit(at pt: NSPoint) -> (spineIndex: Int, seamX: CGFloat, atEdge: Bool)? {
        for p in placed where p.lane == 0 {
            guard let rect = transitionRect(for: p), rect.insetBy(dx: -3, dy: 0).contains(pt) else { continue }
            guard let si = TimelineGeometry.spineIndex(ofClipID: p.clipID, in: sequence) else { continue }
            let atEdge = abs(pt.x - rect.minX) <= Self.edgeHitPx || abs(pt.x - rect.maxX) <= Self.edgeHitPx
            return (si, rect.midX, atEdge)
        }
        return nil
    }

    /// mouseDown 拦截:点转场边缘→开始调宽;点转场身体→选中。返回 true 表示已处理。
    func transitionMouseDown(at pt: NSPoint) -> Bool {
        guard currentTool == .select || currentTool == .trim else { return false }
        guard let hit = transitionHit(at: pt) else { return false }
        guard case .clip(let c) = sequence.spine[hit.spineIndex] else { return false }
        dispatch?(.selectTransition(c.id))
        if hit.atEdge {
            transitionDrag = (clipIndex: hit.spineIndex, seamX: hit.seamX, startDur: c.crossfadeIn.seconds)
        }
        return true
    }

    /// mouseDragged 拦截:调转场时长。
    func transitionMouseDragged(at pt: NSPoint) -> Bool {
        guard let td = transitionDrag else { return false }
        // 拖任一边缘:时长 = 离接缝距离×2(标记居中)。夹在 [0.1, 相邻两片段较短时长]。
        let dist = abs(Double(pt.x - td.seamX)) / Double(pxPerSecond)
        var newDur = max(0.1, dist * 2)
        let spine = sequence.spine
        let prevDur = (td.clipIndex - 1 >= 0 && spine.indices.contains(td.clipIndex - 1))
            ? spine[td.clipIndex - 1].duration.seconds : newDur
        let thisDur = spine[td.clipIndex].duration.seconds
        newDur = min(newDur, min(prevDur, thisDur))
        dispatch?(.setCrossfade(at: td.clipIndex, duration: .seconds(newDur)))
        return true
    }

    func transitionMouseUp() { transitionDrag = nil }

    /// hover 光标:转场身体=指针,边缘=左右调整。
    func addTransitionCursorRects() {
        guard currentTool == .select || currentTool == .trim else { return }
        for p in placed where p.lane == 0 {
            guard let rect = transitionRect(for: p) else { continue }
            addCursorRect(NSRect(x: rect.minX - Self.edgeHitPx, y: rect.minY, width: Self.edgeHitPx * 2, height: rect.height), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: rect.maxX - Self.edgeHitPx, y: rect.minY, width: Self.edgeHitPx * 2, height: rect.height), cursor: .resizeLeftRight)
        }
    }
}
