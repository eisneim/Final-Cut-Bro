import Foundation

/// OpenAI 兼容流式 Chat Completions + function calling 后端。
/// 解析 SSE:content→文本, reasoning_content→推理, tool_calls[]按 index 拼接 arguments。
/// 参考 dpdframesStudio runner._stream_once 与 shotCrafter llmProvider。
struct StreamingOpenAIBackend: StreamingLLMBackend {
    let provider: ProviderConfig
    var apiKey: String { provider.apiKey }

    private var endpoint: URL {
        var base = provider.baseURL.trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: base.hasSuffix("/chat/completions") ? base : base + "/chat/completions")!
    }

    func stream(messages: [LLMWireMessage], tools: [[String: Any]]) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do { try await self.run(messages: messages, tools: tools) { continuation.yield($0) }
                     continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(messages: [LLMWireMessage], tools: [[String: Any]],
                     emit: @escaping (AgentStreamEvent) -> Void) async throws {
        let body: [String: Any] = [
            "model": provider.model,
            "temperature": 0.3,
            "tool_choice": "auto",
            "tools": tools,
            "stream": true,
            "messages": messages.map(Self.wireToJSON),
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 180
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var msg = ""
            for try await line in bytes.lines { msg += line; if msg.count > 400 { break } }
            emit(.error("HTTP \(http.statusCode): \(msg.prefix(300))")); return
        }

        var splitter = ThinkSplitter()
        var calls: [Int: (id: String, name: String, args: String)] = [:]
        var emittedBegin = Set<Int>()

        for try await line in bytes.lines {
            if Task.isCancelled { return }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let d = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }
            let delta = choice["delta"] as? [String: Any] ?? [:]

            if let content = delta["content"] as? String, !content.isEmpty {
                let (vis, think) = splitter.feed(content)
                if !vis.isEmpty { emit(.textDelta(vis)) }
                if !think.isEmpty { emit(.thinkDelta(think)) }
            }
            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                emit(.thinkDelta(reasoning))
            }
            if let tcs = delta["tool_calls"] as? [[String: Any]] {
                for tc in tcs {
                    let idx = tc["index"] as? Int ?? 0
                    var info = calls[idx] ?? (id: "", name: "", args: "")
                    if let id = tc["id"] as? String, !id.isEmpty { info.id = id }
                    if let fn = tc["function"] as? [String: Any] {
                        if let name = fn["name"] as? String, !name.isEmpty {
                            info.name = name
                            if !emittedBegin.contains(idx) { emittedBegin.insert(idx); emit(.toolCallBegin(id: info.id, name: name)) }
                        }
                        if let argChunk = fn["arguments"] as? String, !argChunk.isEmpty {
                            info.args += argChunk; emit(.toolCallArg(id: info.id, chunk: argChunk))
                        }
                    }
                    calls[idx] = info
                }
            }
            if (choice["finish_reason"] as? String) != nil {
                for (_, info) in calls.sorted(by: { $0.key < $1.key }) where !info.id.isEmpty && !info.name.isEmpty {
                    let args = (try? JSONSerialization.jsonObject(with: Data((info.args.isEmpty ? "{}" : info.args).utf8))) as? [String: Any] ?? [:]
                    emit(.toolCallEnd(id: info.id, name: info.name, args: args))
                }
                calls.removeAll(); emittedBegin.removeAll()
            }
        }
    }

    /// LLMWireMessage → OpenAI 消息 JSON。
    private static func wireToJSON(_ m: LLMWireMessage) -> [String: Any] {
        var d: [String: Any] = ["role": m.role, "content": m.content ?? ""]
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
