import Foundation

/// Agent 对话循环:用户消息 → LLM(带工具 + 当前时间线状态)→ 执行工具(改剪辑)→ 把结果喂回 → 循环
/// 直到 LLM 给出最终文本。消息流写入 store.agentMessages 供 Chat UI 渲染。
/// 这是"对话驱动剪辑"的执行引擎,LLM 后端可注入(生产=真 API,自测=mock)。
@MainActor
final class AgentService {
    let store: DocumentStore
    let registry: AgentToolRegistry
    let backend: LLMBackend
    let maxToolRounds: Int

    init(store: DocumentStore, backend: LLMBackend, maxToolRounds: Int = 8) {
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
    5. 完成后用简短中文告诉用户你做了什么。
    """

    /// 处理一条用户消息(异步)。把对话与工具结果写入 store。
    func send(userText: String) async {
        store.agentMessages.append(AgentMessage(role: .user, text: userText))
        store.agentBusy = true
        defer { store.agentBusy = false }

        var wire: [LLMWireMessage] = [
            LLMWireMessage(role: "system", content: Self.systemPrompt + "\n\n当前状态:\n" + registry.timelineSummary()),
        ]
        // 已有可见历史(user/assistant 文本)带上,供多轮上下文。
        for m in store.agentMessages where m.role != .tool {
            wire.append(LLMWireMessage(role: m.role == .user ? "user" : "assistant", content: m.text))
        }

        for _ in 0..<maxToolRounds {
            let turn: LLMTurn
            do { turn = try await backend.send(messages: wire, tools: registry.toolsJSON()) }
            catch {
                store.agentMessages.append(AgentMessage(role: .assistant, text: "出错了:\(error.localizedDescription)"))
                return
            }

            if turn.toolCalls.isEmpty {
                let text = turn.text ?? ""
                if !text.isEmpty { store.agentMessages.append(AgentMessage(role: .assistant, text: text)) }
                wire.append(LLMWireMessage(role: "assistant", content: text))
                return
            }

            // assistant 发起工具调用
            wire.append(LLMWireMessage(role: "assistant", content: turn.text, toolCalls: turn.toolCalls))
            for tc in turn.toolCalls {
                let result = registry.execute(name: tc.name, args: tc.args)   // ← 真正改剪辑
                store.agentMessages.append(AgentMessage(role: .tool, text: result, toolName: tc.name))
                wire.append(LLMWireMessage(role: "tool", content: result, toolCallId: tc.id, name: tc.name))
            }
        }
        store.agentMessages.append(AgentMessage(role: .assistant, text: "(已达到最大工具步数,停止)"))
    }
}
