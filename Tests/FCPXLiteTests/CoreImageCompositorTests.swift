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
}
