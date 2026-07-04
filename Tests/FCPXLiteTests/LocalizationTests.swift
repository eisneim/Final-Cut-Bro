import XCTest
@testable import FCPXLite

/// i18n 纯查表逻辑:中文直通、英文查表、缺失回退、表无重复 key、每条都有英文。
final class LocalizationTests: XCTestCase {

    func testChinesePassthrough() {
        XCTAssertEqual(Localization.translate("时间线", to: .zh), "时间线")
        XCTAssertEqual(Localization.translate("不存在的串", to: .zh), "不存在的串")
    }

    func testEnglishLookup() {
        XCTAssertEqual(Localization.translate("时间线", to: .en), "Timeline")
        XCTAssertEqual(Localization.translate("导出", to: .en), "Export")
    }

    func testMissingFallsBackToChinese() {
        XCTAssertEqual(Localization.translate("没有英文翻译的串XYZ", to: .en), "没有英文翻译的串XYZ")
    }

    /// 访问 table 触发字典字面量构建 —— 若有重复 key 会在此崩溃(守卫)。
    func testTableHasNoDuplicateKeysAndAllHaveEnglish() {
        let table = Strings.table
        XCTAssertGreaterThan(table.count, 30)
        for (zh, langs) in table {
            XCTAssertNotNil(langs[.en], "缺英文翻译: \(zh)")
            XCTAssertFalse((langs[.en] ?? "").isEmpty, "空英文翻译: \(zh)")
        }
    }

    func testLanguageMetadata() {
        XCTAssertEqual(Language.allCases.count, 2)
        XCTAssertEqual(Language.zh.shortCode, "中")
        XCTAssertEqual(Language.en.nativeName, "English")
    }
}
