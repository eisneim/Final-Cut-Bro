import XCTest
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FCPXLite

/// T5:transform 关键帧端到端 —— 合成器按 request time 求值(不透明度动画用渲染帧验证)+ 模型/持久化。
final class TransformKeyframeCompositionTests: XCTestCase {

    /// 写一张纯色 PNG 到临时文件。
    private func makeSolidImage(_ color: (r: CGFloat, g: CGFloat, b: CGFloat),
                               size: Int = 256) throws -> URL {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let cg = ctx.makeImage()!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tkf-\(UUID().uuidString).png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
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

    /// 不透明度关键帧 1→0:t≈0 时中心偏红,t≈末 时红明显减弱(合成器确实按时间求值)。
    func testOpacityKeyframeAnimatesOverTime() throws {
        let url = try makeSolidImage((1, 0, 0))   // 纯红图
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .image, duration: .seconds(4),
                          naturalSize: CGSize(width: 256, height: 256), frameRate: 25, hasAudio: false)
        var clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(4))
        // 红图铺满画布(同比例),不透明度从 1(t=0)线性降到 0(t=4)。
        clip.transformKeyframes = [
            TransformKeyframe(time: .seconds(0), opacity: 1.0),
            TransformKeyframe(time: .seconds(4), opacity: 0.0),
        ]
        let doc = Document(formatWidth: 256, formatHeight: 256, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let item = CompositionBuilder.build(document: doc)!
        let gen = AVAssetImageGenerator(asset: item.asset)
        gen.videoComposition = item.videoComposition
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero

        let early = try gen.copyCGImage(at: CMTime(value: 1, timescale: 10), actualTime: nil)   // 0.1s
        let late  = try gen.copyCGImage(at: CMTime(value: 38, timescale: 10), actualTime: nil)  // 3.8s
        let rEarly = Self.centerRGB(early).r
        let rLate  = Self.centerRGB(late).r
        XCTAssertGreaterThan(rEarly, 150, "t≈0 不透明度≈1 → 中心应明显红: \(rEarly)")
        XCTAssertLessThan(rLate, rEarly - 40, "t≈末 不透明度≈0 → 红应明显减弱: early=\(rEarly) late=\(rLate)")
    }

    /// 模型持久化:transformKeyframes 编解码往返一致。
    func testTransformKeyframeCodableRoundtrip() throws {
        var clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        clip.transformKeyframes = [
            TransformKeyframe(time: .seconds(0), position: CGPoint(x: 1, y: 2),
                              scale: CGSize(width: 1.5, height: 1.5), opacity: 0.9),
            TransformKeyframe(time: .seconds(2), position: CGPoint(x: 30, y: -4),
                              scale: CGSize(width: 2, height: 2), opacity: 0.1),
        ]
        let data = try JSONEncoder().encode(clip)
        let back = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(back.transformKeyframes, clip.transformKeyframes)
    }

    /// 旧 JSON(无 transformKeyframes 字段)解码 → 空数组(向后兼容)。
    func testDecodingLegacyClipDefaultsEmpty() throws {
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(1))
        var data = try JSONEncoder().encode(clip)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "transformKeyframes")
        data = try JSONSerialization.data(withJSONObject: dict)
        let back = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(back.transformKeyframes.count, 0)
    }
}

/// T5:setTransformKeyframes mutation/dispatch。
@MainActor
final class TransformKeyframeStoreTests: XCTestCase {
    func testDispatchSetsKeyframesOnSpineClip() {
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: [.clip(clip)]))
        let s = DocumentStore(document: doc)
        let kfs = [TransformKeyframe(time: .seconds(0), position: CGPoint(x: 0, y: 0)),
                   TransformKeyframe(time: .seconds(3), position: CGPoint(x: 100, y: 0))]
        s.dispatch(.setTransformKeyframes(clip.id, kfs))
        guard case .clip(let c) = s.document.sequence.spine[0] else { return XCTFail() }
        XCTAssertEqual(c.transformKeyframes.count, 2)
        XCTAssertEqual(c.transformKeyframes.last?.position.x, 100)
    }
}
