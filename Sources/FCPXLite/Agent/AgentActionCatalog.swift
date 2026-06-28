import Foundation

/// LLM 可见的动作领域。
enum ActionDomain: String { case timeline, adjust, navigate }

/// 形参规格(供生成 JSON schema)。
enum ParamKind { case int, number, string; case enumString([String]) }
struct ParamSpec { let name: String; let kind: ParamKind; let required: Bool; let doc: String }

/// 一个 LLM 可发的扁平动作:type + 注释 + 形参 + 翻译执行闭包(index/秒 → EditorAction → dispatch)。
struct AgentAction {
    let type: String
    let domain: ActionDomain
    let doc: String
    let params: [ParamSpec]
    let apply: @MainActor (DocumentStore, [String: Any]) -> String
}

/// 单一事实来源:全部动作。工具 schema 与执行都从这里来,杜绝清单/代码漂移。
enum AgentActionCatalog {
    static func actions(in domain: ActionDomain) -> [AgentAction] { all.filter { $0.domain == domain } }
    static func find(_ type: String) -> AgentAction? { all.first { $0.type == type } }

    // 翻译辅助(index/秒 → 内部表示)。各 apply 闭包共用。
    static func clipID(_ store: DocumentStore, _ clipIndex: Int) -> ClipID? {
        var n = 0
        for el in store.document.sequence.spine { if case .clip(let c) = el { if n == clipIndex { return c.id }; n += 1 } }
        return nil
    }
    static func spineElementIndex(_ store: DocumentStore, clipIndex: Int) -> Int? {
        var n = 0
        for (i, el) in store.document.sequence.spine.enumerated() { if case .clip = el { if n == clipIndex { return i }; n += 1 } }
        return nil
    }
    static func clipFromAsset(_ store: DocumentStore, _ i: Int) -> Clip? {
        guard store.document.assetLibrary.indices.contains(i) else { return nil }
        let a = store.document.assetLibrary[i]
        return Clip(assetID: a.id, sourceIn: .zero, duration: a.duration)
    }
    static func intArg(_ a: [String: Any], _ k: String) -> Int? { (a[k] as? Int) ?? (a[k] as? Double).map(Int.init) ?? (a[k] as? NSNumber)?.intValue }
    static func numArg(_ a: [String: Any], _ k: String) -> Double? { (a[k] as? Double) ?? (a[k] as? Int).map(Double.init) ?? (a[k] as? NSNumber)?.doubleValue }
    static func strArg(_ a: [String: Any], _ k: String) -> String? { a[k] as? String }

    static let all: [AgentAction] = timeline + adjust + navigate

    // 各 domain 在后续 Task 填充;先放占位让骨架可编译+测试通过。
    static let timeline: [AgentAction] = [
        AgentAction(type: "insert", domain: .timeline, doc: "占位", params: []) { _, _ in "未实现" }
    ]
    static let adjust: [AgentAction] = [
        AgentAction(type: "volume", domain: .adjust, doc: "占位", params: []) { _, _ in "未实现" }
    ]
    static let navigate: [AgentAction] = [
        AgentAction(type: "playhead", domain: .navigate, doc: "占位", params: []) { _, _ in "未实现" }
    ]
}
