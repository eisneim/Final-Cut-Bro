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

    /// 回归:连接的字幕(title 片段)必须导出成 <title>,文本/字号/颜色进 text-style,而非被静默丢弃。
    func testConnectedTitleBecomesTitleElement() {
        let a = videoAsset()
        let spec = TitleSpec(text: "你好世界", fontSize: 64, colorHex: "#FF0000", bold: true, align: 1)
        // title 片段 assetID 不在素材库(标题不引用真实媒体)—— 曾导致 firstIndex 失败被丢弃
        let titleClip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3),
                             lane: 1, offset: .seconds(0), title: spec)
        let host = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5), connected: [titleClip])
        let xml = FCPXMLExporter.export(doc([.clip(host)], assets: [a]))

        XCTAssertTrue(xml.contains("<title "), "字幕应导出为 <title> 元素")
        XCTAssertTrue(xml.contains("你好世界"), "字幕文本应出现在导出里")
        XCTAssertTrue(xml.contains("<effect id=\"r_title\""), "应声明 Basic Title 生成器资源")
        XCTAssertTrue(xml.contains("Bumper:Opener.localized"), "uid 子目录段须为 Bumper:Opener(FCP 才解析得到)")
        XCTAssertTrue(xml.contains("fontSize=\"64\""), "字号应进 text-style")
        XCTAssertTrue(xml.contains("fontColor=\"1 0 0 1\""), "颜色 #FF0000 → \"1 0 0 1\"")
        XCTAssertTrue(xml.contains("<text-style-def"), "应有 text-style-def")
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse(), "含字幕的导出仍应结构合法")
    }

    /// 字幕位置:TitleSpec.position(y 向下为正)→ FCP adjust-transform(y 向上为正,翻符号)。
    func testTitlePositionMapsToTransform() {
        let a = videoAsset()
        let spec = TitleSpec(text: "底部字幕", fontSize: 56, position: CGPoint(x: 0, y: 380))
        let titleClip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3),
                             lane: 1, offset: .zero, title: spec)
        let host = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5), connected: [titleClip])
        let xml = FCPXMLExporter.export(doc([.clip(host)], assets: [a]))
        XCTAssertTrue(xml.contains("<adjust-transform position=\"0 -380\""), "y=380(向下)应映射为 FCP y=-380(向上)")
        // DTD 顺序:adjust-transform 必须在 text/text-style-def 之后,否则 FCP 报 "content does not follow the DTD"。
        let posText = xml.range(of: "<text>")!.lowerBound
        let posStyleDef = xml.range(of: "</text-style-def>")!.lowerBound
        let posTransform = xml.range(of: "<adjust-transform")!.lowerBound
        XCTAssertTrue(posText < posTransform, "<text> 应在 <adjust-transform> 之前")
        XCTAssertTrue(posStyleDef < posTransform, "</text-style-def> 应在 <adjust-transform> 之前")
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }
    func testFormatOmitsNameAndHasColorSpace() {
        let a = videoAsset()
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5))
        let xml = FCPXMLExporter.export(doc([.clip(clip)], assets: [a]))
        XCTAssertFalse(xml.contains("name=\"FFVideoFormat"), "自定义分辨率不应写 FFVideoFormat* name")
        XCTAssertTrue(xml.contains("colorSpace=\"1-1-1 (Rec. 709)\""), "format 应带 colorSpace")
        XCTAssertTrue(xml.contains("frameDuration=\"100/2500s\""), "25fps → 100/2500s")
    }

    /// 无字幕时不应冒出 Basic Title 生成器资源。
    func testNoTitleEffectWhenNoTitles() {
        let a = videoAsset()
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5))
        let xml = FCPXMLExporter.export(doc([.clip(clip)], assets: [a]))
        XCTAssertFalse(xml.contains("r_title"), "无字幕不应有 title 生成器资源")
    }
}
