import XCTest
@testable import FCPXLite

final class MutationReanchorTests: XCTestCase {
    private func clip(_ secs: Double, sourceIn: Time = .zero,
                      connected: [Clip] = []) -> Clip {
        Clip(assetID: AssetID(), sourceIn: sourceIn,
             duration: .seconds(secs), connected: connected)
    }

    private func connectedClip(_ secs: Double, lane: Int, offset: Time) -> Clip {
        Clip(assetID: AssetID(), sourceIn: .zero,
             duration: .seconds(secs), lane: lane, offset: offset)
    }

    /// rippleDelete:删宿主后 connected 子节点重锚到相邻主轴 clip,绝对位置不变
    func testRippleDeleteReanchorsConnectedToNeighbor() {
        // spine: A(2s, child@lane1,offset1s) ; B(3s)
        // child abs = 0 + 1 = 1s
        let child = connectedClip(1, lane: 1, offset: .seconds(1))
        let a = clip(2, connected: [child])
        let b = clip(3)
        let seq0 = Sequence(spine: [.clip(a), .clip(b)])

        let seq1 = Mutations.rippleDelete(at: 0, in: seq0)

        // 删 A 后只剩 B(absStart=0),child 应重锚到 B
        XCTAssertEqual(seq1.spine.count, 1, "spine 应只剩 1 个元素")
        let bNew = seq1.spine[0].asClip
        XCTAssertNotNil(bNew, "剩余元素应是 clip")
        XCTAssertEqual(bNew!.connected.count, 1, "child 不得丢失")

        // 通过 Layout 验证绝对位置保持 1s
        let placed = Layout.compute(seq1)
        let connPlaced = placed.first { $0.isConnected }
        XCTAssertNotNil(connPlaced, "Layout 中应能找到 connected clip")
        XCTAssertEqual(connPlaced!.absStart, .seconds(1),
                       "re-anchor 后绝对时间线位置应保持 1s")
    }

    /// liftDelete:宿主变 gap 后 connected 子节点重锚到最近主轴 clip,绝对位置不变
    func testLiftDeleteReanchorsConnected() {
        // spine: A(2s, child@lane1,offset1s) ; B(3s)
        // child abs = 0 + 1 = 1s
        let child = connectedClip(1, lane: 1, offset: .seconds(1))
        let a = clip(2, connected: [child])
        let b = clip(3)
        let seq0 = Sequence(spine: [.clip(a), .clip(b)])

        let seq1 = Mutations.liftDelete(at: 0, in: seq0)

        // spine[0] 变成 gap,spine[1] 仍为 B(absStart=2)
        XCTAssertEqual(seq1.spine.count, 2)
        if case .gap = seq1.spine[0] {} else {
            XCTFail("spine[0] 应变为 gap")
        }
        let bNew = seq1.spine[1].asClip
        XCTAssertNotNil(bNew, "B 仍应是 clip")
        XCTAssertEqual(bNew!.connected.count, 1, "child 不得丢失")

        // child 绝对位置仍为 1s
        let placed = Layout.compute(seq1)
        let connPlaced = placed.first { $0.isConnected }
        XCTAssertNotNil(connPlaced)
        XCTAssertEqual(connPlaced!.absStart, .seconds(1),
                       "liftDelete 后 re-anchor 绝对时间线位置应保持 1s")
    }

    /// moveClip:移动宿主时 connected 子节点应随宿主一起移动(不重锚)
    func testMoveHostCarriesConnected() {
        // spine: A(2s, child@lane1,offset0.5s) ; B(3s) ; C(1s)
        let child = connectedClip(1, lane: 1, offset: .seconds(0.5))
        let a = clip(2, connected: [child])
        let b = clip(3)
        let c = clip(1)
        let seq0 = Sequence(spine: [.clip(a), .clip(b), .clip(c)])

        // 把 A 从 index 0 移到 index 2
        let seq1 = Mutations.moveClip(from: 0, to: 2, in: seq0)

        // 结果 spine: B(3)@0, C(1)@3, A(2)@4
        let spineClips = seq1.spine.compactMap { $0.asClip }
        XCTAssertEqual(spineClips.count, 3)

        // A 应该仍带着 child(count=1)
        let aNew = spineClips.last
        XCTAssertNotNil(aNew)
        XCTAssertEqual(aNew!.connected.count, 1, "moveClip 后 connected child 应随宿主移动")

        // Layout 中 child 的 absStart = A 新的 absStart(4s) + offset(0.5s) = 4.5s
        let placed = Layout.compute(seq1)
        let aPlaced = placed.first { !$0.isConnected && $0.clipID == aNew!.id }
        let connPlaced = placed.first { $0.isConnected }
        XCTAssertNotNil(aPlaced)
        XCTAssertNotNil(connPlaced)
        XCTAssertEqual(aPlaced!.absStart, .seconds(4))
        XCTAssertEqual(connPlaced!.absStart, .seconds(4.5),
                       "child 应随宿主移动,absStart = 新宿主起点 + offset")
    }

    /// 删除宿主后不变量依然通过(无 laneCollision,无 negativeDuration)
    func testDeleteHostWithConnectedPreservesInvariants() {
        let child = connectedClip(1, lane: 1, offset: .seconds(0.5))
        let a = clip(2, connected: [child])
        let b = clip(4)
        let seq0 = Sequence(spine: [.clip(a), .clip(b)])

        let seq1 = Mutations.rippleDelete(at: 0, in: seq0)

        XCTAssertNoThrow(try Invariants.check(seq1),
                         "re-anchor 后不变量应通过")
    }
}
