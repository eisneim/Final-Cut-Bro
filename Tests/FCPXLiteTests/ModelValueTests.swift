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
}
