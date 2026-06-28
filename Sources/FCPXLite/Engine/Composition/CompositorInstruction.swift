// Sources/FCPXLite/Engine/Composition/CompositorInstruction.swift
import AVFoundation
import CoreImage

/// 一层的合成数据:源轨 ID + 完整几何矩阵(源像素→renderSize)+ 不透明度 + 特效链。
final class CompositorLayer: NSObject {
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let opacity: Float
    let effects: [Effect]
    init(trackID: CMPersistentTrackID, transform: CGAffineTransform, opacity: Float, effects: [Effect]) {
        self.trackID = trackID; self.transform = transform; self.opacity = opacity; self.effects = effects
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
        self.requiredSourceTrackIDs = layers.map { NSNumber(value: $0.trackID) }
    }
}
