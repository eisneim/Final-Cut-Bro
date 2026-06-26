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
}
