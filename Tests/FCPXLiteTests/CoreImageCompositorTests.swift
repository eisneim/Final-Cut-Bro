// Tests/FCPXLiteTests/CoreImageCompositorTests.swift
import XCTest
import AVFoundation
@testable import FCPXLite

final class CoreImageCompositorTests: XCTestCase {
    // 生成一个纯色 N 秒视频文件(真实可解码视频轨,供合成器测试)。
    private func makeColorVideo(seconds: Double, size: CGSize, color: CIColor) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("citest-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                       AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let fps = 25, total = Int(seconds * Double(fps))
        let ctx = CIContext()
        var pbo: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &pbo)
        for f in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            if let pb = pbo { ctx.render(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size)), to: pb)
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps))) }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        return url
    }

    // 合成器接入后:单视频片段仍能产出可解码、尺寸=renderSize 的帧(等价旧行为,不崩)。
    func testCompositorProducesFrameForSingleVideo() throws {
        let url = try makeColorVideo(seconds: 1, size: CGSize(width: 320, height: 240), color: .red)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .video, duration: .seconds(1),
                          naturalSize: CGSize(width: 320, height: 240), frameRate: 25, hasAudio: false)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(1))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let item = CompositionBuilder.build(document: doc)
        XCTAssertNotNil(item?.videoComposition)
        // videoComposition 的 customVideoCompositorClass 应是我们的合成器
        XCTAssertTrue(item?.videoComposition?.customVideoCompositorClass == CoreImageCompositor.self)
        // 用 imageGenerator 取一帧 → 不为 nil(产物可渲染)
        let gen = AVAssetImageGenerator(asset: item!.asset)
        gen.videoComposition = item!.videoComposition
        let cg = try gen.copyCGImage(at: CMTime(value: 1, timescale: 4), actualTime: nil)
        XCTAssertEqual(cg.width, 1920)
        XCTAssertEqual(cg.height, 1080)
    }

    /// 上半红、下半蓝的视频(picture-top=红)。row 0 是画面顶部。
    private func makeHalfRedBlueVideo(seconds: Double, size: CGSize) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("halfrb-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                       AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let fps = 25, total = Int(seconds * Double(fps))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var pbo: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &pbo)
        for f in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            guard let pb = pbo else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb),
               let cg = CGContext(data: base, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                // CGContext 原点在左下;画面"上半"(顶部)是高 y。顶部红、底部蓝。
                cg.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
                cg.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)) // 上半红
                cg.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
                cg.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))               // 下半蓝
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        return url
    }

    private static func centerRGB(_ cg: CGImage) -> (r: Int, g: Int, b: Int) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // 把整图的中心像素绘到 1x1(缩放采样近似中心区域主色)
        ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width)/2 + 0.5, y: -CGFloat(cg.height)/2 + 0.5,
                                width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    /// 回归:crop.top 必须裁掉【画面顶部】(红),保留底部(蓝)。
    /// 锁定 CIImage(y-up) 与 fullTransform(y-down) 的坐标系修复 —— 修复前中心是红,修复后是蓝。
    func testCropTopRemovesTopEdge() throws {
        let size = CGSize(width: 320, height: 240)
        let url = try makeHalfRedBlueVideo(seconds: 1, size: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .video, duration: .seconds(1),
                          naturalSize: size, frameRate: 25, hasAudio: false)
        var clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(1))
        clip.adjust.crop.top = Double(size.height) * 0.5   // 裁掉上半(红)
        let doc = Document(formatWidth: 320, formatHeight: 240, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let item = CompositionBuilder.build(document: doc)!
        let gen = AVAssetImageGenerator(asset: item.asset)
        gen.videoComposition = item.videoComposition
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let cg = try gen.copyCGImage(at: CMTime(value: 1, timescale: 4), actualTime: nil)
        let (r, _, b) = Self.centerRGB(cg)
        XCTAssertGreaterThan(b, r, "crop.top 应裁掉画面上半(红),中心应为下半蓝: r=\(r) b=\(b)")
    }
}

