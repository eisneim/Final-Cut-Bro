import XCTest
import CoreGraphics
@testable import FCPXLite

/// T5:transform 关键帧插值的纯逻辑测试。
final class TransformKeyframeMathTests: XCTestCase {
    private func kf(_ t: Double, pos: CGPoint = .zero, scale: CGFloat = 1, opacity: Double = 1) -> TransformKeyframe {
        TransformKeyframe(time: .seconds(t), position: pos,
                          scale: CGSize(width: scale, height: scale), opacity: opacity)
    }

    func testNoKeyframesReturnsBase() {
        let s = TransformKeyframeMath.sample(
            keyframes: [], atSeconds: 1.0,
            basePosition: CGPoint(x: 5, y: 7), baseScale: CGSize(width: 2, height: 2), baseOpacity: 0.5)
        XCTAssertEqual(s.position, CGPoint(x: 5, y: 7))
        XCTAssertEqual(s.scale, CGSize(width: 2, height: 2))
        XCTAssertEqual(s.opacity, 0.5)
    }

    func testBeforeFirstHoldsFirst() {
        let kfs = [kf(1, pos: CGPoint(x: 10, y: 0), scale: 1.5, opacity: 0.8),
                   kf(3, pos: CGPoint(x: 30, y: 0))]
        let s = TransformKeyframeMath.sample(keyframes: kfs, atSeconds: 0.0,
                                             basePosition: .zero, baseScale: CGSize(width: 1, height: 1), baseOpacity: 1)
        XCTAssertEqual(s.position.x, 10, accuracy: 0.001)
        XCTAssertEqual(s.scale.width, 1.5, accuracy: 0.001)
        XCTAssertEqual(s.opacity, 0.8, accuracy: 0.001)
    }

    func testAfterLastHoldsLast() {
        let kfs = [kf(1, pos: CGPoint(x: 10, y: 0)),
                   kf(3, pos: CGPoint(x: 30, y: 0), scale: 2, opacity: 0.2)]
        let s = TransformKeyframeMath.sample(keyframes: kfs, atSeconds: 99,
                                             basePosition: .zero, baseScale: CGSize(width: 1, height: 1), baseOpacity: 1)
        XCTAssertEqual(s.position.x, 30, accuracy: 0.001)
        XCTAssertEqual(s.scale.width, 2, accuracy: 0.001)
        XCTAssertEqual(s.opacity, 0.2, accuracy: 0.001)
    }

    func testLinearMidpoint() {
        let kfs = [kf(0, pos: CGPoint(x: 0, y: 0), scale: 1, opacity: 1),
                   kf(2, pos: CGPoint(x: 100, y: 40), scale: 3, opacity: 0)]
        let s = TransformKeyframeMath.sample(keyframes: kfs, atSeconds: 1.0,
                                             basePosition: .zero, baseScale: CGSize(width: 1, height: 1), baseOpacity: 1)
        XCTAssertEqual(s.position.x, 50, accuracy: 0.001)
        XCTAssertEqual(s.position.y, 20, accuracy: 0.001)
        XCTAssertEqual(s.scale.width, 2, accuracy: 0.001)   // (1+3)/2
        XCTAssertEqual(s.opacity, 0.5, accuracy: 0.001)
    }

    func testQuarterAndThreeQuarter() {
        let kfs = [kf(0, pos: CGPoint(x: 0, y: 0)), kf(4, pos: CGPoint(x: 40, y: 0))]
        let q = TransformKeyframeMath.sample(keyframes: kfs, atSeconds: 1.0,
                                             basePosition: .zero, baseScale: CGSize(width: 1, height: 1), baseOpacity: 1)
        let tq = TransformKeyframeMath.sample(keyframes: kfs, atSeconds: 3.0,
                                              basePosition: .zero, baseScale: CGSize(width: 1, height: 1), baseOpacity: 1)
        XCTAssertEqual(q.position.x, 10, accuracy: 0.001)
        XCTAssertEqual(tq.position.x, 30, accuracy: 0.001)
    }

    func testUnsortedInputIsHandled() {
        // 乱序输入也应按时间插值
        let kfs = [kf(2, pos: CGPoint(x: 20, y: 0)), kf(0, pos: CGPoint(x: 0, y: 0))]
        let s = TransformKeyframeMath.sample(keyframes: kfs, atSeconds: 1.0,
                                             basePosition: .zero, baseScale: CGSize(width: 1, height: 1), baseOpacity: 1)
        XCTAssertEqual(s.position.x, 10, accuracy: 0.001)
    }

    func testZeroSpanDuplicateTimes() {
        // 同时间两关键帧不应除零
        let kfs = [kf(1, pos: CGPoint(x: 10, y: 0)), kf(1, pos: CGPoint(x: 20, y: 0))]
        let s = TransformKeyframeMath.sample(keyframes: kfs, atSeconds: 1.0,
                                             basePosition: .zero, baseScale: CGSize(width: 1, height: 1), baseOpacity: 1)
        XCTAssertTrue(s.position.x == 10 || s.position.x == 20)   // 取端点之一,不崩
    }
}
