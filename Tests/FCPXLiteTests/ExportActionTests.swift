import XCTest
@testable import FCPXLite

@MainActor
final class ExportActionTests: XCTestCase {
    func testExportFCPXMLWritesFile() throws {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                      duration: .seconds(5), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5))
        let store = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                     assetLibrary: [a], sequence: Sequence(spine: [.clip(clip)])))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).fcpxml")
        defer { try? FileManager.default.removeItem(at: out) }
        try store.exportFCPXML(to: out)
        let content = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(content.contains("<fcpxml"))
        XCTAssertTrue(content.contains("<asset-clip"))
    }
}
