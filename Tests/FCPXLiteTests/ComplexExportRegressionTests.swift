import XCTest
import AVFoundation
@testable import FCPXLite

/// 复现 T8 导出失败:中间是纯音频(视频空洞)+ 尾部视频片段 → 导出 "could not be composed"(-11841)?
/// 以及交叉叠化 + 连接片段溢出宿主的组合。用合成媒体复现,锁定回归。
final class ComplexExportRegressionTests: XCTestCase {
    private func makeColorVideo(seconds: Double, size: CGSize, color: CIColor) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cx-\(UUID().uuidString).mov")
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
            while !input.isReadyForMoreMediaData { usleep(800) }
            if let pb = pbo {
                ctx.render(CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size)), to: pb)
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
            }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0); writer.finishWriting { sem.signal() }; sem.wait()
        return url
    }
    private func makeSilentAudio(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cxa-\(UUID().uuidString).wav")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!; buf.frameLength = frames
        try file.write(from: buf); return url
    }
    private func videoAsset(_ url: URL, _ dur: Double) -> Asset {
        Asset(id: AssetID(), url: url, kind: .video, duration: .seconds(dur),
              naturalSize: CGSize(width: 320, height: 240), frameRate: 25, hasAudio: false)
    }
    private func audioAsset(_ url: URL, _ dur: Double) -> Asset {
        Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(dur),
              naturalSize: .zero, frameRate: nil, hasAudio: true)
    }

    private func export(_ doc: Document) -> Result<URL, Error> {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cxout-\(UUID().uuidString).mp4")
        let exp = expectation(description: "export")
        var res: Result<URL, Error>!
        MovieExporter.export(document: doc, to: out, settings: ExportSettings(), progress: { _ in }) { r in
            res = r; exp.fulfill()
        }
        wait(for: [exp], timeout: 90)
        try? FileManager.default.removeItem(at: out)
        return res
    }

    /// 回归(T8 根因):背景乐比最后一个视频段长(纯音乐拖到尾部,后面没视频)时,
    /// videoComposition 的 instruction 必须覆盖到【音频决定的 composition 总时长】,否则导出 -11841。
    /// 只校验【合成结构】(快、headless 安全);实际导出渲染依赖 GPU,headless 软渲染慢,不在单测里跑。
    func testInstructionsCoverFullDurationWhenAudioLonger() throws {
        let v1 = try makeColorVideo(seconds: 2, size: CGSize(width: 320, height: 240), color: .red)
        let a1 = try makeSilentAudio(seconds: 10)   // 音频(10s)远长于视频(2s),尾部无视频
        defer { [v1, a1].forEach { try? FileManager.default.removeItem(at: $0) } }
        let av1 = videoAsset(v1, 2), aa = audioAsset(a1, 10)
        let doc = Document(formatWidth: 320, formatHeight: 240, frameRate: 25,
                           assetLibrary: [av1, aa],
                           sequence: Sequence(spine: [
                               .clip(Clip(assetID: av1.id, sourceIn: .zero, duration: .seconds(2))),
                               .clip(Clip(assetID: aa.id, sourceIn: .zero, duration: .seconds(10))),
                           ]))
        let item = CompositionBuilder.build(document: doc)!
        let vc = try XCTUnwrap(item.videoComposition, "应有 videoComposition")
        let lastInstrEnd = vc.instructions.map { CMTimeGetSeconds($0.timeRange.end) }.max() ?? 0
        let compDur = CMTimeGetSeconds(item.asset.duration)
        XCTAssertEqual(lastInstrEnd, compDur, accuracy: 0.1,
                       "instruction 末尾(\(lastInstrEnd))必须覆盖到 composition 总时长(\(compDur)),否则导出 -11841")
    }

    /// 视频片段 → 纯音频(视频空洞)→ 视频片段:导出应成功(空洞渲染黑帧,不该 -11841)。
    func testVideoGapMiddleExports() throws {
        let v1 = try makeColorVideo(seconds: 2, size: CGSize(width: 320, height: 240), color: .red)
        let a1 = try makeSilentAudio(seconds: 8)
        let v2 = try makeColorVideo(seconds: 2, size: CGSize(width: 320, height: 240), color: .green)
        defer { [v1, a1, v2].forEach { try? FileManager.default.removeItem(at: $0) } }
        let av1 = videoAsset(v1, 2), aa = audioAsset(a1, 8), av2 = videoAsset(v2, 2)
        let doc = Document(formatWidth: 320, formatHeight: 240, frameRate: 25,
                           assetLibrary: [av1, aa, av2],
                           sequence: Sequence(spine: [
                               .clip(Clip(assetID: av1.id, sourceIn: .zero, duration: .seconds(2))),
                               .clip(Clip(assetID: aa.id, sourceIn: .zero, duration: .seconds(8))),
                               .clip(Clip(assetID: av2.id, sourceIn: .zero, duration: .seconds(2))),
                           ]))
        if case .failure(let e) = export(doc) { XCTFail("视频空洞中间的时间线导出失败: \(e)") }
    }

    /// 交叉叠化 + 连接片段溢出宿主 + 中间音频空洞 + 尾部视频(贴近 T8 agent 实际结构)。
    func testCrossfadeConnectedAudioGapExports() throws {
        let v1 = try makeColorVideo(seconds: 3, size: CGSize(width: 320, height: 240), color: .red)
        let v2 = try makeColorVideo(seconds: 6, size: CGSize(width: 320, height: 240), color: .green)
        let a1 = try makeSilentAudio(seconds: 10)
        defer { [v1, v2, a1].forEach { try? FileManager.default.removeItem(at: $0) } }
        let av1 = videoAsset(v1, 3), av2 = videoAsset(v2, 6), aa = audioAsset(a1, 10)
        // clip1 带 crossfade,且挂一个溢出宿主的连接视频
        let connected = Clip(assetID: av2.id, sourceIn: .zero, duration: .seconds(6), lane: 1, offset: .seconds(1))
        let clip1 = Clip(assetID: av2.id, sourceIn: .zero, duration: .seconds(6),
                         connected: [connected], crossfadeIn: .seconds(1))
        let doc = Document(formatWidth: 320, formatHeight: 240, frameRate: 25,
                           assetLibrary: [av1, av2, aa],
                           sequence: Sequence(spine: [
                               .clip(Clip(assetID: av1.id, sourceIn: .zero, duration: .seconds(2))),
                               .clip(clip1),
                               .clip(Clip(assetID: aa.id, sourceIn: .zero, duration: .seconds(10))),
                               .clip(Clip(assetID: av1.id, sourceIn: .zero, duration: .seconds(2))),
                           ]))
        if case .failure(let e) = export(doc) { XCTFail("复杂 agent 式时间线导出失败: \(e)") }
    }
}
