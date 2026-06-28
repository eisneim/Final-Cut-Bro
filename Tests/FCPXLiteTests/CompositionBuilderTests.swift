import XCTest
import AVFoundation
@testable import FCPXLite

final class CompositionBuilderTests: XCTestCase {
    private func doc(assets: [Asset], spine: [Element]) -> Document {
        Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                 assetLibrary: assets, sequence: Sequence(spine: spine))
    }

    func testEmptyDocumentReturnsNil() {
        XCTAssertNil(CompositionBuilder.build(document: doc(assets: [], spine: [])))
    }

    func testImageOnlyReturnsNilWithoutCrash() {
        let img = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/x.png"),
                        kind: .image, duration: .seconds(5),
                        naturalSize: CGSize(width: 100, height: 100),
                        frameRate: nil, hasAudio: false)
        let clip = Clip(assetID: img.id, sourceIn: .zero, duration: .seconds(5))
        // 图片被跳过 → 无插入 → nil,且不崩溃
        XCTAssertNil(CompositionBuilder.build(document: doc(assets: [img], spine: [.clip(clip)])))
    }

    func testMissingAssetReturnsNilWithoutCrash() {
        // clip 引用了库里不存在的 asset → 跳过 → nil
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        XCTAssertNil(CompositionBuilder.build(document: doc(assets: [], spine: [.clip(clip)])))
    }

    // 回归:纯音频轨(无视频)必须能合成出可播放 item。
    // 之前 `inserted` 只在视频轨置位 + guard 要求 segments 非空 → 纯音乐返回 nil = 无法播放。
    func testAudioOnlyBuildsPlayableItem() throws {
        let url = try makeSilentAudioFile(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(2),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(2))
        let item = CompositionBuilder.build(document: doc(assets: [asset], spine: [.clip(clip)]))
        XCTAssertNotNil(item, "纯音频应能合成出 item")
        // 有音频混音、无视频合成(纯音频不需要 videoComposition)。
        XCTAssertNotNil(item?.audioMix, "应有 audioMix")
        XCTAssertNil(item?.videoComposition, "纯音频不应有 videoComposition")
        let dur = item.map { CMTimeGetSeconds($0.asset.duration) } ?? 0
        XCTAssertEqual(dur, 2.0, accuracy: 0.1, "时长应约 2 秒")
    }

    /// 用 AVAudioFile 写一个 N 秒的静音 WAV 到临时目录(真实可解码的音频轨,供合成测试)。
    private func makeSilentAudioFile(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fcpxlite-test-\(UUID().uuidString).wav")
        let sampleRate = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames   // 全零 = 静音,但有真实音频轨可解码
        try file.write(from: buffer)
        return url
    }
}
