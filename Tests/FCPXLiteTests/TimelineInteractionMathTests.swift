import XCTest
import AppKit
@testable import FCPXLite

/// 时间轴交互的纯数学 + 几何命中(对照断言锁住"逻辑绕、肉眼难判"的部分)。
final class TimelineInteractionMathTests: XCTestCase {

    // MARK: - VolumeLineMath(纯函数)

    func testVolumeToYFlipAndClamp() {
        // region: maxY=100(底=音量0), height=50 → 顶 y=50=音量2
        XCTAssertEqual(VolumeLineMath.volumeToY(volume: 0, regionMaxY: 100, regionHeight: 50), 100, accuracy: 1e-6)
        XCTAssertEqual(VolumeLineMath.volumeToY(volume: 2, regionMaxY: 100, regionHeight: 50), 50, accuracy: 1e-6)
        XCTAssertEqual(VolumeLineMath.volumeToY(volume: 1, regionMaxY: 100, regionHeight: 50), 75, accuracy: 1e-6)
        // clamp
        XCTAssertEqual(VolumeLineMath.volumeToY(volume: 5, regionMaxY: 100, regionHeight: 50), 50, accuracy: 1e-6)
        XCTAssertEqual(VolumeLineMath.volumeToY(volume: -1, regionMaxY: 100, regionHeight: 50), 100, accuracy: 1e-6)
    }

    func testVolumeYRoundtrip() {
        for v in [0.0, 0.5, 1.0, 1.5, 2.0] {
            let y = VolumeLineMath.volumeToY(volume: v, regionMaxY: 200, regionHeight: 80)
            let back = VolumeLineMath.yToVolume(y: y, regionMaxY: 200, regionHeight: 80)
            XCTAssertEqual(back, v, accuracy: 1e-6, "volume↔y 往返")
        }
    }

    func testInterpolatedVolumeNoKeyframes() {
        XCTAssertEqual(VolumeLineMath.interpolatedVolume(keyframes: [], durationSecs: 10, atSeconds: 5, baseVolume: 0.7), 0.7)
    }

    func testInterpolatedVolumeLinearBetweenKeyframes() {
        let kfs = [
            VolumeKeyframe(id: UUID(), time: .seconds(2), value: 0.0),
            VolumeKeyframe(id: UUID(), time: .seconds(6), value: 1.0),
        ]
        // 中点 t=4 → 0.5
        XCTAssertEqual(VolumeLineMath.interpolatedVolume(keyframes: kfs, durationSecs: 10, atSeconds: 4, baseVolume: 1), 0.5, accuracy: 1e-6)
        // 首帧之前保持首值
        XCTAssertEqual(VolumeLineMath.interpolatedVolume(keyframes: kfs, durationSecs: 10, atSeconds: 0, baseVolume: 1), 0.0, accuracy: 1e-6)
        // 末帧之后保持末值
        XCTAssertEqual(VolumeLineMath.interpolatedVolume(keyframes: kfs, durationSecs: 10, atSeconds: 9, baseVolume: 1), 1.0, accuracy: 1e-6)
    }

    func testInterpolatedVolumeUnsortedInput() {
        let kfs = [
            VolumeKeyframe(id: UUID(), time: .seconds(6), value: 1.0),
            VolumeKeyframe(id: UUID(), time: .seconds(2), value: 0.0),
        ]  // 乱序也应正确排序后插值
        XCTAssertEqual(VolumeLineMath.interpolatedVolume(keyframes: kfs, durationSecs: 10, atSeconds: 4, baseVolume: 1), 0.5, accuracy: 1e-6)
    }

    // MARK: - gapRects(几何命中,经 view 实例)

    @MainActor
    private func viewWith(_ spine: [Element]) -> TimelineContentView {
        let v = TimelineContentView(frame: NSRect(x: 0, y: 0, width: 2000, height: 200))
        v.apply(state: .init(sequence: Sequence(spine: spine), assetLibrary: [],
                             pxPerSecond: 60, playheadSeconds: 0, selectedClipID: nil, selectedClipIDs: [], selectedGapID: nil,
                             selectedTransitionClipID: nil,
                             currentTool: .select, snappingEnabled: true, clipHeight: 72, vaRatio: 0.6))
        return v
    }

    @MainActor
    func testGapRectsPositionAndWidth() {
        // [clip(2s), gap(3s)] @ 60px/s → gap 起点 x=120, 宽=180
        let c = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let v = viewWith([.clip(c), .gap(duration: .seconds(3))])
        let rects = v.gapRects()
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0].rect.minX, 120, accuracy: 0.5)
        XCTAssertEqual(rects[0].rect.width, 180, accuracy: 0.5)
        XCTAssertEqual(rects[0].startSec, 2, accuracy: 1e-6)
        XCTAssertEqual(rects[0].durSec, 3, accuracy: 1e-6)
    }
}
