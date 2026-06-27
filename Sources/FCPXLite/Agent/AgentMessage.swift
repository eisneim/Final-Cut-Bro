import Foundation

/// Agent 对话消息(进 store,Redux 纪律)。
struct AgentMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant, tool }
    let id: UUID
    let role: Role
    var text: String
    var think: String = ""          // assistant 的推理过程(可折叠展示)
    var toolName: String? = nil     // role == .tool 时:执行的工具名
    var toolArgs: String? = nil     // 工具参数(流式展示)
    var streaming: Bool = false     // 是否正在流式输出
    init(id: UUID = UUID(), role: Role, text: String, think: String = "",
         toolName: String? = nil, toolArgs: String? = nil, streaming: Bool = false) {
        self.id = id; self.role = role; self.text = text; self.think = think
        self.toolName = toolName; self.toolArgs = toolArgs; self.streaming = streaming
    }
}

/// 发给 LLM 的消息(wire 格式)。
struct LLMWireMessage {
    let role: String                 // system/user/assistant/tool
    var content: String?
    var toolCalls: [LLMToolCall]?    // assistant 发起的调用
    var toolCallId: String?          // tool 结果对应的调用 id
    var name: String?                // tool 结果的工具名
}
struct LLMToolCall {
    let id: String
    let name: String
    let args: [String: Any]
}

/// 流式事件(LLM 边生成边发)。
enum AgentStreamEvent {
    case textDelta(String)                          // 可见文本增量
    case thinkDelta(String)                         // 推理增量
    case toolCallBegin(id: String, name: String)
    case toolCallArg(id: String, chunk: String)     // arguments 增量
    case toolCallEnd(id: String, name: String, args: [String: Any])
    case done
    case error(String)
}

/// 流式 LLM 后端抽象(生产=真 API,自测=mock)。返回有序事件流,可被取消。
protocol StreamingLLMBackend {
    func stream(messages: [LLMWireMessage], tools: [[String: Any]]) -> AsyncThrowingStream<AgentStreamEvent, Error>
}

/// 内联 `<think>…</think>` 剥离器(MiniMax 把推理写在 content 里;stepfun/deepseek 用独立 reasoning_content)。
/// 逐 delta 喂入,返回 (可见文本, 推理文本);跨 delta 的标签用尾缓冲处理。
struct ThinkSplitter {
    private var inThink = false
    private var tail = ""   // 可能是半个标签的尾巴

    mutating func feed(_ delta: String) -> (visible: String, think: String) {
        var buf = tail + delta
        tail = ""
        var visible = ""; var think = ""
        while !buf.isEmpty {
            if inThink {
                if let r = buf.range(of: "</think>") {
                    think += buf[buf.startIndex..<r.lowerBound]
                    buf = String(buf[r.upperBound...]); inThink = false
                } else if let partial = partialTagTail(buf, tag: "</think>") {
                    think += buf[buf.startIndex..<partial]; tail = String(buf[partial...]); buf = ""
                } else { think += buf; buf = "" }
            } else {
                if let r = buf.range(of: "<think>") {
                    visible += buf[buf.startIndex..<r.lowerBound]
                    buf = String(buf[r.upperBound...]); inThink = true
                } else if let partial = partialTagTail(buf, tag: "<think>") {
                    visible += buf[buf.startIndex..<partial]; tail = String(buf[partial...]); buf = ""
                } else { visible += buf; buf = "" }
            }
        }
        return (visible, think)
    }

    /// 若 buf 尾部是 tag 的真前缀(如 "<thi"),返回该前缀起点,以便缓冲到下个 delta。
    private func partialTagTail(_ buf: String, tag: String) -> String.Index? {
        let maxLen = min(tag.count - 1, buf.count)
        for len in stride(from: maxLen, through: 1, by: -1) {
            let suffix = String(buf.suffix(len))
            if tag.hasPrefix(suffix) { return buf.index(buf.endIndex, offsetBy: -len) }
        }
        return nil
    }
}
