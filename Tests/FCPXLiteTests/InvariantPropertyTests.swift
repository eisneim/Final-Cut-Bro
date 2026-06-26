import XCTest
@testable import FCPXLite

/// spec §8 控制变量对照实验:用数据驱动证明磁性引擎正确,杜绝肉眼猜测。
final class InvariantPropertyTests: XCTestCase {
    private func clip(_ secs: Double) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(secs))
    }

    // 多维矩阵:一批操作随机序列,每步断言三不变量恒成立。固定种子可复现。
    func testRandomOperationSequencesPreserveInvariants() {
        var rng = SeededRNG(seed: 42)
        for _ in 0..<200 {
            var seq = Sequence(spine: (0..<5).map { _ in
                Element.clip(clip(Double(rng.next(in: 1...5))))
            })
            for _ in 0..<10 {
                let op = rng.next(in: 0...3)
                let n = seq.spine.count
                guard n > 0 else { break }
                switch op {
                case 0: seq = Mutations.insertClip(clip(2), at: rng.next(in: 0...n), in: seq)
                case 1: seq = Mutations.rippleDelete(at: rng.next(in: 0...(n-1)), in: seq)
                case 2: seq = Mutations.moveClip(from: rng.next(in: 0...(n-1)),
                                                 to: rng.next(in: 0...(n-1)), in: seq)
                default: seq = Mutations.liftDelete(at: rng.next(in: 0...(n-1)), in: seq)
                }
                XCTAssertNoThrow(try Invariants.check(seq), "操作序列破坏了不变量")
            }
        }
    }

    // 顺序对照:insert-then-delete vs delete-then-insert,结果应不同但可预测。
    func testOrderMattersPredictably() {
        let base = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        let insThenDel = Mutations.rippleDelete(at: 0,
            in: Mutations.insertClip(clip(1), at: 1, in: base))
        let delThenIns = Mutations.insertClip(clip(1), at: 1,
            in: Mutations.rippleDelete(at: 0, in: base))
        let posA = ExperimentReport.placementTable(insThenDel).map(\.absStartSeconds)
        let posB = ExperimentReport.placementTable(delThenIns).map(\.absStartSeconds)
        // 顺序敏感且各自确定: insThenDel=[clip1@0, clip3@1]; delThenIns=[clip3@0, clip1@3]
        XCTAssertEqual(posA, [0, 1])
        XCTAssertEqual(posB, [0, 3])
        XCTAssertNotEqual(posA, posB)
    }

    // 参数扫描:trim duration 从 1..9,后续 clip 起点应单调左移。
    func testTrimSweepMonotonic() {
        var prevStart = Double.infinity
        for d in stride(from: 10, through: 1, by: -1) {
            let seq = Mutations.rippleTrimRight(at: 0, newDuration: .seconds(Double(d)),
                assetDuration: .seconds(20),
                in: Sequence(spine: [.clip(clip(10)), .clip(clip(2))]))
            let secondStart = ExperimentReport.placementTable(seq)[1].absStartSeconds
            XCTAssertLessThan(secondStart, prevStart, "trim 越短,后续起点应越靠左")
            prevStart = secondStart
        }
    }

    // A/B:吸附 on vs off,落点不同且可解释。
    func testSnapOnVsOff() {
        let raw = Time.seconds(2.03)
        let cands = [Time.seconds(2.0)]
        let snapped = Snapping.snap(raw, candidates: cands, threshold: .seconds(0.05))
        let notSnapped = Snapping.snap(raw, candidates: cands, threshold: .seconds(0.001))
        XCTAssertEqual(snapped, .seconds(2.0))
        XCTAssertEqual(notSnapped, raw)
    }

    func testCSVExport() {
        let seq = Sequence(spine: [.clip(clip(2)), .clip(clip(3))])
        let csv = ExperimentReport.csv(seq)
        XCTAssertTrue(csv.contains("clipID,absStart,duration,lane"))
        XCTAssertEqual(csv.split(separator: "\n").count, 3) // header + 2 rows
    }

    func testConnectedClipsAcrossLanesPreserveInvariants() {
        var seq = Sequence(spine: [.clip(clip(10))])
        for lane in 1...4 {
            seq = Mutations.connectClip(clip(2), toHostIndex: 0, lane: lane,
                                        offset: .seconds(Double(lane)), in: seq)
            XCTAssertNoThrow(try Invariants.check(seq))
        }
        let connected = Layout.compute(seq).filter(\.isConnected)
        XCTAssertEqual(connected.count, 4)
    }
}

/// 确定性 RNG(固定种子,实验可复现)。
struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func nextRaw() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func next(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(nextRaw() % span)
    }
}
