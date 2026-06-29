import Foundation
import CoreGraphics

/// 纯函数:时间线像素坐标 ↔ 主轴下标。无副作用,易于单元测试。
enum TimelineGeometry {

    /// 把时间线 x 像素换算成主轴插入下标。
    /// 落点 x 落在第几个 spine 元素中心之后 → 返回该下标。
    /// 算法: prefix-sum 主轴各元素时长;center = (accStart + dur/2) * pxPerSecond;
    ///       insertionIndex = 中心点在 x 左边的元素数量。
    static func insertionIndex(forX x: CGFloat, sequence: Sequence, pxPerSecond: CGFloat) -> Int {
        var accumulated: Double = 0
        var count = 0
        for element in sequence.spine {
            let dur = element.duration.seconds
            let center = (accumulated + dur / 2.0) * Double(pxPerSecond)
            if center < Double(x) {
                count += 1
            }
            accumulated += dur
        }
        return count
    }

    /// spine 第 index 个 clip 的下标(用于把 clipID 映射回 spine index 做删除)。
    /// 仅匹配主轴直接元素(非 connected child)。返回 nil 表示未找到。
    static func spineIndex(ofClipID id: ClipID, in sequence: Sequence) -> Int? {
        for (i, element) in sequence.spine.enumerated() {
            if case .clip(let c) = element, c.id == id {
                return i
            }
        }
        return nil
    }

    // MARK: - 画布坐标(纯几何,供 AppKit 画布与单元测试共用)

    /// 时间(秒)→ 时间线 x 像素。
    static func x(forSeconds seconds: Double, pxPerSecond: CGFloat) -> CGFloat {
        CGFloat(seconds) * pxPerSecond
    }

    /// 时间线 x 像素 → 时间(秒),clamp 到 ≥0。
    static func seconds(forX x: CGFloat, pxPerSecond: CGFloat) -> Double {
        guard pxPerSecond > 0 else { return 0 }
        return max(0, Double(x / pxPerSecond))
    }

    /// 交叉叠化转场标记的矩形:以接缝 seamX 为中心,宽 = crossfade 秒 × pxPerSecond,
    /// 跨接缝两侧各一半(夹最小宽,保证可见)。纯几何,供画布与单测共用。
    static func transitionRect(seamX: CGFloat, crossfadeSecs: Double, pxPerSecond: CGFloat,
                               laneY: CGFloat, laneHeight: CGFloat) -> CGRect {
        let w = max(6, CGFloat(crossfadeSecs) * pxPerSecond)
        return CGRect(x: seamX - w / 2, y: laneY, width: w, height: laneHeight)
    }

    /// 车道(lane)→ 该车道行的 y 顶部坐标(在 isFlipped 坐标系下,y 向下增长)。
    /// 布局:lane 0(主轴)在标尺下方可用区域【垂直居中】;
    /// lane n>0 连接片段在主轴【上方】(y 更小),lane n<0 在主轴【下方】(y 更大)。
    /// centerY = rulerHeight + (contentHeight - rulerHeight)/2;lane0Top = centerY - laneHeight/2;
    /// top = lane0Top - lane*(laneHeight+laneGap)。
    static func laneTopY(lane: Int,
                         rulerHeight: CGFloat,
                         laneHeight: CGFloat,
                         laneGap: CGFloat,
                         contentHeight: CGFloat) -> CGFloat {
        let centerY = rulerHeight + (contentHeight - rulerHeight) / 2
        let lane0Top = centerY - laneHeight / 2
        return lane0Top - CGFloat(lane) * (laneHeight + laneGap)
    }

    /// 逆运算:画布内某 y 落在哪个 lane 行(用于决定拖放目标 lane)。
    /// 以 lane 0 顶为基准,按行高+间距推算;round 到最近行。
    static func lane(forY y: CGFloat,
                     rulerHeight: CGFloat,
                     laneHeight: CGFloat,
                     laneGap: CGFloat,
                     contentHeight: CGFloat) -> Int {
        let step = laneHeight + laneGap
        guard step > 0 else { return 0 }
        let lane0Top = laneTopY(lane: 0, rulerHeight: rulerHeight, laneHeight: laneHeight,
                                laneGap: laneGap, contentHeight: contentHeight)
        // y = lane0Top - lane*step  →  lane = (lane0Top - y)/step
        // 对每行中心做最近取整:用行顶 +laneHeight/2 偏移使边界落在行间隙。
        let raw = (lane0Top + laneHeight / 2 - y) / step
        return Int(raw.rounded(.down))
    }

    /// 标尺刻度间隔(秒):选一个“好看”的秒数,使相邻标签 ≈ targetLabelPx 像素。
    /// 从 {1,2,5,10,15,30,60,120,300,600} 里挑第一个满足 spacing*px ≥ targetLabelPx 的;
    /// 都不够则用最大值。保证 pxPerSecond 任意时标签不挤成一团。
    static func tickIntervalSeconds(pxPerSecond: CGFloat, targetLabelPx: CGFloat = 80) -> Double {
        let candidates: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        for c in candidates where CGFloat(c) * pxPerSecond >= targetLabelPx {
            return c
        }
        return candidates.last!
    }
}
