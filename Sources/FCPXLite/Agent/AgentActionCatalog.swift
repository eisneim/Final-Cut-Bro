import Foundation
import CoreGraphics

/// LLM 可见的动作领域。
enum ActionDomain: String { case timeline, adjust, navigate, system, shell }

/// 形参规格(供生成 JSON schema)。objectArray 用于批量动作:一个由若干同构对象组成的数组。
indirect enum ParamKind { case int, number, string; case enumString([String]); case objectArray([ParamSpec]) }
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
    /// 第 n 个标题片段的 id(主轴+连接,文档顺序)。供编辑已有标题用。
    static func titleClipID(_ store: DocumentStore, _ n: Int) -> ClipID? {
        var titles: [ClipID] = []
        for el in store.document.sequence.spine {
            if case .clip(let c) = el {
                if c.isTitle { titles.append(c.id) }
                for ch in c.connected where ch.isTitle { titles.append(ch.id) }
            }
        }
        return titles.indices.contains(n) ? titles[n] : nil
    }
    /// 按 id 找 clip(主轴或连接子项)。
    static func findClip(_ store: DocumentStore, _ id: ClipID) -> Clip? {
        store.document.sequence.clip(id: id)
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
    /// 取一个对象数组形参(批量动作用)。容忍 [[String:Any]] 或 [Any](内含字典)。
    static func arrArg(_ a: [String: Any], _ k: String) -> [[String: Any]] {
        if let arr = a[k] as? [[String: Any]] { return arr }
        if let arr = a[k] as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
        return []
    }
    static func boolArg(_ a: [String: Any], _ k: String) -> Bool? {
        if let b = a[k] as? Bool { return b }
        if let n = a[k] as? NSNumber { return n.boolValue }
        if let s = a[k] as? String { return (s as NSString).boolValue }
        return nil
    }

    static let all: [AgentAction] = timeline + adjust + navigate + system + shell

    // 各 domain 在后续 Task 填充;先放占位让骨架可编译+测试通过。
    @MainActor static func mutateEffects(_ store: DocumentStore, clipIndex: Int, _ f: (inout [Effect]) -> Void) -> Bool {
        guard let id = clipID(store, clipIndex), let ei = spineElementIndex(store, clipIndex: clipIndex),
              case .clip(let c) = store.document.sequence.spine[ei] else { return false }
        var fx = c.effects; f(&fx); store.dispatch(.setEffects(id, fx)); return true
    }

    static func mutateAdjust(_ store: DocumentStore, clipIndex: Int, _ f: (inout Adjustments) -> Void) -> Bool {
        guard let id = clipID(store, clipIndex), let ei = spineElementIndex(store, clipIndex: clipIndex),
              case .clip(let c) = store.document.sequence.spine[ei] else { return false }
        var adj = c.adjust; f(&adj); store.dispatch(.setAdjust(id, adj)); return true
    }

    /// 改某 clip 的变换关键帧(走命令层,可撤销)。返回 false=clipIndex 无效。
    static func mutateTransformKeyframes(_ store: DocumentStore, clipIndex: Int, _ f: (inout [TransformKeyframe]) -> Void) -> Bool {
        guard let id = clipID(store, clipIndex), let ei = spineElementIndex(store, clipIndex: clipIndex),
              case .clip(let c) = store.document.sequence.spine[ei] else { return false }
        var kfs = c.transformKeyframes; f(&kfs); store.dispatch(.setTransformKeyframes(id, kfs)); return true
    }


}
