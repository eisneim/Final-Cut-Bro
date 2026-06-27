import Foundation

/// Agent 对话消息(进 store,Redux 纪律:UI 是消息列表的纯函数)。
struct AgentMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant, tool }
    let id: UUID
    let role: Role
    var text: String
    var toolName: String?       // role == .tool 时:执行的工具名
    init(id: UUID = UUID(), role: Role, text: String, toolName: String? = nil) {
        self.id = id; self.role = role; self.text = text; self.toolName = toolName
    }
}

/// LLM 一轮返回:要么是文本回复,要么是一组工具调用。
struct LLMTurn {
    let text: String?
    let toolCalls: [LLMToolCall]
}
struct LLMToolCall {
    let id: String
    let name: String
    let args: [String: Any]
}

/// 发给 LLM 的消息(wire 格式,role + content + 可选 tool 信息)。
struct LLMWireMessage {
    let role: String                 // system/user/assistant/tool
    var content: String?
    var toolCalls: [LLMToolCall]?    // assistant 发起的调用
    var toolCallId: String?          // tool 结果对应的调用 id
    var name: String?                // tool 结果的工具名
}

/// LLM 后端抽象:生产接真 API,自测注入 mock。
protocol LLMBackend {
    func send(messages: [LLMWireMessage], tools: [[String: Any]]) async throws -> LLMTurn
}
