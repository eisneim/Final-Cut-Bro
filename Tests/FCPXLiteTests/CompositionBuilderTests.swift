import XCTest
import AVFoundation
@testable import FCPXLite

final class CompositionBuilderTests: XCTestCase {
    private func doc(assets: [Asset], spine: [Element]) -> Document {
        Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                 assetLibrary: assets, sequence: Sequence(spine: spine))
    }

    func testEmptyDocumentReturnsNil() {
        XCTAssertNil(CompositionBuilder.build(document: doc(assets: [], spine: [])))
    }

    func testImageOnlyReturnsNilWithoutCrash() {
        let img = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/x.png"),
                        kind: .image, duration: .seconds(5),
                        naturalSize: CGSize(width: 100, height: 100),
                        frameRate: nil, hasAudio: false)
        let clip = Clip(assetID: img.id, sourceIn: .zero, duration: .seconds(5))
        // 图片被跳过 → 无插入 → nil,且不崩溃
        XCTAssertNil(CompositionBuilder.build(document: doc(assets: [img], spine: [.clip(clip)])))
    }

    func testMissingAssetReturnsNilWithoutCrash() {
        // clip 引用了库里不存在的 asset → 跳过 → nil
        let clip = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        XCTAssertNil(CompositionBuilder.build(document: doc(assets: [], spine: [.clip(clip)])))
    }
}
