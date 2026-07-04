import XCTest
@testable import FCPXLite

/// 拖拽核心修复:①手势级撤销合并(整段拖拽一次 undo,而非逐 tick);②连接片段拖回主轨道转成 spine 片段。
@MainActor
final class DragUndoCoalesceTests: XCTestCase {

    private func storeWith2Clips() -> DocumentStore {
        let a = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                      duration: .seconds(20), naturalSize: CGSize(width: 1920, height: 1080),
                      frameRate: 25, hasAudio: true)
        let store = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                     assetLibrary: [a], sequence: Sequence(spine: [])))
        store.dispatch(.insertClip(Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(6)), at: 0))
        store.dispatch(.insertClip(Clip(assetID: a.id, sourceIn: .seconds(6), duration: .seconds(6)), at: 1))
        return store
    }
    private func firstClipDur(_ s: DocumentStore) -> Double {
        guard case .clip(let c) = s.document.sequence.spine[0] else { return -1 }
        return c.duration.seconds
    }

    /// 模拟一次"拖结尾从 6s 一路拉到 12s"的多 tick 拖拽:begin 一次 → 多次 trimRight → end。
    /// ⌘Z 应【一步】回到拖拽前(6s),而不是逐 tick(逐像素)回撤。
    func testInteractiveTrimCoalescesToSingleUndo() {
        let store = storeWith2Clips()
        XCTAssertEqual(firstClipDur(store), 6, accuracy: 0.01)

        store.beginInteractiveEdit()
        for d in stride(from: 6.2, through: 12.0, by: 0.2) {   // 30 个 tick
            store.dispatch(.trimRight(at: 0, newDuration: .seconds(d), assetDuration: .seconds(20)))
        }
        store.endInteractiveEdit()
        XCTAssertEqual(firstClipDur(store), 12, accuracy: 0.01, "拖拽后结尾 12s")

        store.undo()
        XCTAssertEqual(firstClipDur(store), 6, accuracy: 0.01, "⌘Z 一步回到拖拽前 6s(合并成单次 undo)")
        // 拖拽只加了【一个】撤销层:再 undo 一次应回退到 setup 的上一步(spine 只剩 1 个 clip),
        // 证明 30 个 tick 没有各自堆 undo。
        store.undo()
        XCTAssertEqual(store.document.sequence.spine.count, 1, "第二次 undo 回退到只插入了 1 个 clip 的状态")
    }

    /// C1 回归:交互合并态中混入 transaction{} 不应提前结束合并、也不应多堆 undo。
    func testTransactionDuringInteractiveEditDoesNotBreakCoalescing() {
        let store = storeWith2Clips()
        store.beginInteractiveEdit()
        store.dispatch(.trimRight(at: 0, newDuration: .seconds(7), assetDuration: .seconds(20)))
        store.transaction {   // 合并态中内嵌事务(不应重置合并标志/不应新堆 undo)
            store.dispatch(.trimRight(at: 0, newDuration: .seconds(9), assetDuration: .seconds(20)))
        }
        store.dispatch(.trimRight(at: 0, newDuration: .seconds(11), assetDuration: .seconds(20)))
        store.endInteractiveEdit()
        XCTAssertEqual(firstClipDur(store), 11, accuracy: 0.01)
        store.undo()
        XCTAssertEqual(firstClipDur(store), 6, accuracy: 0.01, "整段(含内嵌事务)仍是一次 undo → 回到 6s")
        store.undo()
        XCTAssertEqual(store.document.sequence.spine.count, 1, "再 undo 回到 setup 上一步")
    }

    /// 对照:不合并时每次 dispatch 各留一个 undo → 需要 undo 多次。
    func testWithoutCoalesceEachTickIsSeparateUndo() {
        let store = storeWith2Clips()
        store.dispatch(.trimRight(at: 0, newDuration: .seconds(7), assetDuration: .seconds(20)))
        store.dispatch(.trimRight(at: 0, newDuration: .seconds(8), assetDuration: .seconds(20)))
        store.undo()
        XCTAssertEqual(firstClipDur(store), 7, accuracy: 0.01, "单次 undo 只回退一步")
    }

    /// 连接片段拖到 lane 0 → relocate 把它转回主轴 spine 片段(可拖回主轨道)。
    func testConnectedClipReturnsToMainLane() {
        let store = storeWith2Clips()
        // 把第 2 个 clip 变成连接片段(挂到第 1 个上)。用 connect action 造一个连接片段更直接:
        guard case .clip(let host) = store.document.sequence.spine[0] else { return XCTFail() }
        let connID = ClipID()
        let conn = Clip(id: connID, assetID: host.assetID, sourceIn: .zero, duration: .seconds(3),
                        lane: 1, offset: .seconds(1))
        var hostClip = host; hostClip.connected.append(conn)
        store.document.sequence.spine[0] = .clip(hostClip)
        XCTAssertEqual(Layout.compute(store.document.sequence).filter { $0.isConnected }.count, 1)

        // 拖到主轨道(lane 0)→ relocate 转 spine。
        store.dispatch(.relocateClip(connID, lane: 0, time: .seconds(2)))
        XCTAssertEqual(Layout.compute(store.document.sequence).filter { $0.isConnected }.count, 0,
                       "连接片段应已转回主轴(不再是 connected)")
        XCTAssertTrue(store.document.sequence.spine.contains { if case .clip(let c) = $0 { return c.id == connID }; return false },
                      "该片段现在是主轴 spine 元素")
    }
}
