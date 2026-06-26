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

    /// 车道(lane)→ 该车道行的 y 顶部坐标(在 isFlipped 坐标系下,y 向下增长)。
    /// 布局:顶部 rulerHeight 留给标尺;lane 0(主轴)位于 baseline 行;
    /// lane n>0 在主轴【上方】(y 更小),lane n<0 在主轴【下方】(y 更大)。
    /// baselineTop = rulerHeight + maxPositiveLanes * (laneHeight + laneGap)。
    static func laneTopY(lane: Int,
                         rulerHeight: CGFloat,
                         laneHeight: CGFloat,
                         laneGap: CGFloat,
                         maxPositiveLanes: Int) -> CGFloat {
        let baselineTop = rulerHeight + CGFloat(maxPositiveLanes) * (laneHeight + laneGap)
        return baselineTop - CGFloat(lane) * (laneHeight + laneGap)
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
