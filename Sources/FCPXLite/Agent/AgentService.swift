import Foundation

/// Agent 流式对话循环:用户消息 → LLM(流式,带工具+时间线状态)→ 实时显示文本/推理/工具调用 →
/// 执行工具(改剪辑)→ 结果喂回 → 循环到最终回复。可中止(stop)。
/// 消息流实时写入 store.agentMessages 供 Chat UI 渲染。
@MainActor
final class AgentService {
    let store: DocumentStore
    let registry: AgentToolRegistry
    let backend: StreamingLLMBackend
    let maxToolRounds: Int

    init(store: DocumentStore, backend: StreamingLLMBackend, maxToolRounds: Int = 16) {
        self.store = store
        self.registry = AgentToolRegistry(store: store)
        self.backend = backend
        self.maxToolRounds = maxToolRounds
    }

    private static let systemPrompt = """
    你是 FCPX-lite(一个简化版 Final Cut Pro)的剪辑助手。用户用中文描述剪辑意图,你用提供的工具操作时间线。
    规则:
    1. 动手前先调用 get_timeline 了解素材库与当前时间线。
    2. 一步步用工具完成,每个工具调用后会收到结果。
    3. 时间用秒,素材用 assetIndex(素材库索引),主轴片段用 spineIndex。
    4. 叠加/画中画用 connect_clip 到 lane>0,并可用 set_adjust 缩小上层(scale<1)露出下层。
    5. 完成所有工具操作后,【必须】再用一句简短中文总结你做了什么(不要只调工具就结束)。
    """

    /// 处理一条用户消息(流式)。返回时整轮结束或被取消。
    func send(userText: String) async {
        store.agentMessages.append(AgentMessage(role: .user, text: userText))
        store.agentBusy = true
        defer { store.agentBusy = false }

        var wire: [LLMWireMessage] = [
            LLMWireMessage(role: "system", content: Self.systemPrompt + "\n\n当前状态:\n" + registry.timelineSummary()),
        ]
        for m in store.agentMessages where m.role != .tool {
            wire.append(LLMWireMessage(role: m.role == .user ? "user" : "assistant", content: m.text))
        }

        for _ in 0..<maxToolRounds {
            if Task.isCancelled { markStopped(); return }

            // 本轮的实时 assistant 气泡
            let asstId = UUID()
            store.agentMessages.append(AgentMessage(id: asstId, role: .assistant, text: "", streaming: true))
            var asstText = ""; var asstThink = ""
            var roundCalls: [LLMToolCall] = []
            var toolMsgIds: [String: UUID] = [:]   // toolCall.id → 对应的 tool 气泡

            do {
                for try await ev in backend.stream(messages: wire, tools: registry.toolsJSON()) {
                    if Task.isCancelled { markStopped(); return }
                    switch ev {
                    case .textDelta(let d):
                        asstText += d; updateMsg(asstId) { $0.text = asstText }
                    case .thinkDelta(let d):
                        asstThink += d; updateMsg(asstId) { $0.think = asstThink }
                    case .toolCallBegin(let id, let name):
                        let tid = UUID(); toolMsgIds[id] = tid
                        store.agentMessages.append(AgentMessage(id: tid, role: .tool, text: "调用中…", toolName: name, toolArgs: "", streaming: true))
                    case .toolCallArg(let id, let chunk):
                        if let tid = toolMsgIds[id] { updateMsg(tid) { $0.toolArgs = ($0.toolArgs ?? "") + chunk } }
                    case .toolCallEnd(let id, let name, let args):
                        roundCalls.append(LLMToolCall(id: id, name: name, args: args))
                        _ = id
                    case .error(let m):
                        updateMsg(asstId) { $0.text = (asstText.isEmpty ? "" : asstText + "\n") + "出错:" + m; $0.streaming = false }
                        return
                    case .done: break
                    }
                }
            } catch {
                updateMsg(asstId) { $0.text = "出错:\(error.localizedDescription)"; $0.streaming = false }
                return
            }

            updateMsg(asstId) { $0.streaming = false }

            if roundCalls.isEmpty { return }   // 最终回复,结束

            // assistant 发起工具调用 → 执行 → 结果喂回
            wire.append(LLMWireMessage(role: "assistant", content: asstText, toolCalls: roundCalls))
            for tc in roundCalls {
                let result = registry.execute(name: tc.name, args: tc.args)   // ← 真正改剪辑
                if let tid = toolMsgIds[tc.id] {
                    updateMsg(tid) { $0.text = result; $0.streaming = false }
                } else {
                    store.agentMessages.append(AgentMessage(role: .tool, text: result, toolName: tc.name))
                }
                wire.append(LLMWireMessage(role: "tool", content: result, toolCallId: tc.id, name: tc.name))
            }
        }
        store.agentMessages.append(AgentMessage(role: .assistant, text: "(已达到最大工具步数,停止)"))
    }

    private func updateMsg(_ id: UUID, _ f: (inout AgentMessage) -> Void) {
        if let i = store.agentMessages.firstIndex(where: { $0.id == id }) { f(&store.agentMessages[i]) }
    }
    private func markStopped() {
        for i in store.agentMessages.indices where store.agentMessages[i].streaming {
            store.agentMessages[i].streaming = false
        }
        store.agentMessages.append(AgentMessage(role: .assistant, text: "(已停止)"))
    }
}
