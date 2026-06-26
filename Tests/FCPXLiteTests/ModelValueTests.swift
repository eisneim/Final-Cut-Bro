import XCTest
@testable import FCPXLite

final class ModelValueTests: XCTestCase {
    func testIdsUnique() {
        XCTAssertNotEqual(AssetID(), AssetID())
        XCTAssertNotEqual(ClipID(), ClipID())
    }

    func testAdjustmentsDefaults() {
        let a = Adjustments()
        XCTAssertEqual(a.opacity, 1.0)
        XCTAssertEqual(a.volume, 1.0)
        XCTAssertEqual(a.transform.scale, CGSize(width: 1, height: 1))
    }

    func testAssetCodableRoundTrip() throws {
        let asset = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"),
                          kind: .video, duration: Time(value: 600, timescale: 600),
                          naturalSize: CGSize(width: 1920, height: 1080),
                          frameRate: 25, hasAudio: true)
        let data = try JSONEncoder().encode(asset)
        let back = try JSONDecoder().decode(Asset.self, from: data)
        XCTAssertEqual(asset, back)
    }

    func testTransformCodableRoundTrip() throws {
        var t = Transform()
        t.position = CGPoint(x: 12, y: -8)
        t.scale = CGSize(width: 2, height: 0.5)
        t.rotation = 45
        t.anchor = CGPoint(x: 1, y: 2)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(Transform.self, from: data)
        XCTAssertEqual(t, back)
    }
}
