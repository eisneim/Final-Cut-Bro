import XCTest
@testable import FCPXLite

final class PositionMoveTests: XCTestCase {

    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    // positionMove on a spine clip: source slot becomes .gap, clip lands at target
    func testPositionMoveLeavesGapAtSource() {
        let a = clip(3), b = clip(2), c = clip(1)
        let seq = Sequence(spine: [.clip(a), .clip(b), .clip(c)])
        // Move clip B (index 1) to time=6 (after c)
        let out = Mutations.positionMove(clipID: b.id, atTime: .seconds(6), in: seq)
        // spine[1] must now be a gap of 2s
        if case .gap(let d) = out.spine[1] {
            XCTAssertEqual(d, .seconds(2))
        } else {
            XCTFail("spine[1] should be .gap; got \(out.spine[1])")
        }
        // B must appear somewhere in the spine after the gap
        let ids = out.spine.compactMap { $0.asClip?.id }
        XCTAssertTrue(ids.contains(b.id))
        // original [A(3),B(2),C(1)] → replace B with gap: [A,gap,C] → insert B at t=6 (after C end t=4): [A,gap,C,B]
        XCTAssertEqual(out.spine.count, 4) // [A, gap, C, B]
        XCTAssertNoThrow(try Invariants.check(out))
    }

    func testPositionMoveUnknownIdIsNoop() {
        let a = clip(3)
        let seq = Sequence(spine: [.clip(a)])
        let out = Mutations.positionMove(clipID: ClipID(), atTime: .seconds(0), in: seq)
        XCTAssertEqual(out, seq)
    }

    func testPositionMoveConnectedClipFallsBackToRelocate() {
        let child = Clip(id: ClipID(), assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                         lane: 1, offset: .seconds(0.5))
        let host = Clip(id: ClipID(), assetID: AssetID(), sourceIn: .zero, duration: .seconds(4),
                        connected: [child])
        let seq = Sequence(spine: [.clip(host)])
        // Moving a connected clip: falls back to relocate(lane:0), no gap added
        let out = Mutations.positionMove(clipID: child.id, atTime: .seconds(0), in: seq)
        // host still on spine, child moved to spine as lane 0 → 2 spine elements
        XCTAssertEqual(out.spine.count, 2)
        XCTAssertNoThrow(try Invariants.check(out))
    }

    // setGapDuration resizes a gap
    func testSetGapDurationResizesGap() {
        let seq = Sequence(spine: [.gap(duration: .seconds(3))])
        let out = Mutations.setGapDuration(at: 0, duration: .seconds(5), in: seq)
        XCTAssertEqual(out.spine[0].duration, .seconds(5))
    }

    func testSetGapDurationClampsToMinimum() {
        let seq = Sequence(spine: [.gap(duration: .seconds(3))])
        let out = Mutations.setGapDuration(at: 0, duration: .seconds(-1), in: seq)
        // Duration must be at least 1 tick (non-zero positive)
        XCTAssertGreaterThan(out.spine[0].duration, .zero)
    }

    func testSetGapDurationOnClipIsNoop() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let seq = Sequence(spine: [.clip(a)])
        let out = Mutations.setGapDuration(at: 0, duration: .seconds(5), in: seq)
        XCTAssertEqual(out, seq)
    }

    func testSetGapDurationOutOfBoundsIsNoop() {
        let seq = Sequence(spine: [.gap(duration: .seconds(3))])
        let out = Mutations.setGapDuration(at: 5, duration: .seconds(5), in: seq)
        XCTAssertEqual(out, seq)
    }
}
