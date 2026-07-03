import AppKit

/// 主轴 gap(灰色占位)的交互:像 clip 一样可选中 / 修剪边缘(改时长)/ 拖动(改位置)/ 删除。
extension TimelineContentView {

    /// 计算主轴各 gap 的屏幕矩形(lane 0)+ id + 绝对起点秒。
    func gapRects() -> [(id: GapID, rect: NSRect, startSec: Double, durSec: Double)] {
        let y = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                          laneHeight: laneH, laneGap: Self.laneGap,
                                          contentHeight: bounds.height)
        var out: [(GapID, NSRect, Double, Double)] = []
        var acc = Time.zero
        for el in sequence.spine {
            if case .gap(let id, let d) = el {
                let x = TimelineGeometry.x(forSeconds: acc.seconds, pxPerSecond: pxPerSecond)
                let w = max(2, TimelineGeometry.x(forSeconds: d.seconds, pxPerSecond: pxPerSecond))
                out.append((id, NSRect(x: x, y: y, width: w, height: laneH), acc.seconds, d.seconds))
            }
            acc = acc + el.duration
        }
        return out
    }

    /// mouseDown 时检查 gap 命中(select / trim / position 工具)。返回 true 表示已处理。
    func gapMouseDown(at pt: NSPoint) -> Bool {
        guard currentTool == .select || currentTool == .trim || currentTool == .position else { return false }
        for g in gapRects() {
            guard pt.y >= g.rect.minY, pt.y <= g.rect.maxY,
                  pt.x >= g.rect.minX - Self.edgeHitPx, pt.x <= g.rect.maxX + Self.edgeHitPx else { continue }
            dispatch?(.selectGap(g.id))
            // 边缘 → 修剪时长;中间 → 拖动移动
            if abs(pt.x - g.rect.maxX) <= Self.edgeHitPx {
                gapTrim = (g.id, .tail, g.startSec)
            } else if abs(pt.x - g.rect.minX) <= Self.edgeHitPx {
                gapTrim = (g.id, .head, g.startSec)
            } else {
                dragGapID = g.id
                dragGapGrabDX = pt.x - g.rect.minX
                dragStartPoint = pt
                dragCurrentPoint = pt
            }
            return true
        }
        return false
    }

    /// mouseDragged 时处理 gap 修剪 / 拖动。返回 true 表示已处理。
    func gapMouseDragged(at pt: NSPoint) -> Bool {
        if let gt = gapTrim {
            let cursorSec = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
            ensureInteractive()   // gap 修剪:整段合成一次 undo
            if gt.edge == .tail {
                let newDur = max(0.04, cursorSec - gt.startSec)   // 尾边 → 新时长 = 光标 − 起点
                dispatch?(.setGapDurationByID(gt.gapID, Time.seconds(newDur)))
            } else {
                // 头边:光标右移则缩短(起点后移),保持尾不动 → 新时长 = 原尾 − 光标
                if let g = gapRects().first(where: { $0.id == gt.gapID }) {
                    let tailSec = g.startSec + g.durSec
                    let newDur = max(0.04, tailSec - cursorSec)
                    dispatch?(.setGapDurationByID(gt.gapID, Time.seconds(newDur)))
                }
            }
            return true
        }
        if let id = dragGapID {
            dragCurrentPoint = pt
            if let start = dragStartPoint, hypot(pt.x - start.x, pt.y - start.y) <= Self.dragThresholdPx { return true }
            let raw = max(0, TimelineGeometry.seconds(forX: pt.x - dragGapGrabDX, pxPerSecond: pxPerSecond))
            ensureInteractive()   // gap 拖动:整段合成一次 undo
            dispatch?(.moveGap(id, time: Time.seconds(raw)))
            return true
        }
        return false
    }

    /// mouseUp 清 gap 拖动状态。
    func gapMouseUp() {
        gapTrim = nil; dragGapID = nil
    }

    /// 光标:gap 边缘 → 双箭头。
    func addGapCursorRects() {
        guard currentTool == .select else { return }
        for g in gapRects() {
            let tail = NSRect(x: g.rect.maxX - Self.edgeHitPx, y: g.rect.minY, width: Self.edgeHitPx * 2, height: g.rect.height)
            let head = NSRect(x: g.rect.minX - Self.edgeHitPx, y: g.rect.minY, width: Self.edgeHitPx * 2, height: g.rect.height)
            addCursorRect(tail, cursor: .resizeLeftRight)
            addCursorRect(head, cursor: .resizeLeftRight)
        }
    }
}
