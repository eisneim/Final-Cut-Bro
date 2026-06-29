// Sources/FCPXLite/Engine/Composition/CompositorInstruction.swift
import AVFoundation
import CoreImage

/// 一层的合成数据:源轨 ID(图片层为 invalid)+ 可选静帧图 + 几何矩阵 + 不透明度 + 裁剪 + 特效链。
/// 若带变换关键帧(transformKeyframes 非空),合成器按 request time 重算几何矩阵/不透明度实现动画;
/// 重算需要原始几何输入(natural/pref/renderSize/baseRotation/clipStart)。
final class CompositorLayer: NSObject {
    let trackID: CMPersistentTrackID
    let image: CGImage?     // 非 nil = 图片静帧层(不从源轨取帧)
    let transform: CGAffineTransform
    let opacity: Float
    let crop: Crop
    let effects: [Effect]
    // 动画载荷(transformKeyframes 为空 → 用上面的静态 transform/opacity)。
    let transformKeyframes: [TransformKeyframe]
    let clipStart: CMTime          // 该片段在时间线上的绝对起点(关键帧时间相对此)
    let natural: CGSize            // 源像素尺寸
    let pref: CGAffineTransform    // preferredTransform(方向)
    let renderSize: CGSize         // 画布尺寸
    let baseRotation: Double       // 静态旋转(关键帧不动旋转)

    init(trackID: CMPersistentTrackID, image: CGImage? = nil, transform: CGAffineTransform,
         opacity: Float, crop: Crop, effects: [Effect],
         transformKeyframes: [TransformKeyframe] = [], clipStart: CMTime = .zero,
         natural: CGSize = .zero, pref: CGAffineTransform = .identity,
         renderSize: CGSize = .zero, baseRotation: Double = 0) {
        self.trackID = trackID; self.image = image; self.transform = transform; self.opacity = opacity
        self.crop = crop; self.effects = effects
        self.transformKeyframes = transformKeyframes; self.clipStart = clipStart
        self.natural = natural; self.pref = pref; self.renderSize = renderSize
        self.baseRotation = baseRotation
    }
}

/// 自定义合成指令:某时间区间内活跃的层(layers 顺序=底→顶)。
final class CompositorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening: Bool
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [CompositorLayer]
    init(timeRange: CMTimeRange, layers: [CompositorLayer]) {
        self.timeRange = timeRange; self.layers = layers
        // 有变换关键帧 → 区间内逐帧插值,必须告诉 AVFoundation 内容随时间变化(否则可能只渲一帧)。
        self.containsTweening = layers.contains { !$0.transformKeyframes.isEmpty }
        // 只把真实源轨(图片层 trackID 无效)列为必需,避免 AVFoundation 等一个不存在的轨。
        let ids = layers.map { $0.trackID }.filter { $0 != kCMPersistentTrackID_Invalid }
        self.requiredSourceTrackIDs = ids.isEmpty ? nil : ids.map { NSNumber(value: $0) }
    }
}
