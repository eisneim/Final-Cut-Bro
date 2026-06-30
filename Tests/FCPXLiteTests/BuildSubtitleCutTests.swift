import XCTest
import CoreGraphics
@testable import FCPXLite

/// build_subtitle_cut:一次调用按【保留段计划】批量提取片段+逐段加字幕。
/// 验证"程序化批量"取代"逐段 LLM 调用":N 段计划 → N 个视频段 + N 条字幕,源区间精确。
@MainActor
final class BuildSubtitleCutTests: XCTestCase {

    private func storeWithVideo(_ dur: Double = 40) -> DocumentStore {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v.mov"), kind: .video,
                      duration: .seconds(dur), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [a], sequence: Sequence(spine: []))
        return DocumentStore(document: doc)
    }
    private func run(_ s: DocumentStore, _ args: [String: Any]) -> String {
        AgentActionCatalog.find("build_subtitle_cut")!.apply(s, args.merging(["type": "build_subtitle_cut"]) { x, _ in x })
    }

    /// 主轴片段数 = 保留段数;每段时长 = to-from;字幕条数 = 段数,文字/位置正确。
    func testBatchBuildsClipsAndTitles() {
        let s = storeWithVideo()
        let segs: [[String: Any]] = [
            ["from": 11.28, "to": 24.56, "text": "保留A"],
            ["from": 35.44, "to": 37.44, "text": "保留B"],
        ]
        let msg = run(s, ["segments": segs, "assetIndex": 0, "fontSize": 56, "y": 380])
        XCTAssertFalse(msg.contains("错误"), msg)

        // 主轴视频段(非标题)
        var videoClips: [Clip] = []
        var titles: [Clip] = []
        for el in s.document.sequence.spine {
            if case .clip(let c) = el {
                if c.isTitle { titles.append(c) } else { videoClips.append(c) }
                for ch in c.connected where ch.isTitle { titles.append(ch) }
            }
        }
        XCTAssertEqual(videoClips.count, 2, "应有2个视频段")
        XCTAssertEqual(titles.count, 2, "应有2条字幕")
        // 源区间精确(sourceIn + duration)
        XCTAssertEqual(videoClips[0].sourceIn.seconds, 11.28, accuracy: 0.01)
        XCTAssertEqual(videoClips[0].duration.seconds, 13.28, accuracy: 0.01)
        XCTAssertEqual(videoClips[1].sourceIn.seconds, 35.44, accuracy: 0.01)
        XCTAssertEqual(videoClips[1].duration.seconds, 2.0, accuracy: 0.01)
        // 字幕样式
        let texts = Set(titles.compactMap { $0.title?.text })
        XCTAssertEqual(texts, ["保留A", "保留B"])
        XCTAssertEqual(titles.first?.title?.fontSize, 56)
        XCTAssertEqual(titles.first?.title?.position.y, 380)
    }

    /// 无效段(to<=from)跳过,不影响其余;空计划报错。
    func testSkipsInvalidAndRejectsEmpty() {
        let s = storeWithVideo()
        let segs: [[String: Any]] = [
            ["from": 5.0, "to": 3.0, "text": "倒序无效"],
            ["from": 10.0, "to": 12.0, "text": "有效"],
        ]
        let msg = run(s, ["segments": segs])
        XCTAssertTrue(msg.contains("跳过无效段"), msg)
        let clips = s.document.sequence.spine.filter { if case .clip(let c) = $0 { return !c.isTitle }; return false }
        XCTAssertEqual(clips.count, 1)

        let s2 = storeWithVideo()
        XCTAssertTrue(run(s2, ["segments": [[String: Any]]()]).contains("错误"))
    }

    /// 一次 build = 一次撤销:undo 回到空时间线(验证不是几十步散落操作)。
    func testSingleUndoRestoresEmpty() {
        let s = storeWithVideo()
        _ = run(s, ["segments": [["from": 1.0, "to": 3.0, "text": "x"], ["from": 5.0, "to": 6.0, "text": "y"]] as [[String: Any]]])
        XCTAssertFalse(s.document.sequence.spine.isEmpty)
        s.undo()
        XCTAssertTrue(s.document.sequence.spine.isEmpty, "一次 build 应可单次 undo 回到空(否则是散落多步)")
    }
}
