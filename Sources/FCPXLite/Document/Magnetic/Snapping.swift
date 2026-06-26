import Foundation

/// 纯函数吸附。threshold 由画布把"像素阈值 ÷ 缩放"换算成时间传入;引擎不碰像素。
enum Snapping {
    static func snap(_ t: Time, candidates: [Time], threshold: Time) -> Time {
        var best: Time? = nil
        var bestDist = threshold
        for c in candidates {
            let dist = c >= t ? (c - t) : (t - c)
            if dist < bestDist || (dist == bestDist && (best == nil || c < best!)) {
                if dist <= threshold {
                    bestDist = dist
                    best = c
                }
            }
        }
        return best ?? t
    }
}
