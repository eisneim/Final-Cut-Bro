import XCTest
import CoreGraphics
@testable import FCPXLite

/// 解耦字幕契约:视频段可 merge 成少数长段,字幕仍是多条独立短字幕,各自叠在段内不同时间点。
/// 一个长视频段 → 挂多条 lane-1 连接字幕,offset = 该字幕时间线位置 − 段起点。
@MainActor
final class DecoupledSubtitlesTests: XCTestCase {

    private func storeWithOneLongClip(_ dur: Double = 40) -> DocumentStore {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v.mov"), kind: .video,
                      duration: .seconds(dur), naturalSize: CGSize(width: 1080, height: 1920), frameRate: 25, hasAudio: true)
        let clip = Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(dur))
        let doc = Document(formatWidth: 1080, formatHeight: 1920, frameRate: 25,
                           assetLibrary: [a], sequence: Sequence(spine: [.clip(clip)]))
        return DocumentStore(document: doc)
    }
    private func addTitle(_ s: DocumentStore, at: Double, dur: Double, text: String) {
        _ = AgentActionCatalog.find("add_title")!.apply(s, [
            "type": "add_title", "text": text, "atSeconds": at, "duration": dur, "y": 380,
        ])
    }

    /// 同一个长视频段上,不同时间点加 3 条字幕 → 段挂 3 条连接字幕,offset 分别 = 各自时间 − 段起点(0)。
    func testMultipleTitlesOnOneMergedSegment() {
        let s = storeWithOneLongClip(40)
        addTitle(s, at: 2, dur: 3, text: "第一句")
        addTitle(s, at: 15, dur: 4, text: "第二句")
        addTitle(s, at: 30, dur: 2, text: "第三句")

        // 主轴仍只有 1 个视频段(未被字幕拆开)
        let videoClips = s.document.sequence.spine.compactMap { el -> Clip? in
            if case .clip(let c) = el, !c.isTitle { return c }; return nil
        }
        XCTAssertEqual(videoClips.count, 1, "视频段应保持 merge 的 1 段,不被字幕拆分")

        // 该段挂 3 条连接字幕,offset 对应各自时间(段起点=0)
        let titles = videoClips[0].connected.filter { $0.isTitle }
        XCTAssertEqual(titles.count, 3, "一个长段应挂 3 条独立字幕")
        let offsets = titles.map { $0.offset.seconds }.sorted()
        XCTAssertEqual(offsets[0], 2, accuracy: 0.01)
        XCTAssertEqual(offsets[1], 15, accuracy: 0.01)
        XCTAssertEqual(offsets[2], 30, accuracy: 0.01)
        // 时长独立于视频段
        let byText = Dictionary(uniqueKeysWithValues: titles.map { ($0.title!.text, $0.duration.seconds) })
        XCTAssertEqual(byText["第一句"] ?? 0, 3, accuracy: 0.01)
        XCTAssertEqual(byText["第三句"] ?? 0, 2, accuracy: 0.01)
    }

    /// 字幕跨到第二个视频段:挂到对应宿主段,offset 相对该段起点(非绝对时间线)。
    func testTitleAttachesToCorrectHostSegment() {
        let s = storeWithOneLongClip(20)
        // 追加第二段(20s),时间线 20–40
        _ = s.appendSourceRange(assetID: s.document.assetLibrary[0].id, from: 0, to: 20)
        addTitle(s, at: 25, dur: 3, text: "在第二段上")   // 绝对 25s → 第二段(起点20)内 offset 5

        let videoClips = s.document.sequence.spine.compactMap { el -> Clip? in
            if case .clip(let c) = el, !c.isTitle { return c }; return nil
        }
        XCTAssertEqual(videoClips.count, 2)
        XCTAssertTrue(videoClips[0].connected.filter { $0.isTitle }.isEmpty, "第一段不应挂该字幕")
        let t = videoClips[1].connected.filter { $0.isTitle }
        XCTAssertEqual(t.count, 1, "字幕应挂到第二段")
        XCTAssertEqual(t[0].offset.seconds, 5, accuracy: 0.01, "offset 应相对第二段起点(25−20=5)")
    }
}
