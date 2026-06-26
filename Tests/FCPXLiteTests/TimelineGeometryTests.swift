import XCTest
@testable import FCPXLite

final class TimelineGeometryTests: XCTestCase {

    // Build a spine: A(2s) then B(3s)
    // At 60px/s:
    //   A: x=0..120, center=60
    //   B: x=120..300, center=210
    //
    // insertionIndex(forX: 0) → 0   (no center is left of 0)
    // insertionIndex(forX: 61) → 1  (A's center=60 is left of 61)
    // insertionIndex(forX: 1000) → 2 (both centers left of 1000)

    private func makeSequence() -> (Sequence, ClipID, ClipID) {
        let idA = ClipID(); let idB = ClipID()
        let clipA = Clip(id: idA, assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let clipB = Clip(id: idB, assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let seq = Sequence(spine: [.clip(clipA), .clip(clipB)])
        return (seq, idA, idB)
    }

    func testInsertionIndexAtZero() {
        let (seq, _, _) = makeSequence()
        let idx = TimelineGeometry.insertionIndex(forX: 0, sequence: seq, pxPerSecond: 60)
        XCTAssertEqual(idx, 0)
    }

    func testInsertionIndexPastFirstCenter() {
        let (seq, _, _) = makeSequence()
        // A's center = (0 + 1) * 60 = 60px; just past it
        let idx = TimelineGeometry.insertionIndex(forX: 61, sequence: seq, pxPerSecond: 60)
        XCTAssertEqual(idx, 1)
    }

    func testInsertionIndexLarge() {
        let (seq, _, _) = makeSequence()
        let idx = TimelineGeometry.insertionIndex(forX: 1000, sequence: seq, pxPerSecond: 60)
        XCTAssertEqual(idx, 2)
    }

    func testInsertionIndexEmptySpine() {
        let seq = Sequence(spine: [])
        let idx = TimelineGeometry.insertionIndex(forX: 100, sequence: seq, pxPerSecond: 60)
        XCTAssertEqual(idx, 0)
    }

    func testInsertionIndexBeforeFirstCenter() {
        let (seq, _, _) = makeSequence()
        // A's center = 60px; at x=59 nothing is to the left → 0
        let idx = TimelineGeometry.insertionIndex(forX: 59, sequence: seq, pxPerSecond: 60)
        XCTAssertEqual(idx, 0)
    }

    func testSpineIndexFindsClipA() {
        let (seq, idA, _) = makeSequence()
        let idx = TimelineGeometry.spineIndex(ofClipID: idA, in: seq)
        XCTAssertEqual(idx, 0)
    }

    func testSpineIndexFindsClipB() {
        let (seq, _, idB) = makeSequence()
        let idx = TimelineGeometry.spineIndex(ofClipID: idB, in: seq)
        XCTAssertEqual(idx, 1)
    }

    func testSpineIndexReturnsNilForUnknownID() {
        let (seq, _, _) = makeSequence()
        let unknown = ClipID()
        let idx = TimelineGeometry.spineIndex(ofClipID: unknown, in: seq)
        XCTAssertNil(idx)
    }

    func testSpineIndexEmptySpine() {
        let seq = Sequence(spine: [])
        let idx = TimelineGeometry.spineIndex(ofClipID: ClipID(), in: seq)
        XCTAssertNil(idx)
    }

    // MARK: - 画布坐标几何

    func testSecondsToXAndBack() {
        XCTAssertEqual(TimelineGeometry.x(forSeconds: 2, pxPerSecond: 60), 120)
        XCTAssertEqual(TimelineGeometry.seconds(forX: 120, pxPerSecond: 60), 2, accuracy: 1e-9)
    }

    func testSecondsForXClampsToZero() {
        // 负 x → clamp 到 0
        XCTAssertEqual(TimelineGeometry.seconds(forX: -50, pxPerSecond: 60), 0, accuracy: 1e-9)
    }

    func testSecondsForXZeroPxIsZero() {
        XCTAssertEqual(TimelineGeometry.seconds(forX: 100, pxPerSecond: 0), 0, accuracy: 1e-9)
    }

    func testLaneTopYCentersLane0() {
        // contentHeight=600, ruler=24, laneHeight=44, gap=4 → step=48
        // centerY = 24 + (600-24)/2 = 24 + 288 = 312; lane0Top = 312 - 22 = 290
        let h: CGFloat = 44, gap: CGFloat = 4, ruler: CGFloat = 24, content: CGFloat = 600
        let lane0 = TimelineGeometry.laneTopY(lane: 0, rulerHeight: ruler, laneHeight: h, laneGap: gap, contentHeight: content)
        XCTAssertEqual(lane0, 290, accuracy: 1e-6)
        // lane0 行心 ≈ 画布心
        let lane0Center = lane0 + h / 2
        XCTAssertEqual(lane0Center, content / 2 + ruler / 2, accuracy: 1e-6)

        // lane +1 在上方:y 更小
        let lane1 = TimelineGeometry.laneTopY(lane: 1, rulerHeight: ruler, laneHeight: h, laneGap: gap, contentHeight: content)
        XCTAssertEqual(lane1, 290 - 48, accuracy: 1e-6)
        XCTAssertLessThan(lane1, lane0)
        // lane -1 在下方:y 更大
        let laneNeg1 = TimelineGeometry.laneTopY(lane: -1, rulerHeight: ruler, laneHeight: h, laneGap: gap, contentHeight: content)
        XCTAssertEqual(laneNeg1, 290 + 48, accuracy: 1e-6)
        XCTAssertGreaterThan(laneNeg1, lane0)
    }

    func testLaneForYRoundTrips() {
        let h: CGFloat = 44, gap: CGFloat = 4, ruler: CGFloat = 24, content: CGFloat = 600
        for lane in [-2, -1, 0, 1, 2, 3] {
            let top = TimelineGeometry.laneTopY(lane: lane, rulerHeight: ruler, laneHeight: h, laneGap: gap, contentHeight: content)
            let centerY = top + h / 2
            let got = TimelineGeometry.lane(forY: centerY, rulerHeight: ruler, laneHeight: h, laneGap: gap, contentHeight: content)
            XCTAssertEqual(got, lane, "y at lane \(lane) center should map back")
        }
    }

    func testTickIntervalAdaptsToZoom() {
        // 60px/s,目标 80px:1s*60=60 <80,2s*60=120 ≥80 → 2
        XCTAssertEqual(TimelineGeometry.tickIntervalSeconds(pxPerSecond: 60), 2, accuracy: 1e-9)
        // 大缩放 200px/s:1s*200=200 ≥80 → 1
        XCTAssertEqual(TimelineGeometry.tickIntervalSeconds(pxPerSecond: 200), 1, accuracy: 1e-9)
        // 极小缩放 8px/s:10s*8=80 ≥80 → 10
        XCTAssertEqual(TimelineGeometry.tickIntervalSeconds(pxPerSecond: 8), 10, accuracy: 1e-9)
    }
}
