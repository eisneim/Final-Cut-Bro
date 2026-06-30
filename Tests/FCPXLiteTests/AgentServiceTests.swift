import XCTest
@testable import FCPXLite

/// 用 mock 流式后端验证 Agent 对话循环:工具调用→执行(改剪辑)→结果喂回→最终文本,不依赖真 API。
@MainActor
final class AgentServiceTests: XCTestCase {

    /// 脚本化 mock:每次 stream 返回预设回合的事件序列。
    final class MockBackend: StreamingLLMBackend {
        var rounds: [[AgentStreamEvent]]
        private(set) var streamCount = 0
        private(set) var lastTools: [[String: Any]] = []
        init(_ rounds: [[AgentStreamEvent]]) { self.rounds = rounds }
        func stream(messages: [LLMWireMessage], tools: [[String: Any]]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
            lastTools = tools
            let evs = streamCount < rounds.count ? rounds[streamCount] : [.done]
            streamCount += 1
            return AsyncThrowingStream { cont in
                for e in evs { cont.yield(e) }
                cont.finish()
            }
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
        let mock = MockBackend([
            [.toolCallEnd(id: "1", name: "timeline_edit", args: ["type": "append", "assetIndex": 0]), .done],
            [.textDelta("已把素材"), .textDelta("追加到时间线。"), .done],
        ])
        let svc = AgentService(store: s, backend: mock)
        await svc.send(userText: "把第一个素材加到时间线")

        XCTAssertEqual(s.document.sequence.spine.count, 1)               // 剪辑真的变了
        XCTAssertEqual(s.agentMessages.last?.role, .assistant)
        XCTAssertEqual(s.agentMessages.last?.text, "已把素材追加到时间线。")  // 流式拼接
        XCTAssertFalse(s.agentBusy)
        XCTAssertEqual(mock.lastTools.count, 5)                          // 5 个 dispatch 工具传给 LLM
        XCTAssertTrue(s.agentMessages.contains { $0.role == .tool && $0.toolName == "timeline_edit" })
    }

    func testMultiToolSequence() async {
        let s = store()
        let mock = MockBackend([
            [.toolCallEnd(id: "1", name: "timeline_edit", args: ["type": "append", "assetIndex": 0]), .done],
            [.toolCallEnd(id: "2", name: "timeline_edit", args: ["type": "blade", "clipIndex": 0, "atSeconds": 2.0]), .done],
            [.textDelta("完成。"), .done],
        ])
        let svc = AgentService(store: s, backend: mock)
        await svc.send(userText: "加进去然后在2秒切一刀")
        XCTAssertEqual(s.document.sequence.spine.count, 2)              // 切成两段
        XCTAssertEqual(mock.streamCount, 3)
        XCTAssertEqual(s.agentMessages.filter { $0.role == .tool }.count, 2)
    }

    func testThinkDeltaShown() async {
        let s = store()
        let mock = MockBackend([
            [.thinkDelta("我先看看时间线"), .textDelta("好的。"), .done],
        ])
        let svc = AgentService(store: s, backend: mock)
        await svc.send(userText: "你好")
        let asst = s.agentMessages.last { $0.role == .assistant }
        XCTAssertEqual(asst?.think, "我先看看时间线")
        XCTAssertEqual(asst?.text, "好的。")
    }

    func testThinkSplitterInlineTags() {
        var sp = ThinkSplitter()
        let (v1, t1) = sp.feed("hello<think>reason")
        XCTAssertEqual(v1, "hello"); XCTAssertEqual(t1, "reason")
        let (v2, t2) = sp.feed("ing</think>world")
        XCTAssertEqual(t2, "ing"); XCTAssertEqual(v2, "world")
    }

    func testThinkSplitterSplitTagAcrossDeltas() {
        var sp = ThinkSplitter()
        let (v1, _) = sp.feed("abc<thi")          // 半个标签
        XCTAssertEqual(v1, "abc")
        let (v2, t2) = sp.feed("nk>secret")        // 补全
        XCTAssertEqual(v2, ""); XCTAssertEqual(t2, "secret")
    }
}
