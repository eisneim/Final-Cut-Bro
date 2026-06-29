import Foundation
import CoreGraphics

/// 变换关键帧的纯数学(无 view/合成依赖,可单测)。
/// 时间相对 clip 起点;位移/缩放/不透明度按时间线性插值。
/// 无关键帧 → 返回 base;首帧之前/末帧之后 → 保持端点值;之间 → 线性插值。
enum TransformKeyframeMath {

    struct Sample: Equatable {
        var position: CGPoint
        var scale: CGSize
        var opacity: Double
    }

    /// 求 atSeconds 处的插值。base = 无关键帧时的静态值(取自 clip.adjust)。
    static func sample(keyframes: [TransformKeyframe], atSeconds t: Double,
                       basePosition: CGPoint, baseScale: CGSize, baseOpacity: Double) -> Sample {
        let sorted = keyframes.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else {
            return Sample(position: basePosition, scale: baseScale, opacity: baseOpacity)
        }
        if t <= first.time.seconds { return sampleOf(first) }
        if t >= last.time.seconds { return sampleOf(last) }
        for i in 0..<(sorted.count - 1) {
            let k0 = sorted[i], k1 = sorted[i + 1]
            if t >= k0.time.seconds && t <= k1.time.seconds {
                let span = k1.time.seconds - k0.time.seconds
                guard span > 0 else { return sampleOf(k0) }
                let a = (t - k0.time.seconds) / span
                return Sample(
                    position: CGPoint(x: lerp(k0.position.x, k1.position.x, a),
                                      y: lerp(k0.position.y, k1.position.y, a)),
                    scale: CGSize(width: lerp(k0.scale.width, k1.scale.width, a),
                                  height: lerp(k0.scale.height, k1.scale.height, a)),
                    opacity: lerp(k0.opacity, k1.opacity, a))
            }
        }
        return sampleOf(first)
    }

    private static func sampleOf(_ k: TransformKeyframe) -> Sample {
        Sample(position: k.position, scale: k.scale, opacity: k.opacity)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}
