// Tests/FCPXLiteTests/MovieExporterTests.swift
import XCTest
import AVFoundation
@testable import FCPXLite

final class MovieExporterTests: XCTestCase {
    private func makeSilentAudio(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("me-\(UUID().uuidString).wav")
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!; buf.frameLength = frames
        try file.write(from: buf); return url
    }

    func testEmptyTimelineFailsFast() {
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25, assetLibrary: [], sequence: Sequence(spine: []))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("empty.m4a")
        let exp = expectation(description: "completion")
        MovieExporter.export(document: doc, to: out, settings: ExportSettings(), progress: { _ in }) { result in
            if case .failure = result { exp.fulfill() } else { XCTFail("空时间线应失败") }
        }
        wait(for: [exp], timeout: 5)
    }

    func testH264ExportWithSettings() throws {
        let url = try makeSilentAudio(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(1),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(1))
        let doc = Document(formatWidth: 1280, formatHeight: 720, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("h264-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        let exp = expectation(description: "h264 export")
        let settings = ExportSettings(codec: .h264, quality: .low, resolution: .r720, includeAudio: true)
        MovieExporter.export(document: doc, to: out, settings: settings, progress: { _ in }) { result in
            switch result {
            case .success(let u):
                XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
                let a = AVURLAsset(url: u)
                XCTAssertEqual(CMTimeGetSeconds(a.duration), 1.0, accuracy: 0.5)
            case .failure(let e): XCTFail("export failed: \(e)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 60)
    }

    func testAudioOnlyExportsM4A() throws {
        let url = try makeSilentAudio(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = Asset(id: AssetID(), url: url, kind: .audio, duration: .seconds(1),
                          naturalSize: .zero, frameRate: nil, hasAudio: true)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(1))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [asset], sequence: Sequence(spine: [.clip(clip)]))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("out-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: out) }
        let exp = expectation(description: "export")
        MovieExporter.export(document: doc, to: out, settings: ExportSettings(), progress: { _ in }) { result in
            switch result {
            case .success(let u):
                XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
                // 产物可读、时长 ~1s
                let a = AVURLAsset(url: u)
                XCTAssertEqual(CMTimeGetSeconds(a.duration), 1.0, accuracy: 0.3)
            case .failure(let e): XCTFail("导出失败 \(e)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }
}
