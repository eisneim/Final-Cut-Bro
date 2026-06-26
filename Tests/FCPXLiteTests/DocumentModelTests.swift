import XCTest
@testable import FCPXLite

final class DocumentModelTests: XCTestCase {
    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    func testElementDuration() {
        XCTAssertEqual(Element.gap(duration: .seconds(2)).duration, .seconds(2))
        XCTAssertEqual(Element.clip(clip(3)).duration, .seconds(3))
    }

    func testElementAsClip() {
        XCTAssertNil(Element.gap(duration: .seconds(1)).asClip)
        XCTAssertNotNil(Element.clip(clip(1)).asClip)
    }

    func testEmptyDocument() {
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: []))
        XCTAssertTrue(doc.sequence.spine.isEmpty)
    }

    func testDocumentCodableRoundTrip() throws {
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [],
                           sequence: Sequence(spine: [.clip(clip(2)), .gap(duration: .seconds(1))]))
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertEqual(doc, back)
    }
}
