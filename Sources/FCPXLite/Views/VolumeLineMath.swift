import Foundation

/// 音量 level 线的纯数学(无 view 依赖,可单测)。
/// volume 域 0–2;timeline 上音量关键帧按时间线性插值。
enum VolumeLineMath {
    /// 给定关键帧(已按 time 排序与否均可)与片段总秒数,求 atSeconds 处的插值音量。
    /// 无关键帧 → 返回 baseVolume;首帧之前/末帧之后 → 保持端点值;之间 → 线性插值。
    static func interpolatedVolume(keyframes: [VolumeKeyframe], durationSecs: Double,
                                   atSeconds t: Double, baseVolume: Double) -> Double {
        let sorted = keyframes.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else { return baseVolume }
        if t <= first.time.seconds { return first.value }
        if t >= last.time.seconds { return last.value }
        for i in 0..<(sorted.count - 1) {
            let k0 = sorted[i], k1 = sorted[i + 1]
            if t >= k0.time.seconds && t <= k1.time.seconds {
                let span = k1.time.seconds - k0.time.seconds
                guard span > 0 else { return k0.value }
                let alpha = (t - k0.time.seconds) / span
                return k0.value + alpha * (k1.value - k0.value)
            }
        }
        return first.value
    }

    /// volume(0–2) → y(在 region 内,isFlipped: maxY=底=音量0,minY=顶=音量2)。
    static func volumeToY(volume: Double, regionMaxY: CGFloat, regionHeight: CGFloat) -> CGFloat {
        let clamped = max(0, min(2, volume))
        return regionMaxY - CGFloat(clamped / 2.0) * regionHeight
    }

    /// y → volume(0–2),clamp。
    static func yToVolume(y: CGFloat, regionMaxY: CGFloat, regionHeight: CGFloat) -> Double {
        guard regionHeight > 0 else { return 0 }
        let frac = Double((regionMaxY - y) / regionHeight)
        return max(0, min(2, frac * 2.0))
    }
}
