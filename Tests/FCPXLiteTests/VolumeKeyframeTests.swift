import XCTest
import AVFoundation
@testable import FCPXLite

final class VolumeKeyframeTests: XCTestCase {

    // MARK: - (a) Codable roundtrip + backward compat

    func testClipCodableRoundtripWithKeyframes() throws {
        let kf1 = VolumeKeyframe(time: .seconds(1), value: 0.5)
        let kf2 = VolumeKeyframe(time: .seconds(3), value: 1.5)
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5),
                        volumeKeyframes: [kf1, kf2])
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(decoded.volumeKeyframes.count, 2)
        XCTAssertEqual(decoded.volumeKeyframes[0].value, 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded.volumeKeyframes[1].value, 1.5, accuracy: 0.001)
        XCTAssertEqual(decoded.volumeKeyframes[0].time.seconds, 1.0, accuracy: 0.001)
    }

    func testClipBackwardCompatDecodeWithoutVolumeKeyframes() throws {
        // 先用 Codable 编码一个真实的 clip,再手工移除 volumeKeyframes 字段模拟旧 JSON。
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(clip)) as! [String: Any]
        json.removeValue(forKey: "volumeKeyframes")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(decoded.volumeKeyframes.count, 0, "旧 JSON 缺 volumeKeyframes → 解码为空数组")
    }

    // MARK: - (b) Mutations.setVolumeKeyframes

    func testSetVolumeKeyframesOnSpineClip() {
        let asset = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v.mov"), kind: .video,
                          duration: .seconds(10), naturalSize: .zero, frameRate: 25, hasAudio: true)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(10))
        let seq = Sequence(spine: [.clip(clip)])
        let kfs = [VolumeKeyframe(time: .seconds(2), value: 0.8)]
        let newSeq = Mutations.setVolumeKeyframes(clipID: clip.id, kfs, in: seq)
        guard case .clip(let updated) = newSeq.spine[0] else { return XCTFail() }
        XCTAssertEqual(updated.volumeKeyframes.count, 1)
        XCTAssertEqual(updated.volumeKeyframes[0].value, 0.8, accuracy: 0.001)
    }

    func testSetVolumeKeyframesOnConnectedChild() {
        let asset = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v.mov"), kind: .video,
                          duration: .seconds(10), naturalSize: .zero, frameRate: 25, hasAudio: true)
        var host = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(10))
        let child = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(3),
                         lane: 1, offset: .seconds(1))
        host.connected = [child]
        let seq = Sequence(spine: [.clip(host)])
        let kfs = [VolumeKeyframe(time: .seconds(1), value: 0.3)]
        let newSeq = Mutations.setVolumeKeyframes(clipID: child.id, kfs, in: seq)
        guard case .clip(let updatedHost) = newSeq.spine[0] else { return XCTFail() }
        XCTAssertEqual(updatedHost.connected[0].volumeKeyframes.count, 1)
        XCTAssertEqual(updatedHost.connected[0].volumeKeyframes[0].value, 0.3, accuracy: 0.001)
    }

    // MARK: - (c) CompositionBuilder with keyframes

    func testCompositionBuilderKeyframesProduceAudioMix() throws {
        let url = try makeSilentAudio(seconds: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(4),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        var clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(4))
        clip.volumeKeyframes = [
            VolumeKeyframe(time: .seconds(0), value: 0.0),
            VolumeKeyframe(time: .seconds(2), value: 1.0),
            VolumeKeyframe(time: .seconds(4), value: 0.5),
        ]
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let item = CompositionBuilder.build(document: doc)
        XCTAssertNotNil(item?.audioMix, "关键帧路径应产生 audioMix")
        XCTAssertEqual(item?.audioMix?.inputParameters.count, 1)
    }

    private func makeSilentAudio(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vkf-test-\(UUID().uuidString).wav")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        try file.write(from: buf)
        return url
    }
}
