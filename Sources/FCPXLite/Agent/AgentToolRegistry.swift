import Foundation

/// Agent 工具层:把剪辑操作形式化成 LLM 友好的工具(用 index/秒,不用内部 ClipID)。
/// 每个工具有 name/description/JSON-schema 参数;execute 调 store;timelineSummary 给 LLM 看状态。
/// 这是"对话驱动剪辑"的核心 seam —— 与 DebugControlServer 的 /cmd 同源,形式化成 Agent 可调用的工具。
@MainActor
final class AgentToolRegistry {
    let store: DocumentStore
    init(store: DocumentStore) { self.store = store }

    struct Tool {
        let name: String
        let description: String
        let parameters: [String: Any]   // JSON schema (type:object)
    }

    // MARK: - 工具定义

    func tools() -> [Tool] {
        [
            Tool(name: "query_timeline",
                 description: "获取当前时间线与素材库的完整状态摘要(片段、时长、层级、播放头)。做任何编辑前先调用。",
                 parameters: obj([:])),
            dispatchTool(name: "timeline_edit", domain: .timeline,
                         intro: "改时间线结构:增删/移动/裁剪/切割/拼接/间隙。"),
            dispatchTool(name: "clip_adjust", domain: .adjust,
                         intro: "改片段画面/音频参数:缩放/位置/裁剪/不透明度/音量。"),
            dispatchTool(name: "navigate", domain: .navigate,
                         intro: "导航/选择/工具/撤销重做/缩放/导入。"),
        ]
    }

    /// 从 catalog 的某 domain 生成一个 dispatch 工具:参数固定为 {type, params...},
    /// description 内嵌该域所有 action 名 + 形参表(自包含,LLM 无需多查)。
    private func dispatchTool(name: String, domain: ActionDomain, intro: String) -> Tool {
        let actions = AgentActionCatalog.actions(in: domain)
        var doc = intro + "\n用法:传 type=动作名,其余字段为该动作参数。可用动作:\n"
        for a in actions {
            let ps = a.params.map { p -> String in
                let req = p.required ? "" : "?"
                return "\(p.name)\(req)"
            }.joined(separator: ", ")
            doc += "  • \(a.type)(\(ps)) — \(a.doc)\n"
        }
        // 参数 schema:type 必填(枚举所有动作名),其余参数合并为开放属性。
        var props: [String: Any] = ["type": enm(actions.map { $0.type }, "要执行的动作名")]
        for a in actions {
            for p in a.params where props[p.name] == nil {
                switch p.kind {
                case .int: props[p.name] = int(p.doc)
                case .number: props[p.name] = num(p.doc)
                case .string: props[p.name] = str(p.doc)
                case .enumString(let vals): props[p.name] = enm(vals, p.doc)
                case .objectArray(let item): props[p.name] = arr(item, p.doc)
                }
            }
        }
        return Tool(name: name, description: doc, parameters: obj(props, required: ["type"]))
    }

    /// OpenAI function-calling 格式的工具数组。
    func toolsJSON() -> [[String: Any]] {
        tools().map { t in
            ["type": "function",
             "function": ["name": t.name, "description": t.description, "parameters": t.parameters]]
        }
    }

    // MARK: - 执行

    /// 执行一个工具,返回给 LLM 的结果文本(成功摘要或错误)。
    func execute(name: String, args: [String: Any]) -> String {
        let result = executeInner(name: name, args: args)
        NSLog("[AgentTool] \(name) args=\(args) → \(result)")   // DEBUG: 诊断 LLM 实际调用
        return result
    }

    private func executeInner(name: String, args: [String: Any]) -> String {
        if name == "query_timeline" { return timelineSummary() }
        // 三个 dispatch 工具:取 type 查 catalog,domain 须匹配工具。
        guard let type = args["type"] as? String else { return "错误:缺 type" }
        guard let action = AgentActionCatalog.find(type) else { return "错误:未知动作 type=\(type)" }
        let expectedTool: String
        switch action.domain {
        case .timeline: expectedTool = "timeline_edit"
        case .adjust: expectedTool = "clip_adjust"
        case .navigate: expectedTool = "navigate"
        }
        guard name == expectedTool else { return "错误:动作 \(type) 属于 \(expectedTool),不该用 \(name)" }
        return action.apply(store, args)
    }

    // MARK: - 状态摘要(给 LLM 看)

    func timelineSummary() -> String {
        var s = "格式 \(store.document.formatWidth)x\(store.document.formatHeight) @\(Int(store.document.frameRate))fps,播放头 \(fmt(store.ui.playhead.seconds))s\n"
        s += "素材库(\(store.document.assetLibrary.count)):\n"
        for (i, a) in store.document.assetLibrary.enumerated() {
            s += "  [\(i)] \(a.url.lastPathComponent) \(a.kind.rawValue) \(fmt(a.duration.seconds))s\(a.hasAudio ? " 有音频" : "")\n"
        }
        let placed = Layout.compute(store.document.sequence)
        s += "主时间线片段:\n"
        var ci = 0
        var acc = 0.0
        for el in store.document.sequence.spine {
            switch el {
            case .gap(_, let d): s += "  (间隙 \(fmt(d.seconds))s)\n"; acc += d.seconds
            case .clip(let c):
                let name = store.document.assetLibrary.first { $0.id == c.assetID }?.url.lastPathComponent ?? "?"
                s += "  [\(ci)] \(name) \(fmt(acc))→\(fmt(acc + c.duration.seconds))s lane0\n"
                ci += 1; acc += c.duration.seconds
            }
        }
        let conns = placed.filter { $0.isConnected }
        if !conns.isEmpty {
            s += "连接片段(叠加):\n"
            for p in conns {
                let name = clipName(p.clipID)
                s += "  \(name) lane\(p.lane) \(fmt(p.absStart.seconds))→\(fmt((p.absStart + p.duration).seconds))s\n"
            }
        }
        return s
    }

    // MARK: - 辅助

    private func clipName(_ id: ClipID) -> String {
        for el in store.document.sequence.spine {
            if case .clip(let c) = el {
                if c.id == id { return store.document.assetLibrary.first { $0.id == c.assetID }?.url.lastPathComponent ?? "?" }
                for ch in c.connected where ch.id == id { return store.document.assetLibrary.first { $0.id == ch.assetID }?.url.lastPathComponent ?? "?" }
            }
        }
        return "?"
    }
    private func fmt(_ x: Double) -> String { String(format: "%.2f", x) }

    // JSON schema 构件
    private func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        var p: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { p["required"] = required }
        return p
    }
    private func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
    private func num(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
    private func enm(_ vals: [String], _ d: String) -> [String: Any] { ["type": "string", "enum": vals, "description": d] }
    /// 对象数组 schema:items 为由 specs 构成的 object。供批量动作(如 build_subtitle_cut)用。
    private func arr(_ specs: [ParamSpec], _ d: String) -> [String: Any] {
        var itemProps: [String: Any] = [:]
        var req: [String] = []
        for p in specs {
            switch p.kind {
            case .int: itemProps[p.name] = int(p.doc)
            case .number: itemProps[p.name] = num(p.doc)
            case .string: itemProps[p.name] = str(p.doc)
            case .enumString(let vals): itemProps[p.name] = enm(vals, p.doc)
            case .objectArray(let inner): itemProps[p.name] = arr(inner, p.doc)
            }
            if p.required { req.append(p.name) }
        }
        var items: [String: Any] = ["type": "object", "properties": itemProps]
        if !req.isEmpty { items["required"] = req }
        return ["type": "array", "description": d, "items": items]
    }
}
