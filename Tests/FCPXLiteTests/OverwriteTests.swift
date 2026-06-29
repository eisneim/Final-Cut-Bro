import XCTest
@testable import FCPXLite

final class OverwriteTests: XCTestCase {
    private func clip(_ secs: Double, sourceIn: Double = 0) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .seconds(sourceIn), duration: .seconds(secs))
    }
    private func totalDur(_ s: Sequence) -> Double {
        s.spine.reduce(0.0) { $0 + $1.duration.seconds }
    }
    private func clipCount(_ s: Sequence) -> Int {
        s.spine.reduce(0) { if case .clip = $1 { return $0 + 1 }; return $0 }
    }

    // 覆盖单个长 clip 的中段:切成 左 + 新 + 右,总时长不变。
    func testOverwriteMidClipSplits() {
        let seq = Sequence(spine: [.clip(clip(10))])  // 0..10
        let nw = clip(2)
        let out = Mutations.overwrite(nw, atTime: .seconds(4), in: seq)  // 覆盖 4..6
        XCTAssertEqual(totalDur(out), 10, accuracy: 1e-6, "总时长不变")
        XCTAssertEqual(clipCount(out), 3, "左[0..4] + 新[4..6] + 右[6..10]")
        // 中间应是新 clip
        XCTAssertEqual(out.spine[1].asClip?.assetID, nw.assetID)
        XCTAssertEqual(out.spine[1].duration, .seconds(2))
        // 左段时长 4,右段时长 4
        XCTAssertEqual(out.spine[0].duration.seconds, 4, accuracy: 1e-6)
        XCTAssertEqual(out.spine[2].duration.seconds, 4, accuracy: 1e-6)
    }

    // 覆盖跨越两个 clip:中间被覆盖部分移除,两侧裁切,总时长不变。
    func testOverwriteAcrossClips() {
        let a = clip(5), b = clip(5)
        let seq = Sequence(spine: [.clip(a), .clip(b)])  // 0..5, 5..10
        let nw = clip(4)
        let out = Mutations.overwrite(nw, atTime: .seconds(3), in: seq)  // 覆盖 3..7
        XCTAssertEqual(totalDur(out), 10, accuracy: 1e-6)
        // a 裁成 0..3 (3s), 新 3..7 (4s), b 裁成 7..10 (3s)
        XCTAssertEqual(out.spine.first?.duration.seconds ?? -1, 3, accuracy: 1e-6)
        XCTAssertEqual(out.spine.last?.duration.seconds ?? -1, 3, accuracy: 1e-6)
        XCTAssertEqual(out.spine[1].asClip?.assetID, nw.assetID)
    }

    // 覆盖超出末尾:延长时间线。
    func testOverwritePastEnd() {
        let seq = Sequence(spine: [.clip(clip(5))])  // 0..5
        let nw = clip(3)
        let out = Mutations.overwrite(nw, atTime: .seconds(4), in: seq)  // 覆盖 4..7,超尾
        XCTAssertEqual(totalDur(out), 7, accuracy: 1e-6, "延长到 7")
        // 左 0..4, 新 4..7
        XCTAssertEqual(out.spine.first?.duration.seconds ?? -1, 4, accuracy: 1e-6)
        XCTAssertEqual(out.spine.last?.asClip?.assetID, nw.assetID)
    }

    // 播放头超出末尾:补 gap + 新 clip。
    func testOverwriteBeyondEndPadsGap() {
        let seq = Sequence(spine: [.clip(clip(5))])  // 0..5
        let nw = clip(2)
        let out = Mutations.overwrite(nw, atTime: .seconds(8), in: seq)  // 播放头 8 > 末尾 5
        XCTAssertEqual(totalDur(out), 10, accuracy: 1e-6, "5 + gap(3) + 2 = 10")
        XCTAssertNotNil(out.spine[1].gapID, "中间补 gap")
        XCTAssertEqual(out.spine.last?.asClip?.assetID, nw.assetID)
    }

    // 完全覆盖一个 clip(等长):替换之。
    func testOverwriteWholeClip() {
        let a = clip(5)
        let seq = Sequence(spine: [.clip(a)])
        let nw = clip(5)
        let out = Mutations.overwrite(nw, atTime: .zero, in: seq)
        XCTAssertEqual(totalDur(out), 5, accuracy: 1e-6)
        XCTAssertEqual(clipCount(out), 1)
        XCTAssertEqual(out.spine[0].asClip?.assetID, nw.assetID)
    }
}
