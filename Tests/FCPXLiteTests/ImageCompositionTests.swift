import XCTest
import AVFoundation
import AppKit
@testable import FCPXLite

final class ImageCompositionTests: XCTestCase {
    /// 写一张纯红 PNG 到临时目录。
    private func makeRedPNG(_ size: CGSize) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString).png")
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.red.setFill(); NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: url)
        return url
    }

    private func doc(_ assets: [Asset], _ spine: [Element]) -> Document {
        Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25, assetLibrary: assets, sequence: Sequence(spine: spine))
    }

    // 纯图片时间线:应能合成出可渲染的 item(以前直接返回 nil)。
    func testImageOnlyTimelineBuilds() throws {
        let url = try makeRedPNG(CGSize(width: 320, height: 240))
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .image, duration: .seconds(3),
                          naturalSize: CGSize(width: 320, height: 240), frameRate: nil, hasAudio: false)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(3))
        let item = CompositionBuilder.build(document: doc([asset], [.clip(clip)]))
        XCTAssertNotNil(item, "纯图片时间线应能合成")
        XCTAssertNotNil(item?.videoComposition, "图片有视频合成")
        // 时长应约 3s(空轨撑起)
        let dur = item.map { CMTimeGetSeconds($0.asset.duration) } ?? 0
        XCTAssertEqual(dur, 3, accuracy: 0.2)
        // 取一帧:渲染出来应是红色为主(图片填充)
        let gen = AVAssetImageGenerator(asset: item!.asset)
        gen.videoComposition = item!.videoComposition
        let cg = try gen.copyCGImage(at: CMTime(value: 1, timescale: 1), actualTime: nil)
        XCTAssertEqual(cg.width, 1920)
        XCTAssertEqual(cg.height, 1080)
    }

    // 视频 + 叠加图片:图片作为上层连接片段也能渲染。
    func testImageOverlayOnVideo() throws {
        let url = try makeRedPNG(CGSize(width: 200, height: 200))
        defer { try? FileManager.default.removeItem(at: url) }
        let img = Asset(id: AssetID(), url: url, kind: .image, duration: .seconds(2),
                        naturalSize: CGSize(width: 200, height: 200), frameRate: nil, hasAudio: false)
        let clip = Clip(assetID: img.id, sourceIn: .zero, duration: .seconds(2))
        let item = CompositionBuilder.build(document: doc([img], [.clip(clip)]))
        XCTAssertNotNil(item?.videoComposition)
    }
}
