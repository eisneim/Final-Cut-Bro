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

    // MARK: - 多素材/多镜头拼成一条片子

    /// 两个源视频(素材 0 / 1),用不同 duration 便于区分。
    private func storeWithTwoVideos() -> DocumentStore {
        let a0 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v0.mov"), kind: .video,
                       duration: .seconds(40), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let a1 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v1.mov"), kind: .video,
                       duration: .seconds(30), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [a0, a1], sequence: Sequence(spine: []))
        return DocumentStore(document: doc)
    }

    /// 每段带 assetIndex → 跨两个源视频交错拼成一条连贯成片:片段来源/顺序/时长都对。
    func testCrossAssetSegments() {
        let s = storeWithTwoVideos()
        let id0 = s.document.assetLibrary[0].id
        let id1 = s.document.assetLibrary[1].id
        // 成片顺序:素材0 的一段 → 素材1 的一段 → 素材0 的一段
        let segs: [[String: Any]] = [
            ["from": 2.0, "to": 5.0, "text": "甲", "assetIndex": 0],
            ["from": 10.0, "to": 12.0, "text": "乙", "assetIndex": 1],
            ["from": 20.0, "to": 24.0, "text": "丙", "assetIndex": 0],
        ]
        let msg = run(s, ["segments": segs])
        XCTAssertFalse(msg.contains("错误"), msg)
        XCTAssertTrue(msg.contains("来自 2 个素材"), msg)

        let videoClips = s.document.sequence.spine.compactMap { el -> Clip? in
            if case .clip(let c) = el, !c.isTitle { return c }; return nil
        }
        XCTAssertEqual(videoClips.count, 3, "应有3个视频段")
        // 来源正确
        XCTAssertEqual(videoClips[0].assetID, id0)
        XCTAssertEqual(videoClips[1].assetID, id1)
        XCTAssertEqual(videoClips[2].assetID, id0)
        // 源区间正确
        XCTAssertEqual(videoClips[0].sourceIn.seconds, 2.0, accuracy: 0.01)
        XCTAssertEqual(videoClips[1].sourceIn.seconds, 10.0, accuracy: 0.01)
        XCTAssertEqual(videoClips[1].duration.seconds, 2.0, accuracy: 0.01)
        XCTAssertEqual(videoClips[2].duration.seconds, 4.0, accuracy: 0.01)
    }

    /// 段内 assetIndex 省略 → 回退到顶层 assetIndex;越界的段跳过。
    func testSegmentAssetIndexFallbackAndOutOfRange() {
        let s = storeWithTwoVideos()
        let id1 = s.document.assetLibrary[1].id
        let segs: [[String: Any]] = [
            ["from": 1.0, "to": 3.0, "text": "用顶层默认(素材1)"],          // 省略 → 顶层 assetIndex=1
            ["from": 4.0, "to": 6.0, "text": "越界", "assetIndex": 9],       // 越界 → 跳过
            ["from": 7.0, "to": 8.0, "text": "显式素材0", "assetIndex": 0],
        ]
        let msg = run(s, ["segments": segs, "assetIndex": 1])
        XCTAssertTrue(msg.contains("跳过无效段"), msg)
        let videoClips = s.document.sequence.spine.compactMap { el -> Clip? in
            if case .clip(let c) = el, !c.isTitle { return c }; return nil
        }
        XCTAssertEqual(videoClips.count, 2, "越界段应跳过,剩2段")
        XCTAssertEqual(videoClips[0].assetID, id1, "省略 assetIndex 的段应用顶层默认(素材1)")
    }

    /// 跨素材一次 build 仍是单次 undo。
    func testCrossAssetSingleUndo() {
        let s = storeWithTwoVideos()
        _ = run(s, ["segments": [
            ["from": 1.0, "to": 3.0, "text": "a", "assetIndex": 0],
            ["from": 2.0, "to": 4.0, "text": "b", "assetIndex": 1],
        ] as [[String: Any]]])
        XCTAssertFalse(s.document.sequence.spine.isEmpty)
        s.undo()
        XCTAssertTrue(s.document.sequence.spine.isEmpty, "跨素材一次 build 也应单次 undo 回到空")
    }
}
