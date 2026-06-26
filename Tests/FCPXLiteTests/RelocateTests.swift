import XCTest
@testable import FCPXLite

/// Part 1 —— relocate 纯逻辑:把 clip 在主轴/连接片段之间挪位置(磁性换轨)。
final class RelocateTests: XCTestCase {

    // spine [A(2s), B(3s)];把 B 挪到 lane 1 @ 0.5s → B 离开主轴,作为 A 的连接子项出现。
    func testRelocateSpineClipToLane1Connects() {
        let idA = ClipID(); let idB = ClipID()
        let a = Clip(id: idA, assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let b = Clip(id: idB, assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let seq = Sequence(spine: [.clip(a), .clip(b)])

        let out = Mutations.relocate(clipID: idB, toLane: 1, atTime: .seconds(0.5), in: seq)

        // 主轴现在只剩 A
        XCTAssertEqual(out.spine.count, 1)
        guard case .clip(let onlySpine) = out.spine[0] else { return XCTFail("spine[0] not a clip") }
        XCTAssertEqual(onlySpine.id, idA)

        // 布局里恰好一个连接片段在 lane 1,absStart≈0.5s
        let placed = Layout.compute(out)
        let connected = placed.filter { $0.isConnected }
        XCTAssertEqual(connected.count, 1)
        XCTAssertEqual(connected[0].lane, 1)
        XCTAssertEqual(connected[0].absStart.seconds, 0.5, accuracy: 1e-6)
        XCTAssertEqual(connected[0].clipID, idB)
    }

    // 从一个连接子项(host 上 lane1 offset1s)出发,把它挪回 lane 0 @ 主轴末尾 → 变成主轴 clip。
    func testRelocateConnectedBackToSpine() {
        let idHost = ClipID(); let idChild = ClipID()
        let child = Clip(id: idChild, assetID: AssetID(), sourceIn: .zero, duration: .seconds(1),
                         lane: 1, offset: .seconds(1))
        let host = Clip(id: idHost, assetID: AssetID(), sourceIn: .zero, duration: .seconds(4),
                        connected: [child])
        let seq = Sequence(spine: [.clip(host)])

        // 主轴末尾 = host 时长 4s
        let out = Mutations.relocate(clipID: idChild, toLane: 0, atTime: .seconds(4), in: seq)

        // child 变成主轴 clip 被追加;host.connected 清空
        XCTAssertEqual(out.spine.count, 2)
        guard case .clip(let h) = out.spine[0] else { return XCTFail("spine[0] not a clip") }
        XCTAssertTrue(h.connected.isEmpty)
        guard case .clip(let appended) = out.spine[1] else { return XCTFail("spine[1] not a clip") }
        XCTAssertEqual(appended.id, idChild)
        XCTAssertEqual(appended.lane, 0)

        let placed = Layout.compute(out)
        XCTAssertTrue(placed.allSatisfy { !$0.isConnected })
    }

    // spine [A(2s),B(3s),C(1s)];把 A 挪到 lane 0 @ 5.5s(B 之后)→ A 不再在首位,布局连续无缝。
    func testRelocateReordersWithinSpine() {
        let idA = ClipID(); let idB = ClipID(); let idC = ClipID()
        let a = Clip(id: idA, assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let b = Clip(id: idB, assetID: AssetID(), sourceIn: .zero, duration: .seconds(3))
        let c = Clip(id: idC, assetID: AssetID(), sourceIn: .zero, duration: .seconds(1))
        let seq = Sequence(spine: [.clip(a), .clip(b), .clip(c)])

        let out = Mutations.relocate(clipID: idA, toLane: 0, atTime: .seconds(5.5), in: seq)

        // 仍是 3 个 spine 元素,A 不再首位
        XCTAssertEqual(out.spine.count, 3)
        guard case .clip(let first) = out.spine[0] else { return XCTFail("spine[0] not a clip") }
        XCTAssertNotEqual(first.id, idA)

        // 布局连续无缝:每个 clip 的 absStart == 前一个的 end
        let placed = Layout.compute(out).sorted { $0.absStart < $1.absStart }
        var expected = Time.zero
        for p in placed {
            XCTAssertEqual(p.absStart.seconds, expected.seconds, accuracy: 1e-6)
            expected = expected + p.duration
        }
        XCTAssertNoThrow(try Invariants.check(out))
    }

    // 未知 id → 原样返回。
    func testRelocateUnknownIdNoop() {
        let a = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(2))
        let seq = Sequence(spine: [.clip(a)])
        let out = Mutations.relocate(clipID: ClipID(), toLane: 1, atTime: .seconds(0.5), in: seq)
        XCTAssertEqual(out, seq)
    }
}
