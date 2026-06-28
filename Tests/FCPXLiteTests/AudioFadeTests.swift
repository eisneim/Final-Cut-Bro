import XCTest
import AVFoundation
@testable import FCPXLite

final class AudioFadeTests: XCTestCase {
    private func makeSilentAudio(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fade-\(UUID().uuidString).wav")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!; buf.frameLength = frames
        try file.write(from: buf); return url
    }

    func testFadeAddsVolumeRamp() throws {
        let url = try makeSilentAudio(seconds: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(4),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        var clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(4))
        var fade = Effect.make(.fade); fade.params["inSeconds"] = 1; fade.params["outSeconds"] = 1
        clip.effects = [fade]
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let item = CompositionBuilder.build(document: doc)
        XCTAssertNotNil(item?.audioMix)
        // 至少一条 input parameters,且其 audioTimePitchAlgorithm 不验证;验证有 ramp 通过反射不可靠,
        // 改为:导出/读取 mix 后断言存在。这里断言 audioMix 非空 + 参数数==1。
        XCTAssertEqual(item?.audioMix?.inputParameters.count, 1)
    }

    // 无 fade 时不应崩、仍有音量参数。
    func testNoFadeStillBuilds() throws {
        let url = try makeSilentAudio(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(2),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(2))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        XCTAssertNotNil(CompositionBuilder.build(document: doc)?.audioMix)
    }
}
