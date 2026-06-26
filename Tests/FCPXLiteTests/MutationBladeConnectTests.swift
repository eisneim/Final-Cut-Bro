import XCTest
@testable import FCPXLite

final class MutationBladeConnectTests: XCTestCase {
    private func clip(_ secs: Double, sourceIn: Time = .zero, connected: [Clip] = []) -> Clip {
        Clip(assetID: AssetID(), sourceIn: sourceIn, duration: .seconds(secs), connected: connected)
    }

    func testBladeSplitsIntoTwoSharingAsset() {
        let original = clip(6, sourceIn: .seconds(1))
        let seq0 = Sequence(spine: [.clip(original)])
        let seq1 = Mutations.blade(at: 0, localTime: .seconds(2), in: seq0) // 在 clip 内 2s 处切
        XCTAssertEqual(seq1.spine.count, 2)
        let left = seq1.spine[0].asClip!
        let right = seq1.spine[1].asClip!
        XCTAssertEqual(left.assetID, right.assetID)          // 共享素材
        XCTAssertEqual(left.assetID, original.assetID)
        XCTAssertEqual(left.duration, .seconds(2))
        XCTAssertEqual(right.duration, .seconds(4))           // 6 - 2
        XCTAssertEqual(left.sourceIn, .seconds(1))
        XCTAssertEqual(right.sourceIn, .seconds(3))           // 1 + 2
    }

    func testBladeRoutesConnectedToCorrectHalf() {
        let connLeft = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                            lane: 1, offset: .seconds(0.5))   // 在 2s 切点之前 → 留左
        let connRight = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                             lane: 1, offset: .seconds(3))    // 切点之后 → 归右, offset-2
        let original = clip(6, connected: [connLeft, connRight])
        let seq1 = Mutations.blade(at: 0, localTime: .seconds(2),
                                   in: Sequence(spine: [.clip(original)]))
        XCTAssertEqual(seq1.spine[0].asClip!.connected.count, 1)
        XCTAssertEqual(seq1.spine[1].asClip!.connected.count, 1)
        XCTAssertEqual(seq1.spine[1].asClip!.connected[0].offset, .seconds(1)) // 3 - 2
    }

    func testConnectAttachesToHost() {
        let host = clip(5)
        let conn = clip(2)
        let seq1 = Mutations.connectClip(conn, toHostIndex: 0, lane: 1, offset: .seconds(1),
                                         in: Sequence(spine: [.clip(host)]))
        let attached = seq1.spine[0].asClip!.connected
        XCTAssertEqual(attached.count, 1)
        XCTAssertEqual(attached[0].lane, 1)
        XCTAssertEqual(attached[0].offset, .seconds(1))
        // layout 中它锚在宿主起点(0)+offset(1) = 1s
        let placedConn = Layout.compute(seq1).first { $0.isConnected }
        XCTAssertEqual(placedConn?.absStart, .seconds(1))
    }

    func testBladeOutOfBoundsAndBoundaryNoop() {
        let seq0 = Sequence(spine: [.clip(clip(5))])
        // 越界 index → 原样返回不崩
        XCTAssertEqual(Mutations.blade(at: 9, localTime: .seconds(2), in: seq0), seq0)
        // 边界 localTime(0 与 等于 duration)→ 不切,spine 仍 1 个
        XCTAssertEqual(Mutations.blade(at: 0, localTime: .zero, in: seq0).spine.count, 1)
        XCTAssertEqual(Mutations.blade(at: 0, localTime: .seconds(5), in: seq0).spine.count, 1)
    }

    func testConnectOutOfBoundsReturnsUnchanged() {
        let seq0 = Sequence(spine: [.clip(clip(5))])
        XCTAssertEqual(Mutations.connectClip(clip(2), toHostIndex: 9, lane: 1,
                          offset: .seconds(1), in: seq0), seq0)
    }

    func testConnectLaneZeroRejected() {
        // lane 0 は主轴保留 → connectClip 应原样返回,宿主 connected 数量保持为 0
        let host = clip(5)
        let seq0 = Sequence(spine: [.clip(host)])
        let seq1 = Mutations.connectClip(clip(2), toHostIndex: 0, lane: 0,
                                         offset: .seconds(1), in: seq0)
        XCTAssertEqual(seq1, seq0, "lane:0 的 connectClip 应原样返回不变")
        XCTAssertEqual(seq1.spine[0].asClip!.connected.count, 0,
                       "宿主 connected 应仍为 0")
    }
}
