import XCTest
import AVFoundation
@testable import FCPXLite

/// T11:交叉叠化转场(crossfade)—— 模型/总时长/合成器逐帧叠化(渲染帧验证)+ catalog。
final class CrossfadeTransitionTests: XCTestCase {

    private func makeColorVideo(seconds: Double, size: CGSize, color: CIColor) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xf-\(UUID().uuidString).mov")
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

    private static func centerRGB(_ cg: CGImage) -> (r: Int, g: Int, b: Int) {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width)/2 + 0.5, y: -CGFloat(cg.height)/2 + 0.5,
                                width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    // MARK: - 模型 / 总时长

    func testCrossfadeShortensTotalDuration() throws {
        let red = try makeColorVideo(seconds: 3, size: CGSize(width: 320, height: 240), color: .red)
        let blue = try makeColorVideo(seconds: 3, size: CGSize(width: 320, height: 240), color: .blue)
        defer { try? FileManager.default.removeItem(at: red); try? FileManager.default.removeItem(at: blue) }
        let aA = Asset(id: AssetID(), url: red, kind: .video, duration: .seconds(3),
                       naturalSize: CGSize(width: 320, height: 240), frameRate: 25, hasAudio: false)
        let aB = Asset(id: AssetID(), url: blue, kind: .video, duration: .seconds(3),
                       naturalSize: CGSize(width: 320, height: 240), frameRate: 25, hasAudio: false)
        let cA = Clip(assetID: aA.id, sourceIn: .zero, duration: .seconds(3))
        let cB = Clip(assetID: aB.id, sourceIn: .zero, duration: .seconds(3), crossfadeIn: .seconds(1))
        let doc = Document(formatWidth: 320, formatHeight: 240, frameRate: 25,
                           assetLibrary: [aA, aB], sequence: Sequence(spine: [.clip(cA), .clip(cB)]))
        let item = CompositionBuilder.build(document: doc)!
        // 总时长 = 3 + 3 - 1(重叠)= 5s
        XCTAssertEqual(item.asset.duration.seconds, 5, accuracy: 0.1)
    }

    func testCrossfadeBlendsInOverlap() throws {
        let red = try makeColorVideo(seconds: 3, size: CGSize(width: 320, height: 240), color: .red)
        let blue = try makeColorVideo(seconds: 3, size: CGSize(width: 320, height: 240), color: .blue)
        defer { try? FileManager.default.removeItem(at: red); try? FileManager.default.removeItem(at: blue) }
        let aA = Asset(id: AssetID(), url: red, kind: .video, duration: .seconds(3),
                       naturalSize: CGSize(width: 320, height: 240), frameRate: 25, hasAudio: false)
        let aB = Asset(id: AssetID(), url: blue, kind: .video, duration: .seconds(3),
                       naturalSize: CGSize(width: 320, height: 240), frameRate: 25, hasAudio: false)
        let cA = Clip(assetID: aA.id, sourceIn: .zero, duration: .seconds(3))
        let cB = Clip(assetID: aB.id, sourceIn: .zero, duration: .seconds(3), crossfadeIn: .seconds(1))
        let doc = Document(formatWidth: 320, formatHeight: 240, frameRate: 25,
                           assetLibrary: [aA, aB], sequence: Sequence(spine: [.clip(cA), .clip(cB)]))
        let item = CompositionBuilder.build(document: doc)!
        let gen = AVAssetImageGenerator(asset: item.asset)
        gen.videoComposition = item.videoComposition
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        // 重叠区 [2,3]。t=0.5 纯红;t=2.5 红蓝混合;t=4.5 纯蓝。
        let early = Self.centerRGB(try gen.copyCGImage(at: CMTime(value: 5, timescale: 10), actualTime: nil))   // 0.5s
        let mid   = Self.centerRGB(try gen.copyCGImage(at: CMTime(value: 25, timescale: 10), actualTime: nil))  // 2.5s
        let late  = Self.centerRGB(try gen.copyCGImage(at: CMTime(value: 45, timescale: 10), actualTime: nil))  // 4.5s
        XCTAssertGreaterThan(early.r, 150); XCTAssertLessThan(early.b, 80, "t=0.5 纯红")
        XCTAssertLessThan(late.r, 80); XCTAssertGreaterThan(late.b, 150, "t=4.5 纯蓝")
        // 叠化中:红和蓝都有明显存在(既非纯红也非纯蓝)
        XCTAssertGreaterThan(mid.r, 40, "叠化区应仍有红: \(mid)")
        XCTAssertGreaterThan(mid.b, 40, "叠化区应已有蓝: \(mid)")
    }

