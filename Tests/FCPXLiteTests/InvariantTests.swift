import XCTest
@testable import FCPXLite

final class InvariantTests: XCTestCase {
    private func clip(_ secs: Double, lane: Int = 0, offset: Time = .zero,
                      connected: [Clip] = []) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs),
             connected: connected, lane: lane, offset: offset)
    }

    func testValidSequencePasses() throws {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        XCTAssertNoThrow(try Invariants.check(seq))
    }

    func testLaneCollisionThrows() {
        // 同一宿主上两个 connected,时间重叠且同 lane → 冲突
        let a = clip(2, lane: 1, offset: .seconds(0))
        let b = clip(2, lane: 1, offset: .seconds(1)) // 与 a 在 [1,2) 重叠且同 lane
        let seq = Sequence(spine: [.clip(clip(5, connected: [a, b]))])
        XCTAssertThrowsError(try Invariants.check(seq)) { err in
            XCTAssertEqual(err as? InvariantViolation, .laneCollision)
        }
    }

    func testLaneSeparationPasses() throws {
        let a = clip(2, lane: 1, offset: .seconds(0))
        let b = clip(2, lane: 2, offset: .seconds(1)) // 重叠但不同 lane → OK
        let seq = Sequence(spine: [.clip(clip(5, connected: [a, b]))])
        XCTAssertNoThrow(try Invariants.check(seq))
    }
}
