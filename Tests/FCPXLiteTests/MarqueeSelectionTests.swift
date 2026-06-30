import XCTest
import CoreGraphics
@testable import FCPXLite

/// 框选多选 + 同类批量调参(FCPX 高频:框住多条字幕,inspector 一次改全部)。
/// 验证 selectClips 状态、批量 updateSelectedTitle/Adjust、整组单次 undo。
@MainActor
final class MarqueeSelectionTests: XCTestCase {

    private func vAsset(_ dur: Double = 10) -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v\(UUID().uuidString).mov"), kind: .video,
              duration: .seconds(dur), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }
    private func titleClip(_ text: String, y: CGFloat = 380, fontSize: Double = 56) -> Clip {
        var spec = TitleSpec(); spec.text = text; spec.position.y = y; spec.fontSize = fontSize
        return Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2), title: spec)
    }
    /// spine:2 视频 clip + 2 标题 clip。
    private func base() -> (DocumentStore, [ClipID]) {
        let a0 = vAsset(), a1 = vAsset()
        let v0 = Clip(assetID: a0.id, sourceIn: .zero, duration: .seconds(3))
        let v1 = Clip(assetID: a1.id, sourceIn: .zero, duration: .seconds(3))
        let t0 = titleClip("字幕一"), t1 = titleClip("字幕二")
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [a0, a1],
                           sequence: Sequence(spine: [.clip(v0), .clip(t0), .clip(v1), .clip(t1)]))
        return (DocumentStore(document: doc), [v0.id, t0.id, v1.id, t1.id])
    }

    func testSelectClipsSetsAnchorAndSet() {
        let (s, ids) = base()
        s.dispatch(.selectClips([ids[1], ids[3]], anchor: ids[1]))
        XCTAssertEqual(s.ui.selectedClipIDs, [ids[1], ids[3]])
        XCTAssertEqual(s.ui.selectedClipID, ids[1])
        // 单选会把多选集合收敛成单元素(保持一致)
        s.dispatch(.selectClip(ids[0]))
        XCTAssertEqual(s.ui.selectedClipIDs, [ids[0]])
        // 空框选 = 取消
        s.dispatch(.selectClips([], anchor: nil))
        XCTAssertTrue(s.ui.selectedClipIDs.isEmpty)
        XCTAssertNil(s.ui.selectedClipID)
    }

    func testBatchTitleAbsoluteAndRelative() {
        let (s, ids) = base()
        s.dispatch(.selectClips([ids[1], ids[3]], anchor: ids[1]))
        // 绝对设值:两条字幕字号都变 80
        s.updateSelectedTitle { $0.fontSize = 80 }
        let titles1 = s.clipsByIDs([ids[1], ids[3]]).compactMap { $0.clip.title }
        XCTAssertEqual(titles1.map { $0.fontSize }, [80, 80])
        // 相对增量:两条各自 y += 20(原 380 → 400)
        s.updateSelectedTitle { $0.position.y += 20 }
        let titles2 = s.clipsByIDs([ids[1], ids[3]]).compactMap { $0.clip.title }
        XCTAssertEqual(titles2.map { $0.position.y }, [400, 400])
    }

    /// 视频 clip 不是标题 → updateSelectedTitle 只动标题,不误伤视频。
    func testBatchTitleSkipsNonTitles() {
        let (s, ids) = base()
        s.dispatch(.selectClips([ids[0], ids[1], ids[3]], anchor: ids[1]))   // 含 1 个视频 + 2 标题
        s.updateSelectedTitle { $0.fontSize = 99 }
        XCTAssertEqual(s.clipsByIDs([ids[1]]).first?.clip.title?.fontSize, 99)
        XCTAssertEqual(s.clipsByIDs([ids[3]]).first?.clip.title?.fontSize, 99)
        XCTAssertNil(s.clipsByIDs([ids[0]]).first?.clip.title)   // 视频仍无标题
    }

    /// 整组批量改 = 单次 undo 全还原(验证走了 transaction)。
    func testBatchIsSingleUndo() {
        let (s, ids) = base()
        s.dispatch(.selectClips([ids[1], ids[3]], anchor: ids[1]))
        s.updateSelectedTitle { $0.fontSize = 120 }
        s.undo()
        let restored = s.clipsByIDs([ids[1], ids[3]]).compactMap { $0.clip.title?.fontSize }
        XCTAssertEqual(restored, [56, 56], "一次 undo 应还原全部标题字号")
    }

    func testBatchAdjustAcrossSelection() {
        let (s, ids) = base()
        s.dispatch(.selectClips([ids[0], ids[2]], anchor: ids[0]))   // 两个视频片段
        s.updateSelectedAdjust { $0.opacity = 0.5 }
        let ops = s.clipsByIDs([ids[0], ids[2]]).map { $0.clip.adjust.opacity }
        XCTAssertEqual(ops, [0.5, 0.5])
    }
}