    func testNoCrossfadeKeepsFullDuration() throws {
        let red = try makeColorVideo(seconds: 2, size: CGSize(width: 160, height: 120), color: .red)
        let blue = try makeColorVideo(seconds: 2, size: CGSize(width: 160, height: 120), color: .blue)
        defer { try? FileManager.default.removeItem(at: red); try? FileManager.default.removeItem(at: blue) }
        let aA = Asset(id: AssetID(), url: red, kind: .video, duration: .seconds(2), naturalSize: CGSize(width: 160, height: 120), frameRate: 25, hasAudio: false)
        let aB = Asset(id: AssetID(), url: blue, kind: .video, duration: .seconds(2), naturalSize: CGSize(width: 160, height: 120), frameRate: 25, hasAudio: false)
        let cA = Clip(assetID: aA.id, sourceIn: .zero, duration: .seconds(2))
        let cB = Clip(assetID: aB.id, sourceIn: .zero, duration: .seconds(2))   // 无 crossfade
        let doc = Document(formatWidth: 160, formatHeight: 120, frameRate: 25,
                           assetLibrary: [aA, aB], sequence: Sequence(spine: [.clip(cA), .clip(cB)]))
        let item = CompositionBuilder.build(document: doc)!
        XCTAssertEqual(item.asset.duration.seconds, 4, accuracy: 0.1, "无转场总时长不变")
    }
}

/// T11:setCrossfade mutation + add_transition catalog。
@MainActor
final class CrossfadeStoreTests: XCTestCase {
    private func store2() -> DocumentStore {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video, duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: false)
        let s = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25, assetLibrary: [a], sequence: Sequence(spine: [])))
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        return s
    }
    private func crossfadeOf(_ s: DocumentStore, _ i: Int) -> Double? {
        guard case .clip(let c) = s.document.sequence.spine[i] else { return nil }
        return c.crossfadeIn.seconds
    }

    func testSetCrossfadeMutation() {
        let s = store2()
        s.dispatch(.setCrossfade(at: 1, duration: .seconds(1.5)))
        XCTAssertEqual(crossfadeOf(s, 1) ?? -1, 1.5, accuracy: 0.001)
    }

    func testAddTransitionCatalog() {
        let s = store2()
        _ = AgentActionCatalog.find("add_transition")!.apply(s, ["clipIndex": 1, "seconds": 0.8])
        XCTAssertEqual(crossfadeOf(s, 1) ?? -1, 0.8, accuracy: 0.001)
    }

    func testAddTransitionOnFirstClipErrors() {
        let s = store2()
        let msg = AgentActionCatalog.find("add_transition")!.apply(s, ["clipIndex": 0, "seconds": 1.0])
        XCTAssertTrue(msg.contains("错误"), "首片段无前邻,不能加转场")
        XCTAssertEqual(crossfadeOf(s, 0), 0)
    }

    func testRemoveTransitionWithZero() {
        let s = store2()
        s.dispatch(.setCrossfade(at: 1, duration: .seconds(1)))
        _ = AgentActionCatalog.find("add_transition")!.apply(s, ["clipIndex": 1, "seconds": 0.0])
        XCTAssertEqual(crossfadeOf(s, 1), 0, "0=移除转场")
    }
}
