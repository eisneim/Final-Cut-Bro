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
        XCTAssertTrue(xml.contains("<effect id=\"r_title\""), "应声明字幕生成器资源")
        XCTAssertTrue(xml.contains("Custom.localized/Custom.moti"), "用 Custom.moti(跨版本最稳)")
        XCTAssertTrue(xml.contains("fontSize=\"64\""), "字号应进 text-style")
        XCTAssertTrue(xml.contains("fontColor=\"1 0 0 1\""), "颜色 #FF0000 → \"1 0 0 1\"")
        XCTAssertTrue(xml.contains("<text-style-def"), "应有 text-style-def")
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse(), "含字幕的导出仍应结构合法")
    }

    /// 连接字幕的 offset 必须是【父级本地坐标 = 宿主 sourceIn + 相对 offset】,且按帧对齐。
    func testConnectedTitleOffsetIsParentStartPlusRelative() {
        let a = videoAsset()
        let clipA = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5))
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                         lane: 1, offset: .seconds(2), title: TitleSpec(text: "字幕"))
        // 第二段:源入点 sourceIn=10s,时间线位于 5s 起(A 之后)
        let clipB = Clip(assetID: a.id, sourceIn: .seconds(10), duration: .seconds(8), connected: [title])
        let xml = FCPXMLExporter.export(doc([.clip(clipA), .clip(clipB)], assets: [a]))

        // 顶层 clip offset = 绝对时间线(帧对齐,25fps):A=0s, B=5s=125帧=12500/2500s
        XCTAssertTrue(xml.contains("offset=\"0s\""), "A 应在 0s")
        XCTAssertTrue(xml.contains("offset=\"12500/2500s\""), "B 应在 5s(125帧)")
        // 字幕 offset = 宿主 sourceIn(10) + 相对(2) = 12s = 300帧 = 30000/2500s
        XCTAssertTrue(xml.contains("offset=\"30000/2500s\""), "字幕 offset 应=sourceIn+相对=12s;得到 \(xml)")
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }

    /// 所有编辑点时间必须落在整数帧边界(否则 FCP 报"此项目不在编辑帧边界上")。
    func testTimesAreFrameAligned() {
        let a = videoAsset()   // 25fps
        // 故意用非帧对齐的秒数(ASR 时间戳那样)
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(0.137),
                         lane: 1, offset: .seconds(3.1267), title: TitleSpec(text: "x"))
        let host = Clip(assetID: a.id, sourceIn: .seconds(0.44), duration: .seconds(2.9), connected: [title])
        let xml = FCPXMLExporter.export(doc([.clip(host)], assets: [a]))
        // 抽出所有 offset/duration/start 的 "N/2500s",其分子必须是 100 的倍数(=整数帧)
        let re = try! NSRegularExpression(pattern: "\"(\\d+)/2500s\"")
        let ns = xml as NSString
        let matches = re.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        XCTAssertFalse(matches.isEmpty, "应有帧对齐时间")
        for m in matches {
            let num = Int(ns.substring(with: m.range(at: 1)))!
            XCTAssertEqual(num % 100, 0, "时间 \(num)/2500s 不在帧边界(分子非 100 倍数)")
        }
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }

    /// 字幕 fontSize 按分辨率缩放:1080 为基准 ×1,4K(2160)×2。
    func testFontSizeScalesWithResolution() {
        let make: (Int, Int) -> String = { w, h in
            let asset = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                              duration: .seconds(10), naturalSize: CGSize(width: w, height: h), frameRate: 25, hasAudio: true)
            let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2), lane: 1,
                             title: TitleSpec(text: "字", fontSize: 50))
            let host = Clip(assetID: asset.id, sourceIn: .zero, duration: .seconds(5), connected: [title])
            let d = Document(formatWidth: w, formatHeight: h, frameRate: 25, assetLibrary: [asset], sequence: Sequence(spine: [.clip(host)]))
            return FCPXMLExporter.export(d)
        }
        XCTAssertTrue(make(1920, 1080).contains("fontSize=\"50\""), "1080p:50→50")
        XCTAssertTrue(make(3840, 2160).contains("fontSize=\"100\""), "4K:50→100(×2)")
    }

    /// 字幕位置:TitleSpec.position(渲染像素,y 向下为正)→ FCP adjust-transform 百分比(1=1%,y 向上为正)。
    func testTitlePositionMapsToTransformPercent() {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                      duration: .seconds(10), naturalSize: CGSize(width: 1000, height: 1000), frameRate: 25, hasAudio: true)
        // 1000×1000 画幅,y=250px → 25% → FCP -25(向下 25%)
        let d = Document(formatWidth: 1000, formatHeight: 1000, frameRate: 25,
                         assetLibrary: [a], sequence: Sequence(spine: []))
        let spec = TitleSpec(text: "底部字幕", fontSize: 56, position: CGPoint(x: 0, y: 250))
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3), lane: 1, offset: .zero, title: spec)
        let host = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5), connected: [title])
        var doc2 = d; doc2.sequence = Sequence(spine: [.clip(host)])
        let xml = FCPXMLExporter.export(doc2)

        XCTAssertTrue(xml.contains("<adjust-transform position=\"0 -25\""), "y=250px/1000 → 25% 向下 → -25;实际: \(xml)")
        // DTD 顺序:adjust-transform 在 text/text-style-def 之后
        let posText = xml.range(of: "<text>")!.lowerBound
        let posStyleDef = xml.range(of: "</text-style-def>")!.lowerBound
        let posTransform = xml.range(of: "<adjust-transform")!.lowerBound
        XCTAssertTrue(posText < posTransform && posStyleDef < posTransform, "adjust-transform 应在 text/text-style-def 之后")
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
