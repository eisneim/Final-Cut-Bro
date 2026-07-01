import XCTest
import AVFoundation
@testable import FCPXLite

/// T9:导出矩阵验证 —— 编码(H.264/H.265/ProRes)× 分辨率(720/1080)产物的
/// 真实编码 FourCC + 尺寸正确;并验证质量档影响码率/文件大小。
final class MovieExporterMatrixTests: XCTestCase {

    /// 生成一个纯色 N 秒真实视频文件。
    private func makeColorVideo(seconds: Double, size: CGSize, color: CIColor) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("expmx-\(UUID().uuidString).mov")
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
            if let pb = pbo {
                ctx.render(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size)), to: pb)
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
            }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        return url
    }

    /// 生成每帧随机噪声的视频(高熵 → 码率上限会真正生效,可区分质量档)。
    private func makeNoiseVideo(seconds: Double, size: CGSize) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("noise-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                       AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let fps = 25, total = Int(seconds * Double(fps))
        var pbo: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, nil, &pbo)
        for f in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            if let pb = pbo {
                CVPixelBufferLockBaseAddress(pb, [])
                if let base = CVPixelBufferGetBaseAddress(pb) {
                    let count = CVPixelBufferGetBytesPerRow(pb) * Int(size.height)
                    let buf = base.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<count { buf[i] = UInt8.random(in: 0...255) }
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
            }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        return url
    }

    private func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
                     UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "?"
    }

    /// 导出 doc 并返回输出视频轨的 (尺寸, 编码 FourCC, 文件字节数)。
    private func exportAndProbe(_ doc: Document, settings: ExportSettings, ext: String) throws
        -> (size: CGSize, codec: String, bytes: Int) {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("mx-\(UUID().uuidString).\(ext)")
        let exp = expectation(description: "export")
        var produced: URL?
        MovieExporter.export(document: doc, to: out, settings: settings, progress: { _ in }) { result in
            if case .success(let u) = result { produced = u }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 90)
        guard let u = produced else { throw NSError(domain: "export", code: -1) }
        let asset = AVURLAsset(url: u)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "novideo", code: -2)
        }
        let sz = track.naturalSize.applying(track.preferredTransform)
        let absSize = CGSize(width: abs(sz.width), height: abs(sz.height))
        var codec = "?"
        if let fmt = track.formatDescriptions.first {
            codec = fourCC(CMFormatDescriptionGetMediaSubType(fmt as! CMFormatDescription))
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
        try? FileManager.default.removeItem(at: u)
        return (absSize, codec, bytes ?? 0)
    }

    private func makeDoc(srcURL: URL, srcSize: CGSize) -> Document {
        let asset = Asset(id: AssetID(), url: srcURL, kind: .video, duration: .seconds(1),
                          naturalSize: srcSize, frameRate: 25, hasAudio: false)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(1))
        return Document(formatWidth: Int(srcSize.width), formatHeight: Int(srcSize.height),
                        frameRate: 25, assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
    }

    /// 编码 × 分辨率矩阵:产物 FourCC + 尺寸正确。
    func testCodecResolutionMatrix() throws {
        let src = try makeColorVideo(seconds: 1, size: CGSize(width: 640, height: 360), color: .green)
        defer { try? FileManager.default.removeItem(at: src) }
        let doc = makeDoc(srcURL: src, srcSize: CGSize(width: 640, height: 360))

        let cases: [(ExportCodec, String, AVFileType)] = [
            (.h264, "avc1", .mp4),
            (.h265, "hvc1", .mp4),
            (.prores, "apcn", .mov),
        ]
        let resolutions: [(ExportResolution, CGSize)] = [
            (.r720, CGSize(width: 1280, height: 720)),
            (.r1080, CGSize(width: 1920, height: 1080)),
        ]
        for (codec, wantFourCC, fileType) in cases {
            let ext = (fileType == .mov) ? "mov" : "mp4"
            for (res, wantSize) in resolutions {
                let s = ExportSettings(codec: codec, quality: .medium, resolution: res, includeAudio: false)
                let r = try exportAndProbe(doc, settings: s, ext: ext)
                XCTAssertEqual(r.codec, wantFourCC, "\(codec.label) @ \(res.label) 编码应为 \(wantFourCC),实得 \(r.codec)")
                XCTAssertEqual(r.size.width, wantSize.width, accuracy: 2, "\(codec.label) @ \(res.label) 宽度")
                XCTAssertEqual(r.size.height, wantSize.height, accuracy: 2, "\(codec.label) @ \(res.label) 高度")
                XCTAssertGreaterThan(r.bytes, 0, "产物应非空")
            }
        }
    }

    /// 回归:竖屏项目导出必须【保持竖屏宽高比】,不能被拉成横屏(旧 bug:固定 1920x1080)。
    func testPortraitProjectStaysPortrait() throws {
        let src = try makeColorVideo(seconds: 1, size: CGSize(width: 720, height: 1280), color: .blue)
        defer { try? FileManager.default.removeItem(at: src) }
        let doc = makeDoc(srcURL: src, srcSize: CGSize(width: 720, height: 1280))

        // .original:保持项目原尺寸 720x1280
        let orig = try exportAndProbe(doc, settings: ExportSettings(codec: .h264, quality: .medium, resolution: .original, includeAudio: false), ext: "mp4")
        XCTAssertEqual(orig.size.width, 720, accuracy: 2, "original 竖屏宽")
        XCTAssertEqual(orig.size.height, 1280, accuracy: 2, "original 竖屏高")
        XCTAssertGreaterThan(orig.size.height, orig.size.width, "必须竖屏(高>宽),不能拉成横屏")

        // .r1080:短边=1080 → 1080x1920,仍竖屏(不是 1920x1080 横屏)
        let r1080 = try exportAndProbe(doc, settings: ExportSettings(codec: .h264, quality: .medium, resolution: .r1080, includeAudio: false), ext: "mp4")
        XCTAssertEqual(r1080.size.width, 1080, accuracy: 2, "1080p 竖屏宽=1080")
        XCTAssertEqual(r1080.size.height, 1920, accuracy: 2, "1080p 竖屏高=1920")
        XCTAssertGreaterThan(r1080.size.height, r1080.size.width, "1080p 竖屏必须保持竖屏")
    }

    /// 质量档:高质量 H.264 文件应显著大于低质量(码率确实生效)。用高熵噪声内容,使码率上限真正约束。
    func testQualityAffectsFileSize() throws {
        let src = try makeNoiseVideo(seconds: 1, size: CGSize(width: 640, height: 360))
        defer { try? FileManager.default.removeItem(at: src) }
        let doc = makeDoc(srcURL: src, srcSize: CGSize(width: 640, height: 360))
        let low = try exportAndProbe(doc, settings: ExportSettings(codec: .h264, quality: .low, resolution: .r1080, includeAudio: false), ext: "mp4")
        let high = try exportAndProbe(doc, settings: ExportSettings(codec: .h264, quality: .high, resolution: .r1080, includeAudio: false), ext: "mp4")
        XCTAssertGreaterThan(high.bytes, low.bytes, "高质量文件应大于低质量: low=\(low.bytes) high=\(high.bytes)")
    }

    /// 纯逻辑:码率随质量档单调递增,且随分辨率面积缩放;ProRes 无码率。
    func testTargetBitrateMonotonic() {
        let size = CGSize(width: 1920, height: 1080)
        let low = MovieExporter.targetBitrate(quality: .low, size: size)!
        let med = MovieExporter.targetBitrate(quality: .medium, size: size)!
        let high = MovieExporter.targetBitrate(quality: .high, size: size)!
        XCTAssertLessThan(low, med)
        XCTAssertLessThan(med, high)
        // 720p 码率应约为 1080p 的面积比(0.444)
        let bitrate720 = MovieExporter.targetBitrate(quality: .high, size: CGSize(width: 1280, height: 720))!
        XCTAssertLessThan(bitrate720, high)
        // videoSettings:ProRes 不带码率,H.264 带码率。
        let proresSettings = MovieExporter.videoSettings(codec: .prores, quality: .high, size: size)
        XCTAssertNil(proresSettings[AVVideoCompressionPropertiesKey])
        let h264Settings = MovieExporter.videoSettings(codec: .h264, quality: .high, size: size)
        XCTAssertNotNil(h264Settings[AVVideoCompressionPropertiesKey])
    }
}
