// Sources/FCPXLite/Engine/Composition/CompositorInstruction.swift
import AVFoundation
import CoreImage

/// 一层的合成数据:源轨 ID(图片层为 invalid)+ 可选静帧图 + 几何矩阵 + 不透明度 + 裁剪 + 特效链。
final class CompositorLayer: NSObject {
    let trackID: CMPersistentTrackID
    let image: CGImage?     // 非 nil = 图片静帧层(不从源轨取帧)
    let transform: CGAffineTransform
    let opacity: Float
    let crop: Crop
    let effects: [Effect]
    init(trackID: CMPersistentTrackID, image: CGImage? = nil, transform: CGAffineTransform, opacity: Float, crop: Crop, effects: [Effect]) {
        self.trackID = trackID; self.image = image; self.transform = transform; self.opacity = opacity
        self.crop = crop; self.effects = effects
    }
}

/// 自定义合成指令:某时间区间内活跃的层(layers 顺序=底→顶)。
final class CompositorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [CompositorLayer]
    init(timeRange: CMTimeRange, layers: [CompositorLayer]) {
        self.timeRange = timeRange; self.layers = layers
        // 只把真实源轨(图片层 trackID 无效)列为必需,避免 AVFoundation 等一个不存在的轨。
        let ids = layers.map { $0.trackID }.filter { $0 != kCMPersistentTrackID_Invalid }
        self.requiredSourceTrackIDs = ids.isEmpty ? nil : ids.map { NSNumber(value: $0) }
    }
}
