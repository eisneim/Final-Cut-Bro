import XCTest
import CoreGraphics
@testable import FCPXLite

/// 字幕样式扩展:新字段(字体/描边/阴影)Codable 向后兼容 + TitleRenderer 应用不崩。
final class TitleStyleTests: XCTestCase {

    /// 旧 JSON(缺新字段)解码 → 用默认值,不报错(向后兼容)。
    func testDecodeLegacyJSONUsesDefaults() throws {
        let legacy = """
        {"text":"你好","fontSize":56,"colorHex":"#FFFFFF","bold":true,"positionX":0,"positionY":380,"align":1}
        """.data(using: .utf8)!
        let spec = try JSONDecoder().decode(TitleSpec.self, from: legacy)
        XCTAssertEqual(spec.text, "你好")
        XCTAssertNil(spec.fontName)              // 默认系统字体
        XCTAssertEqual(spec.strokeWidth, 3)      // 默认描边
        XCTAssertFalse(spec.shadowEnabled)       // 默认无阴影
        XCTAssertEqual(spec.shadowDY, 2)
    }

    /// 新字段完整 round-trip。
    func testRoundTripNewFields() throws {
        var s = TitleSpec(text: "字幕")
        s.fontName = "Helvetica"; s.strokeWidth = 6; s.strokeColorHex = "#112233"
        s.shadowEnabled = true; s.shadowColorHex = "#010203"; s.shadowRadius = 8; s.shadowDX = 3; s.shadowDY = 5
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(TitleSpec.self, from: data)
        XCTAssertEqual(back, s)
    }

    /// TitleRenderer 带描边+阴影+指定字体渲染出非空图(不崩)。
    func testRendererWithStyles() {
        var s = TitleSpec(text: "口播字幕测试")
        s.fontName = "Helvetica"; s.strokeWidth = 5; s.shadowEnabled = true; s.shadowRadius = 6
        let img = TitleRenderer.render(s, size: CGSize(width: 720, height: 1280))
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.width, 720)
        XCTAssertEqual(img?.height, 1280)
    }

    /// 通过 store 改字幕样式(可撤销)。
    @MainActor
    func testUpdateTitleStyleViaStore() {
        var spec = TitleSpec(text: "字幕")
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2),
                         lane: 1, offset: .zero, title: spec)
        let host = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5), connected: [title])
        let doc = Document(formatWidth: 720, formatHeight: 1280, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: [.clip(host)]))
        let store = DocumentStore(document: doc)
        store.dispatch(.selectClip(title.id))
        store.updateSelectedTitle { $0.shadowEnabled = true; $0.strokeWidth = 8; $0.fontName = "Menlo" }
        let t = store.clipsByIDs([title.id]).first?.clip.title
        XCTAssertEqual(t?.shadowEnabled, true)
        XCTAssertEqual(t?.strokeWidth, 8)
        XCTAssertEqual(t?.fontName, "Menlo")
        _ = spec
    }
}
