import XCTest
import CoreGraphics
@testable import FCPXLite

/// 粘贴属性(FCP ⌘⇧V):把剪贴板片段的 调整/特效/关键帧 套用到所有选中片段,整批单次 undo。
@MainActor
final class PasteAttributesTests: XCTestCase {

    private func vAsset() -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v\(UUID().uuidString).mov"), kind: .video,
              duration: .seconds(5), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }

    /// 3 个视频片段:第0个调好效果+缩放,复制它,选中另两个,粘贴属性 → 两个都套上。
    func testPasteAttributesToMultiple() {
        var a0 = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        a0.adjust.transform.scale = CGSize(width: 0.5, height: 0.5)
        a0.adjust.opacity = 0.4
        a0.effects = [Effect(id: UUID(), kind: .blur, enabled: true, params: ["radius": 8])]
        let a1 = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let a2 = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: [.clip(a0), .clip(a1), .clip(a2)]))
        let s = DocumentStore(document: doc)

        // 复制源片段
        s.dispatch(.selectClip(a0.id)); s.copySelected()
        // 选中另外两个
        s.dispatch(.selectClips([a1.id, a2.id], anchor: a1.id))
        s.pasteAttributesToSelected()

        for id in [a1.id, a2.id] {
            let c = s.clipsByIDs([id]).first!.clip
            XCTAssertEqual(c.adjust.transform.scale.width, 0.5, accuracy: 1e-6, "缩放套用")
            XCTAssertEqual(c.adjust.opacity, 0.4, accuracy: 1e-6, "不透明度套用")
            XCTAssertEqual(c.effects.count, 1, "特效套用")
            XCTAssertEqual(c.effects.first?.kind, .blur)
        }
        // 单次 undo 还原全部
        s.undo()
        XCTAssertEqual(s.clipsByIDs([a1.id]).first!.clip.adjust.opacity, 1.0, accuracy: 1e-6, "一次 undo 还原")
        XCTAssertTrue(s.clipsByIDs([a2.id]).first!.clip.effects.isEmpty)
    }

    /// 剪贴板为空 → 无操作(不崩)。
    func testPasteAttributesNoClipboard() {
        let c = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [], sequence: Sequence(spine: [.clip(c)]))
        let s = DocumentStore(document: doc)
        s.dispatch(.selectClip(c.id))
        s.pasteAttributesToSelected()   // clipboard=nil → no-op
        XCTAssertEqual(s.clipsByIDs([c.id]).first!.clip.adjust.opacity, 1.0)
    }
}
