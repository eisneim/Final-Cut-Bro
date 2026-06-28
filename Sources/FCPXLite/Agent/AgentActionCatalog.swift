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
    static func boolArg(_ a: [String: Any], _ k: String) -> Bool? {
        if let b = a[k] as? Bool { return b }
        if let n = a[k] as? NSNumber { return n.boolValue }
        if let s = a[k] as? String { return (s as NSString).boolValue }
        return nil
    }

    static let all: [AgentAction] = timeline + adjust + navigate

    // 各 domain 在后续 Task 填充;先放占位让骨架可编译+测试通过。
    static let timeline: [AgentAction] = [
        AgentAction(type: "insert", domain: .timeline,
                    doc: "把素材库第 assetIndex 个素材插入主轴 atSeconds 处(省略则末尾)。后续片段右移。",
                    params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引,0基"),
                             ParamSpec(name: "atSeconds", kind: .number, required: false, doc: "插入时间(秒),省略=末尾")]) { store, a in
            guard let clip = clipFromAsset(store, intArg(a, "assetIndex") ?? -1) else { return "错误:assetIndex 无效" }
            let count = store.document.sequence.spine.count
            if let at = numArg(a, "atSeconds") {
                var idx = store.document.sequence.spine.count, acc = 0.0
                for (i, el) in store.document.sequence.spine.enumerated() {
                    if acc + el.duration.seconds > at { idx = i; break }
                    acc += el.duration.seconds
                }
                store.dispatch(.insertClip(clip, at: idx))
            } else {
                store.dispatch(.insertClip(clip, at: count))
            }
            return "已插入素材 \(intArg(a, "assetIndex")!)"
        },
        AgentAction(type: "append", domain: .timeline,
                    doc: "把素材库第 assetIndex 个素材追加到主轴末尾。",
                    params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引,0基")]) { store, a in
            guard let clip = clipFromAsset(store, intArg(a, "assetIndex") ?? -1) else { return "错误:assetIndex 无效" }
            store.dispatch(.insertClip(clip, at: store.document.sequence.spine.count))
            return "已追加素材 \(intArg(a, "assetIndex")!)"
        },
        AgentAction(type: "connect", domain: .timeline,
                    doc: "把素材库第 assetIndex 个素材作为连接片段叠加到 atSeconds、第 lane 层(>0在上,<0在下)。用于画中画/多轨。",
                    params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引"),
                             ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "时间位置(秒)"),
                             ParamSpec(name: "lane", kind: .int, required: false, doc: "层级,默认1")]) { store, a in
            guard let clip = clipFromAsset(store, intArg(a, "assetIndex") ?? -1) else { return "错误:assetIndex 无效" }
            let at = numArg(a, "atSeconds") ?? 0
            // host = 覆盖 at 的主轴片段;offset = at - host起点
            var hostIdx = 0, acc = 0.0, hostStart = 0.0
            var found = false
            for (i, el) in store.document.sequence.spine.enumerated() {
                if case .clip = el { if at >= acc && at < acc + el.duration.seconds { hostIdx = i; hostStart = acc; found = true; break } }
                acc += el.duration.seconds
            }
            guard found else { return "错误:atSeconds 处主轴无片段可挂载" }
            let lane = intArg(a, "lane") ?? 1
            store.dispatch(.connect(clip, host: hostIdx, lane: lane == 0 ? 1 : lane, offset: .seconds(at - hostStart)))
            return "已连接素材 \(intArg(a, "assetIndex")!) 到 lane\(lane)"
        },
        AgentAction(type: "delete", domain: .timeline,
                    doc: "删除主轴第 clipIndex 个片段。ripple=true 磁性合拢,false 留 gap。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "主轴片段索引,0基"),
                             ParamSpec(name: "ripple", kind: .string, required: false, doc: "true/false,默认true")]) { store, a in
            guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            let ripple = boolArg(a, "ripple") ?? true
            store.dispatch(ripple ? .rippleDelete(at: ei) : .liftDelete(at: ei))
            return "已删除片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "move", domain: .timeline,
                    doc: "把主轴第 fromClipIndex 个片段移到第 toClipIndex 个位置(调整顺序)。",
                    params: [ParamSpec(name: "fromClipIndex", kind: .int, required: true, doc: "源片段索引"),
                             ParamSpec(name: "toClipIndex", kind: .int, required: true, doc: "目标位置索引")]) { store, a in
            guard let from = spineElementIndex(store, clipIndex: intArg(a, "fromClipIndex") ?? -1),
                  let to = spineElementIndex(store, clipIndex: intArg(a, "toClipIndex") ?? -1) else { return "错误:索引无效" }
            store.dispatch(.moveClip(from: from, to: to))
            return "已移动片段"
        },
        AgentAction(type: "blade", domain: .timeline,
                    doc: "在 atSeconds 处把主轴第 clipIndex 个片段切成两段。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "切割时间(秒)")]) { store, a in
            guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1),
                  case .clip = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
            // localTime = at - 片段起点
            var acc = 0.0
            for (i, el) in store.document.sequence.spine.enumerated() { if i == ei { break }; acc += el.duration.seconds }
            let at = numArg(a, "atSeconds") ?? 0
            store.dispatch(.blade(at: ei, localTime: .seconds(at - acc)))
            return "已在 \(at)s 切割片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "trim", domain: .timeline,
                    doc: "修剪主轴第 clipIndex 个片段。edge=head 改入点(seconds=入点偏移),edge=tail 改时长(seconds=新时长)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "edge", kind: .enumString(["head", "tail"]), required: true, doc: "修剪哪端"),
                             ParamSpec(name: "seconds", kind: .number, required: true, doc: "head:入点偏移; tail:新时长")]) { store, a in
            guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1),
                  case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
            let sec = numArg(a, "seconds") ?? 0
            if strArg(a, "edge") == "head" { store.dispatch(.trimLeft(at: ei, deltaIn: .seconds(sec))) }
            else {
                let assetDur = store.document.assetLibrary.first { $0.id == c.assetID }?.duration ?? c.duration
                store.dispatch(.trimRight(at: ei, newDuration: .seconds(sec), assetDuration: assetDur))
            }
            return "已修剪片段 \(intArg(a, "clipIndex")!) \(strArg(a, "edge") ?? "")"
        },
        AgentAction(type: "set_gap", domain: .timeline,
                    doc: "把主轴第 spineIndex 个元素(须为间隙)的时长设为 seconds。",
                    params: [ParamSpec(name: "spineIndex", kind: .int, required: true, doc: "spine 元素索引(含间隙)"),
                             ParamSpec(name: "seconds", kind: .number, required: true, doc: "新间隙时长(秒)")]) { store, a in
            let i = intArg(a, "spineIndex") ?? -1
            guard store.document.sequence.spine.indices.contains(i) else { return "错误:spineIndex 无效" }
            store.dispatch(.setGapDuration(at: i, duration: .seconds(numArg(a, "seconds") ?? 1)))
            return "已设置间隙时长"
        },
        AgentAction(type: "position_move", domain: .timeline,
                    doc: "位置工具:把主轴第 clipIndex 个片段移到 atSeconds,源处留下占位间隙(不磁性合拢)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "目标时间(秒)")]) { store, a in
            guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            store.dispatch(.positionMove(id, time: .seconds(numArg(a, "atSeconds") ?? 0)))
            return "已位置移动片段 \(intArg(a, "clipIndex")!)"
        },
    ]

    static func mutateAdjust(_ store: DocumentStore, clipIndex: Int, _ f: (inout Adjustments) -> Void) -> Bool {
        guard let id = clipID(store, clipIndex), let ei = spineElementIndex(store, clipIndex: clipIndex),
              case .clip(let c) = store.document.sequence.spine[ei] else { return false }
        var adj = c.adjust; f(&adj); store.dispatch(.setAdjust(id, adj)); return true
    }

    static let adjust: [AgentAction] = [
        AgentAction(type: "scale", domain: .adjust, doc: "缩放主轴第 clipIndex 个片段画面,value 0.1–4(画中画/放大)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "value", kind: .number, required: true, doc: "缩放比例 0.1–4")]) { store, a in
            let v = numArg(a, "value") ?? 1
            return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.transform.scale = CGSize(width: v, height: v) }
                ? "已缩放片段到 \(v)x" : "错误:clipIndex 无效"
        },
        AgentAction(type: "position", domain: .adjust, doc: "平移主轴第 clipIndex 个片段画面 x/y 像素。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "x", kind: .number, required: true, doc: "水平位移px"),
                             ParamSpec(name: "y", kind: .number, required: true, doc: "垂直位移px")]) { store, a in
            let x = numArg(a, "x") ?? 0, y = numArg(a, "y") ?? 0
            return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.transform.position = CGPoint(x: x, y: y) }
                ? "已平移片段" : "错误:clipIndex 无效"
        },
        AgentAction(type: "crop", domain: .adjust, doc: "裁剪主轴第 clipIndex 个片段。left/right/top/bottom 为各边裁剪比例 0–1(如 left=0.15 裁左15%)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "left", kind: .number, required: false, doc: "左裁比例0–1"),
                             ParamSpec(name: "right", kind: .number, required: false, doc: "右裁比例0–1"),
                             ParamSpec(name: "top", kind: .number, required: false, doc: "上裁比例0–1"),
                             ParamSpec(name: "bottom", kind: .number, required: false, doc: "下裁比例0–1")]) { store, a in
            let ci = intArg(a, "clipIndex") ?? -1
            guard let ei = spineElementIndex(store, clipIndex: ci), case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
            let nat = store.document.assetLibrary.first { $0.id == c.assetID }?.naturalSize ?? CGSize(width: 1920, height: 1080)
            return mutateAdjust(store, clipIndex: ci) {
                if let l = numArg(a, "left")   { $0.crop.left   = l * Double(nat.width) }
                if let r = numArg(a, "right")  { $0.crop.right  = r * Double(nat.width) }
                if let t = numArg(a, "top")    { $0.crop.top    = t * Double(nat.height) }
                if let b = numArg(a, "bottom") { $0.crop.bottom = b * Double(nat.height) }
            } ? "已裁剪片段 \(ci)" : "错误:clipIndex 无效"
        },
        AgentAction(type: "opacity", domain: .adjust, doc: "设主轴第 clipIndex 个片段不透明度 value 0–1。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "value", kind: .number, required: true, doc: "不透明度0–1")]) { store, a in
            let v = numArg(a, "value") ?? 1
            return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.opacity = v }
                ? "已设不透明度 \(v)" : "错误:clipIndex 无效"
        },
        AgentAction(type: "volume", domain: .adjust, doc: "设主轴第 clipIndex 个片段音量 value 0–2(1=原始,0=静音;压低视频原声/调音乐用)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "value", kind: .number, required: true, doc: "音量0–2")]) { store, a in
            let v = numArg(a, "value") ?? 1
            return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.volume = v }
                ? "已设音量 \(v)" : "错误:clipIndex 无效"
        },
    ]
    static let navigate: [AgentAction] = [
        AgentAction(type: "playhead", domain: .navigate, doc: "占位", params: []) { _, _ in "未实现" }
    ]
}
