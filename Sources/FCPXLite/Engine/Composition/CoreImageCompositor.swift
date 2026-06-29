// Sources/FCPXLite/Engine/Composition/CoreImageCompositor.swift
import AVFoundation
import CoreImage

/// 自研视频合成器:逐帧用 Core Image 把多轨按 z-order 合成,每层套几何矩阵+不透明度(+后续滤镜)。
/// 替换 AVMutableVideoCompositionLayerInstruction 路径,以便挂 per-clip CIFilter 特效。
///
/// 坐标系:`CIImage(cvPixelBuffer:)` 是 y-up(picture-top 在高 y),而 `fullTransform` 的矩阵按
/// 左上原点 y-down 作图(crop.top 减低 y 行、position.y 向下为正)。直接套矩阵会让垂直语义反转
/// (crop.top 裁掉底边、position.y 反向)。故:先把源翻成左上原点 → 套矩阵 → 合成 → 整体翻回 y-up 再渲染。
final class CoreImageCompositor: NSObject, AVVideoCompositing {
    // 不可变:CIContext 与渲染尺寸无关,创建一次即可,避免跨线程重建引发的数据竞争。
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let renderQueue = DispatchQueue(label: "fcpxlite.compositor")

    var sourcePixelBufferAttributes: [String: Any]? =
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    var requiredPixelBufferAttributesForRenderContext: [String: Any] =
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // CIContext 与尺寸无关,无需重建(重建还会与 startRequest 的读取形成数据竞争)。
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            guard let instruction = request.videoCompositionInstruction as? CompositorInstruction,
                  let dest = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "compositor", code: -1)); return
            }
            let renderSize = request.renderContext.size
            // 累加器在【左上原点 y-down】空间合成(与 fullTransform 的作图约定一致)。底→顶叠加。
            var acc: CIImage = CIImage(color: .clear).cropped(
                to: CGRect(origin: .zero, size: renderSize))
            for layer in instruction.layers {
                let src: CIImage
                if let cg = layer.image {
                    src = CIImage(cgImage: cg)                       // 图片静帧层
                } else if let pb = request.sourceFrame(byTrackID: layer.trackID) {
                    src = CIImage(cvPixelBuffer: pb)                 // 视频源轨层
                } else {
                    continue
                }
                // 源 y-up → 左上原点 y-down,使 layer.transform 的垂直语义(position.y)与裁剪正确。
                let flipSrc = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: src.extent.height)
                var img = src.transformed(by: flipSrc)
                // 裁剪 = 矩形修剪(trim):保留 [left, W-right] × [top, H-bottom],被裁边缘变透明,不缩放。
                let c = layer.crop
                if c.left > 0 || c.right > 0 || c.top > 0 || c.bottom > 0 {
                    let w = src.extent.width, h = src.extent.height
                    let kept = CGRect(x: CGFloat(c.left), y: CGFloat(c.top),
                                      width: max(1, w - CGFloat(c.left) - CGFloat(c.right)),
                                      height: max(1, h - CGFloat(c.top) - CGFloat(c.bottom)))
                    img = img.cropped(to: kept)
                }
                img = img.transformed(by: layer.transform)
                img = VideoEffectFilters.apply(layer.effects, to: img)
                // 不透明度:乘 alpha
                if layer.opacity < 1 {
                    if let f = CIFilter(name: "CIColorMatrix") {
                        f.setValue(img, forKey: kCIInputImageKey)
                        f.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity)), forKey: "inputAVector")
                        img = f.outputImage ?? img
                    }
                }
                acc = img.composited(over: acc)
            }
            // 整体从左上原点 y-down 翻回 CI 的 y-up 再渲染,保证上下不颠倒。
            let flipBack = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: renderSize.height)
            acc = acc.transformed(by: flipBack)
            self.ciContext.render(acc, to: dest)
            request.finish(withComposedVideoFrame: dest)
        }
    }
}
