import XCTest
@testable import FCPXLite

final class EffectModelTests: XCTestCase {
    func testMakeFillsDefaultParams() {
        let color = Effect.make(.color)
        XCTAssertEqual(color.kind, .color)
        XCTAssertTrue(color.enabled)
        XCTAssertEqual(color.params["brightness"], 0)
        XCTAssertEqual(color.params["contrast"], 1)
        XCTAssertEqual(color.params["saturation"], 1)
        XCTAssertEqual(Effect.make(.blur).params["radius"], 0)
        XCTAssertEqual(Effect.make(.fade).params["inSeconds"], 0)
        XCTAssertEqual(Effect.make(.fade).params["outSeconds"], 0)
    }

    func testIsVideo() {
        XCTAssertTrue(EffectKind.color.isVideo)
        XCTAssertTrue(EffectKind.blur.isVideo)
        XCTAssertFalse(EffectKind.fade.isVideo)
    }

    func testEffectCodableRoundtrip() throws {
        var e = Effect.make(.blur); e.params["radius"] = 12; e.enabled = false
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(Effect.self, from: data)
        XCTAssertEqual(e, back)
    }

    // 关键:旧 JSON(无 effects 字段)仍能解码成空数组。
    func testClipDecodesWithoutEffectsField() throws {
        let json = """
        {"id":{"raw":"X"},"assetID":{"raw":"A"},"sourceIn":{"value":0,"timescale":600},
         "duration":{"value":600,"timescale":600},"connected":[],"lane":0,
         "offset":{"value":0,"timescale":600},
         "adjust":{"transform":{"positionX":0,"positionY":0,"scaleWidth":1,"scaleHeight":1,"rotation":0,"anchorX":0,"anchorY":0},
                   "crop":{"left":0,"right":0,"top":0,"bottom":0},"opacity":1,"volume":1}}
        """.data(using: .utf8)!
        let clip = try JSONDecoder().decode(Clip.self, from: json)
        XCTAssertEqual(clip.effects, [])
    }

    func testClipWithEffectsRoundtrip() throws {
        var clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5))
        clip.effects = [Effect.make(.color), Effect.make(.fade)]
        let data = try JSONEncoder().encode(clip)
        let back = try JSONDecoder().decode(Clip.self, from: data)
        XCTAssertEqual(back.effects.count, 2)
        XCTAssertEqual(back.effects[0].kind, .color)
    }
}
