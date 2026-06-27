import Foundation

/// Agent LLM 配置。默认 stepfun(OpenAI 兼容),API key 读环境变量 STEP_API_KEY。
/// 可用 FCPX_LLM_BASE_URL / FCPX_LLM_MODEL / FCPX_LLM_API_KEY 覆盖。
struct AgentConfig {
    let baseURL: String
    let apiKey: String
    let model: String

    static func fromEnvironment() -> AgentConfig? {
        let e = ProcessInfo.processInfo.environment
        // key:优先 FCPX_LLM_API_KEY,否则 STEP_API_KEY
        guard let key = (e["FCPX_LLM_API_KEY"]?.nilIfEmpty) ?? (e["STEP_API_KEY"]?.nilIfEmpty) else { return nil }
        let base = e["FCPX_LLM_BASE_URL"]?.nilIfEmpty ?? "https://api.stepfun.com/v1"
        let model = e["FCPX_LLM_MODEL"]?.nilIfEmpty ?? "step-3.7-flash"
        return AgentConfig(baseURL: base, apiKey: key, model: model)
    }
}

private extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}

/// OpenAI 兼容 Chat Completions + function calling 后端。
/// 指向任何支持 tools 的 OpenAI 兼容端点即可。
struct OpenAILLMBackend: LLMBackend {
    let config: AgentConfig

    enum BackendError: LocalizedError {
        case http(Int, String), badResponse
        var errorDescription: String? {
            switch self {
            case .http(let c, let b): return "请求失败 [\(c)] \(b.prefix(200))"
            case .badResponse: return "模型返回格式异常"
            }
        }
    }

    private var endpoint: URL {
        var base = config.baseURL.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base.removeLast() }
        let full = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        return URL(string: full)!
    }

    func send(messages: [LLMWireMessage], tools: [[String: Any]]) async throws -> LLMTurn {
        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0.2,
            "tool_choice": "auto",
            "tools": tools,
            "messages": messages.map(Self.wireToJSON),
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw BackendError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any] else {
            throw BackendError.badResponse
        }
        let content = msg["content"] as? String
        var calls: [LLMToolCall] = []
        if let tcs = msg["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                guard let id = tc["id"] as? String,
                      let fn = tc["function"] as? [String: Any],
                      let name = fn["name"] as? String else { continue }
                let argStr = fn["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argStr.utf8))) as? [String: Any] ?? [:]
                calls.append(LLMToolCall(id: id, name: name, args: args))
            }
        }
        return LLMTurn(text: content, toolCalls: calls)
    }

    /// LLMWireMessage → OpenAI 消息 JSON。
    private static func wireToJSON(_ m: LLMWireMessage) -> [String: Any] {
        var d: [String: Any] = ["role": m.role]
        d["content"] = m.content ?? ""
        if let tcs = m.toolCalls {
            d["tool_calls"] = tcs.map { tc in
                ["id": tc.id, "type": "function",
                 "function": ["name": tc.name,
                              "arguments": (try? String(data: JSONSerialization.data(withJSONObject: tc.args), encoding: .utf8)) ?? "{}"]]
            }
        }
        if let id = m.toolCallId { d["tool_call_id"] = id }
        if m.role == "tool", let n = m.name { d["name"] = n }
        return d
    }
}
