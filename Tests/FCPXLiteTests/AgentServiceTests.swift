import XCTest
@testable import FCPXLite

/// 用 mock LLM 后端验证 Agent 对话循环:工具调用→执行(改剪辑)→结果喂回→最终文本,不依赖真 API。
@MainActor
final class AgentServiceTests: XCTestCase {

    /// 脚本化 mock:按预设的回合顺序返回(每次 send 取下一个)。
    final class MockBackend: LLMBackend {
        var turns: [LLMTurn]
        private(set) var sendCount = 0
        private(set) var lastTools: [[String: Any]] = []
        init(_ turns: [LLMTurn]) { self.turns = turns }
        func send(messages: [LLMWireMessage], tools: [[String: Any]]) async throws -> LLMTurn {
            lastTools = tools
            defer { sendCount += 1 }
            return sendCount < turns.count ? turns[sendCount] : LLMTurn(text: "done", toolCalls: [])
        }
    }

    private func store() -> DocumentStore {
        let s = DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                 assetLibrary: [], sequence: Sequence(spine: [])))
        s.dispatch(.importAsset(Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/truck.mov"),
                                      kind: .video, duration: .seconds(5),
                                      naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)))
        return s
    }

    func testAgentExecutesToolThenReplies() async {
        let s = store()
        // 回合1: 调 append_clip;回合2: 纯文本结束
        let mock = MockBackend([
            LLMTurn(text: nil, toolCalls: [LLMToolCall(id: "1", name: "append_clip", args: ["assetIndex": 0])]),
            LLMTurn(text: "已把素材追加到时间线。", toolCalls: []),
        ])
        let svc = AgentService(store: s, backend: mock)
        await svc.send(userText: "把第一个素材加到时间线")

        // 剪辑真的变了
        XCTAssertEqual(s.document.sequence.spine.count, 1)
        // 消息流:user → tool(结果) → assistant(最终)
        XCTAssertEqual(s.agentMessages.map(\.role), [.user, .tool, .assistant])
        XCTAssertEqual(s.agentMessages.last?.text, "已把素材追加到时间线。")
        XCTAssertFalse(s.agentBusy)
        // 工具列表确实传给了 LLM
        XCTAssertGreaterThan(mock.lastTools.count, 8)
    }

    func testMultiToolSequence() async {
        let s = store()
        // append, 再 blade, 再结束
        let mock = MockBackend([
            LLMTurn(text: nil, toolCalls: [LLMToolCall(id: "1", name: "append_clip", args: ["assetIndex": 0])]),
            LLMTurn(text: nil, toolCalls: [LLMToolCall(id: "2", name: "blade_clip", args: ["atSeconds": 2.0])]),
            LLMTurn(text: "完成:已追加并在2秒处切割。", toolCalls: []),
        ])
        let svc = AgentService(store: s, backend: mock)
        await svc.send(userText: "加进去然后在2秒切一刀")
        XCTAssertEqual(s.document.sequence.spine.count, 2)   // 切成两段
        XCTAssertEqual(mock.sendCount, 3)
        XCTAssertEqual(s.agentMessages.filter { $0.role == .tool }.count, 2)
    }

    func testBackendErrorSurfaces() async {
        struct FailBackend: LLMBackend {
            func send(messages: [LLMWireMessage], tools: [[String: Any]]) async throws -> LLMTurn {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "网络炸了"])
            }
        }
        let s = store()
        let svc = AgentService(store: s, backend: FailBackend())
        await svc.send(userText: "x")
        XCTAssertTrue(s.agentMessages.last?.text.contains("网络炸了") ?? false)
        XCTAssertFalse(s.agentBusy)
    }
}
