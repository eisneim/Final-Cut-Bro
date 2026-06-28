import XCTest
@testable import FCPXLite

/// Roll 编辑中的 clamp 逻辑纯函数测试:
/// rollClampDelta(delta, leftClip, leftAssetDur, rightClip) → clampedDelta
/// 逻辑抽取自 TimelineContentView+Drag.swift mouseDragged roll 分支。
final class RollEditClampTests: XCTestCase {

    /// roll clamp 纯函数(镜像 +Drag.swift 中的 clamp 逻辑,便于单测)。
    private func rollClamp(delta: Double,
                           leftSourceIn: Double, leftDur: Double, leftAssetDur: Double,
                           rightDur: Double) -> Double {
        let maxExtendLeft  = leftAssetDur - (leftSourceIn + leftDur)  // 左侧可向右延伸最大量
        let maxShrinkRight = rightDur - 0.04                           // 右侧可收缩最大量
        return max(-maxShrinkRight, min(maxExtendLeft, delta))
    }

    func testRollForwardClampedByLeftAsset() {
        // 左片段已到素材末尾,不可再向右延伸
        let clamped = rollClamp(delta: 2.0,
                                leftSourceIn: 0, leftDur: 10, leftAssetDur: 10,
                                rightDur: 5)
        XCTAssertEqual(clamped, 0.0, accuracy: 1e-6, "左侧无余量时 delta 应 clamp 到 0")
    }

    func testRollForwardClampedByLeftMargin() {
        // 左侧有 3s 余量,请求移 5s → clamp 到 3
        let clamped = rollClamp(delta: 5.0,
                                leftSourceIn: 0, leftDur: 7, leftAssetDur: 10,
                                rightDur: 8)
        XCTAssertEqual(clamped, 3.0, accuracy: 1e-6)
    }

    func testRollBackwardClampedByRightMinDur() {
        // 右侧 duration=1s,向左移 2s 会让右片段缩到负 → clamp 到 -(1-0.04)
        let clamped = rollClamp(delta: -2.0,
                                leftSourceIn: 0, leftDur: 5, leftAssetDur: 10,
                                rightDur: 1.0)
        XCTAssertEqual(clamped, -(1.0 - 0.04), accuracy: 1e-6)
    }

    func testRollNoDeltaPassThrough() {
        // delta=0 不变
        let clamped = rollClamp(delta: 0,
                                leftSourceIn: 0, leftDur: 5, leftAssetDur: 10,
                                rightDur: 5)
        XCTAssertEqual(clamped, 0.0, accuracy: 1e-6)
    }

    func testRollSmallForwardPassThrough() {
        // 双侧均有余量,小 delta 直接通过
        let clamped = rollClamp(delta: 1.0,
                                leftSourceIn: 0, leftDur: 5, leftAssetDur: 10,
                                rightDur: 5)
        XCTAssertEqual(clamped, 1.0, accuracy: 1e-6)
    }
}
