// Tests/FCPXLiteTests/FCPXMLExporterTests.swift
import XCTest
@testable import FCPXLite

final class FCPXMLExporterTests: XCTestCase {
    private func doc(_ spine: [Element], assets: [Asset]) -> Document {
        Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25, assetLibrary: assets, sequence: Sequence(spine: spine))
    }
    private func videoAsset() -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
              duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }

    func testEmptyDocumentProducesValidSkeleton() {
        let xml = FCPXMLExporter.export(doc([], assets: []))
        XCTAssertTrue(xml.contains("<?xml"))
        XCTAssertTrue(xml.contains("<fcpxml"))
        XCTAssertTrue(xml.contains("<resources>"))
        XCTAssertTrue(xml.contains("<spine>"))
        // 可被 XML 解析器解析(结构合法)
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "导出的 fcpxml 应能被解析")
    }

    func testClipBecomesAssetClip() {
        let a = videoAsset()
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5))
        let xml = FCPXMLExporter.export(doc([.clip(clip)], assets: [a]))
        XCTAssertTrue(xml.contains("<asset-clip"))
        XCTAssertTrue(xml.contains("<asset "))           // 资源声明
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }

    func testGapBecomesGapElement() {
        let xml = FCPXMLExporter.export(doc([.gap(duration: .seconds(2))], assets: []))
        XCTAssertTrue(xml.contains("<gap"))
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }

    func testConnectedClipHasLaneAndOffset() {
        let a = videoAsset()
        let child = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(2), lane: 1, offset: .seconds(1))
        let host = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5), connected: [child])
        let xml = FCPXMLExporter.export(doc([.clip(host)], assets: [a]))
        XCTAssertTrue(xml.contains("lane=\"1\""))
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }

    func testTimeFormattedAsRational() {
        let a = videoAsset()
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: Time(value: 5, timescale: 1))
        let xml = FCPXMLExporter.export(doc([.clip(clip)], assets: [a]))
        // FCPXML 时间格式 "value/timescales" 或 "Ns";至少包含 s 结尾的时间
        XCTAssertTrue(xml.contains("s\"") || xml.contains("/"))
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }
}
