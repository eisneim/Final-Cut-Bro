// Sources/FCPXLite/Engine/Composition/CoreImageCompositor.swift
import AVFoundation
import CoreImage

/// 自研视频合成器:逐帧用 Core Image 把多轨按 z-order 合成,每层套几何矩阵+不透明度(+后续滤镜)。
/// 替换 AVMutableVideoCompositionLayerInstruction 路径,以便挂 per-clip CIFilter 特效。
final class CoreImageCompositor: NSObject, AVVideoCompositing {
    private var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let renderQueue = DispatchQueue(label: "fcpxlite.compositor")

    var sourcePixelBufferAttributes: [String: Any]? =
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    var requiredPixelBufferAttributesForRenderContext: [String: Any] =
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            guard let instruction = request.videoCompositionInstruction as? CompositorInstruction,
                  let dest = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "compositor", code: -1)); return
            }
            // 底→顶叠加。空层 → 透明黑底。
            var acc: CIImage = CIImage(color: .clear).cropped(
                to: CGRect(origin: .zero, size: request.renderContext.size))
            for layer in instruction.layers {
                guard let pb = request.sourceFrame(byTrackID: layer.trackID) else { continue }
                var img = CIImage(cvPixelBuffer: pb).transformed(by: layer.transform)
                // 不透明度:乘 alpha
                if layer.opacity < 1 {
                    if let f = CIFilter(name: "CIColorMatrix") {
                        f.setValue(img, forKey: kCIInputImageKey)
                        f.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity)), forKey: "inputAVector")
                        img = f.outputImage ?? img
                    }
                }
                // (Task 4 在此插入 effects 滤镜链)
                acc = img.composited(over: acc)
            }
            self.ciContext.render(acc, to: dest)
            request.finish(withComposedVideoFrame: dest)
        }
    }
}
