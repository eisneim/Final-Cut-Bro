import Foundation
import CoreGraphics

/// LLM 可见的动作领域。
enum ActionDomain: String { case timeline, adjust, navigate, system }

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
        for el in store.document.sequence.spine {
            if case .clip(let c) = el {
                if c.id == id { return c }
                for ch in c.connected where ch.id == id { return ch }
            }
        }
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

    static let all: [AgentAction] = timeline + adjust + navigate + system

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
            let effectiveLane = lane == 0 ? 1 : lane
            store.dispatch(.connect(clip, host: hostIdx, lane: effectiveLane, offset: .seconds(at - hostStart)))
            return "已连接素材 \(intArg(a, "assetIndex")!) 到 lane\(effectiveLane)"
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
                  case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
            // localTime = at - 片段起点
            var acc = 0.0
            for (i, el) in store.document.sequence.spine.enumerated() { if i == ei { break }; acc += el.duration.seconds }
            let at = numArg(a, "atSeconds") ?? 0
            let local = at - acc
            // 越界(切点不在该片段内)→ 明确报错,不能静默"成功"(否则会把 agent 带偏)。
            guard local > 0.001, local < c.duration.seconds - 0.001 else {
                return "错误:切点 \(at)s 不在片段范围内(该片段时间线 \(String(format: "%.2f", acc))–\(String(format: "%.2f", acc + c.duration.seconds))s)"
            }
            let before = store.document.sequence.spine.count
            store.dispatch(.blade(at: ei, localTime: .seconds(local)))
            return store.document.sequence.spine.count > before ? "已在 \(at)s 切割片段 \(intArg(a, "clipIndex")!)" : "错误:切割未生效"
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
                    doc: "调整已存在的【间隙(gap)】时长 —— 不是切割也不是删除。spineIndex 必须指向一个间隙元素。要在片段间制造间隙请用 delete(ripple=false) 或 position_move。",
                    params: [ParamSpec(name: "spineIndex", kind: .int, required: true, doc: "spine 元素索引(含间隙)"),
                             ParamSpec(name: "seconds", kind: .number, required: true, doc: "新间隙时长(秒)")]) { store, a in
            let i = intArg(a, "spineIndex") ?? -1
            guard store.document.sequence.spine.indices.contains(i) else { return "错误:spineIndex 无效" }
            store.dispatch(.setGapDuration(at: i, duration: .seconds(numArg(a, "seconds") ?? 1)))
            return "已设置间隙时长"
        },
        AgentAction(type: "position_move", domain: .timeline,
                    doc: "【位置工具】把主轴第 clipIndex 个片段整体移到 atSeconds,源位置留下占位间隙(不像 blade 那样切开,也不像 move 那样调顺序)。用于在保持其它片段位置不变的前提下挪动一个片段。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "目标时间(秒)")]) { store, a in
            guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            store.dispatch(.positionMove(id, time: .seconds(numArg(a, "atSeconds") ?? 0)))
            return "已位置移动片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "duplicate_clip", domain: .timeline,
                    doc: "复制主轴第 clipIndex 个片段(连同参数/特效/关键帧,换新 id)并粘贴到 atSeconds 处(省略=末尾)。等价 ⌘C/⌘V。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "源片段索引,0基"),
                             ParamSpec(name: "atSeconds", kind: .number, required: false, doc: "粘贴时间(秒),落到最近编辑点;省略=末尾")]) { store, a in
            guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1),
                  case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
            let dup = c.duplicatedWithNewIDs()
            if let at = numArg(a, "atSeconds") {
                var idx = store.document.sequence.spine.count, acc = 0.0
                for (i, el) in store.document.sequence.spine.enumerated() {
                    if acc + el.duration.seconds > at + 0.0005 { idx = i; break }
                    acc += el.duration.seconds
                }
                store.dispatch(.insertClip(dup, at: idx))
            } else {
                store.dispatch(.insertClip(dup, at: store.document.sequence.spine.count))
            }
            store.dispatch(.selectClip(dup.id))
            return "已复制片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "slip", domain: .timeline,
                    doc: "滑移(slip):改主轴第 clipIndex 个片段看到素材的哪一段(入出点 +deltaSeconds),【片段在时间线的位置和时长都不变】。正=往素材后面取,负=往前。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "deltaSeconds", kind: .number, required: true, doc: "入点偏移(秒),正/负")]) { store, a in
            guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1),
                  case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
            let assetDur = store.document.assetLibrary.first { $0.id == c.assetID }?.duration ?? c.duration
            store.dispatch(.slip(at: ei, delta: .seconds(numArg(a, "deltaSeconds") ?? 0), assetDuration: assetDur))
            return "已滑移片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "slide", domain: .timeline,
                    doc: "滑动(slide):把主轴第 clipIndex 个片段沿时间线移 deltaSeconds,【自身入出/时长不变】,由前后相邻片段伸缩补偿,总时长不变。要求前后都有片段(非间隙)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "deltaSeconds", kind: .number, required: true, doc: "移动量(秒),正右/负左")]) { store, a in
            guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            let spine = store.document.sequence.spine
            guard spine.indices.contains(ei - 1), spine.indices.contains(ei + 1),
                  case .clip(let prev) = spine[ei - 1], case .clip(let next) = spine[ei + 1] else {
                return "错误:slide 需要前后都是片段(非间隙/非边缘)"
            }
            let prevDur = store.document.assetLibrary.first { $0.id == prev.assetID }?.duration ?? prev.duration
            let nextDur = store.document.assetLibrary.first { $0.id == next.assetID }?.duration ?? next.duration
            store.dispatch(.slide(at: ei, delta: .seconds(numArg(a, "deltaSeconds") ?? 0),
                                  prevAssetDuration: prevDur, nextAssetDuration: nextDur))
            return "已滑动片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "add_transition", domain: .timeline,
                    doc: "在主轴第 clipIndex 个片段【头部】与前一片段之间加交叉叠化转场(crossfade/dissolve),时长 seconds 秒(0=移除)。要求 clipIndex≥1。本片段头部与前片段尾部重叠该时长。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引(≥1)"),
                             ParamSpec(name: "seconds", kind: .number, required: false, doc: "转场时长(秒),默认1,0=移除")]) { store, a in
            guard let ei = spineElementIndex(store, clipIndex: intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            let spine = store.document.sequence.spine
            guard ei >= 1, spine.indices.contains(ei - 1), case .clip = spine[ei - 1] else {
                return "错误:转场需要前面有一个相邻片段(clipIndex≥1)"
            }
            let secs = numArg(a, "seconds") ?? 1
            store.dispatch(.setCrossfade(at: ei, duration: .seconds(secs)))
            return secs > 0 ? "已加 \(secs)s 叠化转场" : "已移除转场"
        },
        AgentAction(type: "add_title", domain: .timeline,
                    doc: "在 atSeconds(省略=播放头)加一个文字标题/字幕(叠在视频上层)。text 必填;duration 时长秒(默认5);fontSize 字号(默认96,字幕常用56);colorHex 颜色#RRGGBB;y 垂直位置(正=下移,屏幕下方字幕用~380)。",
                    params: [ParamSpec(name: "text", kind: .string, required: true, doc: "标题/字幕文字"),
                             ParamSpec(name: "atSeconds", kind: .number, required: false, doc: "起始时间(秒),省略=播放头"),
                             ParamSpec(name: "duration", kind: .number, required: false, doc: "时长(秒),默认5"),
                             ParamSpec(name: "fontSize", kind: .number, required: false, doc: "字号,默认96"),
                             ParamSpec(name: "colorHex", kind: .string, required: false, doc: "颜色 #RRGGBB,默认白"),
                             ParamSpec(name: "y", kind: .number, required: false, doc: "垂直位置px,正=下移")]) { store, a in
            if let at = numArg(a, "atSeconds") { store.dispatch(.setPlayhead(.seconds(at))) }
            let text = strArg(a, "text") ?? "标题"
            _ = store.addTitleAtPlayhead(text: text, duration: .seconds(numArg(a, "duration") ?? 5))
            store.updateSelectedTitle { spec in
                if let fs = numArg(a, "fontSize") { spec.fontSize = fs }
                if let c = strArg(a, "colorHex") { spec.colorHex = c }
                if let y = numArg(a, "y") { spec.position.y = y }
            }
            return "已加标题「\(text)」"
        },
        AgentAction(type: "append_clip", domain: .timeline,
                    doc: "把素材库第 assetIndex 个素材的【源区间 fromSeconds–toSeconds 秒】作为一个片段追加到主时间线末尾,并把播放头移到该片段起点。这是按 ASR/字幕时间戳【批量提取保留段拼成成片】的核心动作:先规划保留哪些段,再对每段调一次本动作;之后可紧跟 add_title 给该段加字幕(atSeconds 省略=刚追加段的起点)。",
                    params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引,0基"),
                             ParamSpec(name: "fromSeconds", kind: .number, required: true, doc: "源区间起点(秒)"),
                             ParamSpec(name: "toSeconds", kind: .number, required: true, doc: "源区间终点(秒)")]) { store, a in
            let i = intArg(a, "assetIndex") ?? -1
            guard store.document.assetLibrary.indices.contains(i) else { return "错误:assetIndex 无效" }
            let from = numArg(a, "fromSeconds") ?? 0, to = numArg(a, "toSeconds") ?? 0
            guard to > from else { return "错误:toSeconds 必须大于 fromSeconds" }
            let at = store.appendSourceRange(assetID: store.document.assetLibrary[i].id, from: from, to: to)
            return "已追加源[\(from)–\(to)]s 到时间线 \(String(format: "%.2f", at))s 起(播放头已移到此)"
        },
        AgentAction(type: "blade_at", domain: .timeline,
                    doc: "在 atSeconds 处直接切割(自动找到该时间点所在的片段并切)。用于【每隔 N 秒切一刀】等批量切割场景,比逐个调 blade(需指定 clipIndex)更高效。",
                    params: [ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "切割时间(秒,绝对时间线)")]) { store, a in
            let at = numArg(a, "atSeconds") ?? 0
            // 找包含 at 的主轴片段
            var acc = 0.0
            for (i, el) in store.document.sequence.spine.enumerated() {
                if case .clip(let c) = el {
                    let local = at - acc
                    if local > 0.001, local < c.duration.seconds - 0.001 {
                        store.dispatch(.setPlayhead(.seconds(at)))
                        store.dispatch(.blade(at: i, localTime: .seconds(local)))
                        return "已在 \(at)s 切割"
                    }
                }
                acc += el.duration.seconds
            }
            return "错误:\(at)s 处无片段可切"
        },
        AgentAction(type: "batch_blade", domain: .timeline,
                    doc: "每隔 intervalSeconds 秒切一刀(从头到尾)。一次调用完成全部切割,适合「每 2 秒剪一刀」等批量场景。",
                    params: [ParamSpec(name: "intervalSeconds", kind: .number, required: true, doc: "切割间隔(秒),如 2")]) { store, a in
            let interval = numArg(a, "intervalSeconds") ?? 2
            guard interval > 0.1 else { return "错误:间隔太小" }
            store.transaction {
                var total = 0.0
                for el in store.document.sequence.spine { total += el.duration.seconds }
                var t = interval
                while t < total - 0.01 {
                    var acc = 0.0
                    for (i, el) in store.document.sequence.spine.enumerated() {
                        if case .clip(let c) = el {
                            let local = t - acc
                            if local > 0.001, local < c.duration.seconds - 0.001 {
                                store.dispatch(.blade(at: i, localTime: .seconds(local)))
                                break
                            }
                        }
                        acc += el.duration.seconds
                    }
                    t += interval
                }
            }
            var cnt = 0
            for el in store.document.sequence.spine { if case .clip = el { cnt += 1 } }
            return "已每隔 \(interval)s 切割,共 \(cnt) 段"
        },
        AgentAction(type: "build_subtitle_cut", domain: .timeline,
                    doc: "【字幕剪辑一键成片 —— 处理 ASR/字幕剪辑请【只用这一个】动作,不要用几十次 append_clip/add_title】。你先在脑子里根据字幕【规划】要保留哪些句子(丢掉口误/重拍/思考废话/和别的句子重复的),然后把保留的句子【一次性】作为 segments 数组全部传进来。本动作会按顺序:逐段从源视频提取该时间区间拼到时间线 + 给该段加屏幕下方字幕,(若给了 exportPath)最后直接导出成片。一次调用完成全部工作。\n  segments: 保留段数组,每项 {from:源起始秒, to:源结束秒, text:该段字幕文字};按成片先后顺序排列。\n  assetIndex: 源视频在素材库的索引(默认0)。fontSize 字号(默认56)。y 字幕垂直位置(默认380=屏幕下方)。colorHex 颜色(默认#FFFFFF)。exportPath 给了就剪完导出到该绝对路径。",
                    params: [ParamSpec(name: "segments", kind: .objectArray([
                                ParamSpec(name: "from", kind: .number, required: true, doc: "源起始秒"),
                                ParamSpec(name: "to", kind: .number, required: true, doc: "源结束秒"),
                                ParamSpec(name: "text", kind: .string, required: true, doc: "该段字幕文字")]),
                                required: true, doc: "保留段数组(按成片顺序)"),
                             ParamSpec(name: "assetIndex", kind: .int, required: false, doc: "源视频索引,默认0"),
                             ParamSpec(name: "fontSize", kind: .number, required: false, doc: "字号,默认56"),
                             ParamSpec(name: "y", kind: .number, required: false, doc: "字幕垂直位置,默认380"),
                             ParamSpec(name: "colorHex", kind: .string, required: false, doc: "颜色#RRGGBB,默认白"),
                             ParamSpec(name: "exportPath", kind: .string, required: false, doc: "导出成片的绝对路径,省略=不导出")]) { store, a in
            let segs = arrArg(a, "segments")
            guard !segs.isEmpty else { return "错误:segments 为空,需先规划保留段再传入" }
            let i = intArg(a, "assetIndex") ?? 0
            guard store.document.assetLibrary.indices.contains(i) else { return "错误:assetIndex \(i) 无效" }
            let assetID = store.document.assetLibrary[i].id
            let fs = numArg(a, "fontSize") ?? 56
            let yy = numArg(a, "y") ?? 380
            let color = strArg(a, "colorHex") ?? "#FFFFFF"
            var built = 0
            var bad: [Int] = []
            store.transaction {
                for (k, seg) in segs.enumerated() {
                    guard let from = numArg(seg, "from"), let to = numArg(seg, "to"), to > from else { bad.append(k); continue }
                    _ = store.appendSourceRange(assetID: assetID, from: from, to: to)   // 拼接并把播放头移到该段起点
                    let text = strArg(seg, "text") ?? ""
                    if !text.isEmpty {
                        _ = store.addTitleAtPlayhead(text: text, duration: .seconds(to - from))
                        store.updateSelectedTitle { spec in spec.fontSize = fs; spec.colorHex = color; spec.position.y = yy }
                    }
                    built += 1
                }
            }
            var total = 0.0
            for el in store.document.sequence.spine { total += el.duration.seconds }
            var msg = "已一键构建 \(built) 段(提取+字幕),成片时长 \(String(format: "%.2f", total))s"
            if !bad.isEmpty { msg += ";跳过无效段 \(bad)" }
            if let ep = strArg(a, "exportPath"), !ep.isEmpty {
                store.exportMovie(to: URL(fileURLWithPath: ep), settings: ExportSettings())
                msg += ";已开始导出成片到 \(ep)(渲染中,稍候完成)"
            }
            return msg
        },
        AgentAction(type: "overwrite", domain: .timeline,
                    doc: "覆盖(FCP D):用素材库第 assetIndex 个素材覆盖 atSeconds(省略=播放头)处的区间,裁掉/分割被覆盖内容,总时长不变。",
                    params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引"),
                             ParamSpec(name: "atSeconds", kind: .number, required: false, doc: "覆盖起点(秒),省略=播放头")]) { store, a in
            guard let clip = clipFromAsset(store, intArg(a, "assetIndex") ?? -1) else { return "错误:assetIndex 无效" }
            let at = numArg(a, "atSeconds").map { Time.seconds($0) } ?? store.ui.playhead
            store.dispatch(.overwrite(clip, atTime: at))
            return "已覆盖 @\(at.seconds)s"
        },
        AgentAction(type: "move_to_lane", domain: .timeline,
                    doc: "把主轴第 clipIndex 个片段移到第 lane 层(0=主轴,>0=上层叠加,<0=下层),起点 atSeconds。用于把片段挪到画中画轨道。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "lane", kind: .int, required: true, doc: "目标层:0主轴,>0上,<0下"),
                             ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "起点(秒)")]) { store, a in
            guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            store.dispatch(.relocateClip(id, lane: intArg(a, "lane") ?? 1, time: .seconds(numArg(a, "atSeconds") ?? 0)))
            return "已移到 lane\(intArg(a, "lane") ?? 1)"
        },
        AgentAction(type: "remove_gap", domain: .timeline,
                    doc: "删除主轴上第 spineIndex 个【间隙(gap)】元素(后续片段合拢)。spineIndex 必须指向一个间隙。",
                    params: [ParamSpec(name: "spineIndex", kind: .int, required: true, doc: "spine 元素索引(须为间隙)")]) { store, a in
            let i = intArg(a, "spineIndex") ?? -1
            guard store.document.sequence.spine.indices.contains(i),
                  case .gap(let gid, _) = store.document.sequence.spine[i] else { return "错误:spineIndex 不是间隙" }
            store.dispatch(.removeGap(gid))
            return "已删间隙"
        },
    ]
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
        AgentAction(type: "add_effect", domain: .adjust, doc: "给主轴第 clipIndex 个片段加特效。kind: color(调色) / blur(模糊) / fade(音频淡入淡出)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "kind", kind: .enumString(["color","blur","fade"]), required: true, doc: "特效种类")]) { store, a in
            guard let k = strArg(a, "kind").flatMap({ EffectKind(rawValue: $0) }) else { return "错误:未知特效 kind" }
            return mutateEffects(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.append(Effect.make(k)) }
                ? "已加特效 \(k.rawValue)" : "错误:clipIndex 无效"
        },
        AgentAction(type: "remove_effect", domain: .adjust, doc: "删除主轴第 clipIndex 个片段的第 effectIndex 个特效。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "effectIndex", kind: .int, required: true, doc: "特效索引,0基")]) { store, a in
            let ei = intArg(a, "effectIndex") ?? -1
            var found = false
            let ok = mutateEffects(store, clipIndex: intArg(a, "clipIndex") ?? -1) { if $0.indices.contains(ei) { $0.remove(at: ei); found = true } }
            if !ok { return "错误:clipIndex 无效" }
            return found ? "已删特效 \(ei)" : "错误:effectIndex \(ei) 无效"
        },
        AgentAction(type: "set_effect_param", domain: .adjust, doc: "调主轴第 clipIndex 个片段第 effectIndex 个特效的参数 key=value。color: brightness/contrast/saturation; blur: radius; fade: inSeconds/outSeconds。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "effectIndex", kind: .int, required: true, doc: "特效索引"),
                             ParamSpec(name: "key", kind: .string, required: true, doc: "参数名"),
                             ParamSpec(name: "value", kind: .number, required: true, doc: "参数值")]) { store, a in
            let ei = intArg(a, "effectIndex") ?? -1
            guard let key = strArg(a, "key") else { return "错误:缺 key" }
            let v = numArg(a, "value") ?? 0
            var found = false
            let ok = mutateEffects(store, clipIndex: intArg(a, "clipIndex") ?? -1) { if $0.indices.contains(ei) { $0[ei].params[key] = v; found = true } }
            if !ok { return "错误:clipIndex 无效" }
            return found ? "已设特效参数 \(key)=\(v)" : "错误:effectIndex \(ei) 无效"
        },
        AgentAction(type: "toggle_enabled", domain: .adjust, doc: "停用/启用主轴第 clipIndex 个片段。enabled=false 停用(不参与预览/导出,时间线变暗)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "enabled", kind: .string, required: true, doc: "true/false")]) { store, a in
            guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            let on = boolArg(a, "enabled") ?? true
            store.dispatch(.setEnabled(id, on)); return on ? "已启用片段" : "已停用片段"
        },
        AgentAction(type: "add_transform_keyframe", domain: .adjust,
                    doc: "给主轴第 clipIndex 个片段在 atSeconds(相对片段起点的秒数)加一个变换关键帧,做位移/缩放/淡入淡出【动画】。多次用不同 atSeconds 调用即形成动画(如 0s scale=1 → 3s scale=2 是放大推进)。scale 默认1,x/y 位移px默认0,opacity 0–1默认1。同一时间再调用会覆盖。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "相对片段起点的时间(秒)"),
                             ParamSpec(name: "scale", kind: .number, required: false, doc: "缩放,默认1"),
                             ParamSpec(name: "x", kind: .number, required: false, doc: "水平位移px,默认0"),
                             ParamSpec(name: "y", kind: .number, required: false, doc: "垂直位移px,默认0"),
                             ParamSpec(name: "opacity", kind: .number, required: false, doc: "不透明度0–1,默认1")]) { store, a in
            let t = numArg(a, "atSeconds") ?? 0
            let sc = numArg(a, "scale") ?? 1
            let kf = TransformKeyframe(time: .seconds(t),
                                       position: CGPoint(x: numArg(a, "x") ?? 0, y: numArg(a, "y") ?? 0),
                                       scale: CGSize(width: sc, height: sc),
                                       opacity: numArg(a, "opacity") ?? 1)
            return mutateTransformKeyframes(store, clipIndex: intArg(a, "clipIndex") ?? -1) { kfs in
                kfs.removeAll { abs($0.time.seconds - t) < 0.001 }   // 同时间覆盖
                kfs.append(kf); kfs.sort { $0.time < $1.time }
            } ? "已加变换关键帧 @\(t)s" : "错误:clipIndex 无效"
        },
        AgentAction(type: "clear_transform_keyframes", domain: .adjust,
                    doc: "清除主轴第 clipIndex 个片段的全部变换关键帧(回到静态变换)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引")]) { store, a in
            return mutateTransformKeyframes(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.removeAll() }
                ? "已清除变换关键帧" : "错误:clipIndex 无效"
        },
        AgentAction(type: "add_volume_keyframe", domain: .adjust,
                    doc: "给主轴第 clipIndex 个片段在 atSeconds(相对片段起点)加音量关键帧做【音量包络】(淡入淡出/局部压低)。value 0–2(1=原始,0=静音)。多次不同 atSeconds 调用形成包络。同时间覆盖。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "相对片段起点(秒)"),
                             ParamSpec(name: "value", kind: .number, required: true, doc: "音量 0–2")]) { store, a in
            let ci = intArg(a, "clipIndex") ?? -1
            guard let id = clipID(store, ci), let ei = spineElementIndex(store, clipIndex: ci),
                  case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:clipIndex 无效" }
            let t = numArg(a, "atSeconds") ?? 0
            var kfs = c.volumeKeyframes.filter { abs($0.time.seconds - t) > 0.001 }
            kfs.append(VolumeKeyframe(time: .seconds(t), value: numArg(a, "value") ?? 1))
            kfs.sort { $0.time < $1.time }
            store.dispatch(.setVolumeKeyframes(id, kfs))
            return "已加音量关键帧 @\(t)s"
        },
        AgentAction(type: "rotate", domain: .adjust, doc: "旋转主轴第 clipIndex 个片段画面 degrees 度(-180~180,正=顺时针)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引"),
                             ParamSpec(name: "degrees", kind: .number, required: true, doc: "角度 -180~180")]) { store, a in
            let d = numArg(a, "degrees") ?? 0
            return mutateAdjust(store, clipIndex: intArg(a, "clipIndex") ?? -1) { $0.transform.rotation = d }
                ? "已旋转到 \(d)°" : "错误:clipIndex 无效"
        },
        AgentAction(type: "set_title", domain: .adjust,
                    doc: "编辑【已存在】的第 titleIndex 个标题(0基,主轴+连接按文档顺序)。可改 text/fontSize/colorHex(#RRGGBB)/bold(true/false)/align(0左1中2右)/x/y(屏幕内位置px);还可改【时间线上的时间】:startSeconds=字幕出现的时间线起点秒,durationSeconds=字幕停留时长秒。只传想改的字段。",
                    params: [ParamSpec(name: "titleIndex", kind: .int, required: true, doc: "标题索引,0基"),
                             ParamSpec(name: "text", kind: .string, required: false, doc: "新文字"),
                             ParamSpec(name: "fontSize", kind: .number, required: false, doc: "字号"),
                             ParamSpec(name: "colorHex", kind: .string, required: false, doc: "颜色 #RRGGBB"),
                             ParamSpec(name: "bold", kind: .string, required: false, doc: "true/false"),
                             ParamSpec(name: "align", kind: .int, required: false, doc: "0左1中2右"),
                             ParamSpec(name: "x", kind: .number, required: false, doc: "水平位置px"),
                             ParamSpec(name: "y", kind: .number, required: false, doc: "垂直位置px"),
                             ParamSpec(name: "startSeconds", kind: .number, required: false, doc: "时间线上出现的起点(秒)"),
                             ParamSpec(name: "durationSeconds", kind: .number, required: false, doc: "停留时长(秒)")]) { store, a in
            guard let id = titleClipID(store, intArg(a, "titleIndex") ?? -1),
                  let cur = findClip(store, id), var spec = cur.title else { return "错误:titleIndex 无效(没有那个标题)" }
            if let t = strArg(a, "text") { spec.text = t }
            if let fs = numArg(a, "fontSize") { spec.fontSize = fs }
            if let c = strArg(a, "colorHex") { spec.colorHex = c }
            if let b = boolArg(a, "bold") { spec.bold = b }
            if let al = intArg(a, "align") { spec.align = max(0, min(2, al)) }
            if let x = numArg(a, "x") { spec.position.x = x }
            if let y = numArg(a, "y") { spec.position.y = y }
            store.dispatch(.setTitle(id, spec))
            // 时间线上的起点/时长(连接片段:offset 相对宿主起点)
            let start = numArg(a, "startSeconds"), dur = numArg(a, "durationSeconds")
            if start != nil || dur != nil {
                var newOffset: Time? = nil
                if let s = start, let absStart = store.clipAbsStart(id) {
                    let hostStart = absStart.seconds - cur.offset.seconds     // 宿主绝对起点
                    newOffset = .seconds(max(0, s - hostStart))
                }
                store.dispatch(.setConnectedTiming(id, offset: newOffset, sourceIn: nil, duration: dur.map { .seconds($0) }))
            }
            return "已编辑标题「\(spec.text)」"
        },
    ]
    static let navigate: [AgentAction] = [
        AgentAction(type: "playhead", domain: .navigate, doc: "把播放头移到 atSeconds 秒。",
                    params: [ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "时间(秒)")]) { store, a in
            store.dispatch(.setPlayhead(.seconds(numArg(a, "atSeconds") ?? 0))); return "播放头到 \(numArg(a, "atSeconds") ?? 0)s"
        },
        AgentAction(type: "zoom", domain: .navigate, doc: "设置时间线缩放 pxPerSecond(像素/秒)。",
                    params: [ParamSpec(name: "pxPerSecond", kind: .number, required: true, doc: "每秒像素数")]) { store, a in
            store.dispatch(.setZoom(numArg(a, "pxPerSecond") ?? 60)); return "缩放设为 \(numArg(a, "pxPerSecond") ?? 60)"
        },
        AgentAction(type: "tool", domain: .navigate, doc: "切换编辑工具:select/trim/position/range/blade/zoom/hand。",
                    params: [ParamSpec(name: "name", kind: .enumString(["select","trim","position","range","blade","zoom","hand"]), required: true, doc: "工具名")]) { store, a in
            guard let t = strArg(a, "name").flatMap({ EditTool(rawValue: $0) }) else { return "错误:未知工具" }
            store.dispatch(.setTool(t)); return "工具切到 \(t.rawValue)"
        },
        AgentAction(type: "select", domain: .navigate, doc: "选中主轴第 clipIndex 个片段(供 inspector 编辑)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引")]) { store, a in
            guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            store.dispatch(.selectClip(id)); return "已选中片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "select_asset", domain: .navigate, doc: "选中素材库第 assetIndex 个素材。",
                    params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引")]) { store, a in
            let i = intArg(a, "assetIndex") ?? -1
            guard store.document.assetLibrary.indices.contains(i) else { return "错误:assetIndex 无效" }
            store.dispatch(.selectAsset(store.document.assetLibrary[i].id)); return "已选中素材 \(i)"
        },
        AgentAction(type: "undo", domain: .navigate, doc: "撤销上一次编辑。", params: []) { store, _ in store.undo(); return "已撤销" },
        AgentAction(type: "redo", domain: .navigate, doc: "重做。", params: []) { store, _ in store.redo(); return "已重做" },
        AgentAction(type: "import", domain: .navigate, doc: "从磁盘绝对路径导入媒体(视频/音乐)到素材库。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "媒体文件绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            do { let asset = try MediaImporter.importAsset(from: URL(fileURLWithPath: p)); store.dispatch(.importAsset(asset)); return "已导入 \(URL(fileURLWithPath: p).lastPathComponent)" }
            catch { return "错误:导入失败 \(error)" }
        },
        AgentAction(type: "export_fcpxml", domain: .navigate, doc: "把当前剪辑导出为 .fcpxml 工程文件到磁盘绝对路径(可回真 FCP 继续剪)。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "目标 .fcpxml 绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            do { try store.exportFCPXML(to: URL(fileURLWithPath: p)); return "已导出 fcpxml 到 \(p)" }
            catch { return "错误:导出失败 \(error)" }
        },
        AgentAction(type: "export_movie", domain: .navigate, doc: "把当前剪辑渲染导出为成片(有视频→mp4,纯音频→m4a)到磁盘绝对路径。异步,返回已开始。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "目标文件绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            store.exportMovie(to: URL(fileURLWithPath: p), settings: ExportSettings()); return "已开始导出成片到 \(p)(渲染中)"
        },
        AgentAction(type: "create_project", domain: .navigate,
                    doc: "新建一个项目(对应 FCP 的 Project,自带分辨率/帧率与独立时间线),并切到它。无项目时必须先建。",
                    params: [ParamSpec(name: "name", kind: .string, required: true, doc: "项目名"),
                             ParamSpec(name: "width", kind: .int, required: false, doc: "宽,默认1920"),
                             ParamSpec(name: "height", kind: .int, required: false, doc: "高,默认1080"),
                             ParamSpec(name: "fps", kind: .number, required: false, doc: "帧率,默认25")]) { store, a in
            let p = Project(name: strArg(a, "name") ?? "项目",
                            formatWidth: intArg(a, "width") ?? 1920,
                            formatHeight: intArg(a, "height") ?? 1080,
                            frameRate: numArg(a, "fps") ?? 25)
            store.dispatch(.createProject(p))
            return "已新建项目「\(p.name)」\(p.formatWidth)×\(p.formatHeight)"
        },
        AgentAction(type: "toggle_snapping", domain: .navigate,
                    doc: "切换磁吸编辑(snapping)开/关。开时切割/修剪/平移会吸附到邻近编辑点。", params: []) { store, _ in
            store.dispatch(.toggleSnapping)
            return store.ui.snappingEnabled ? "磁吸已开" : "磁吸已关"
        },
        AgentAction(type: "rename_project", domain: .navigate,
                    doc: "重命名当前项目(或第 index 个项目)。",
                    params: [ParamSpec(name: "name", kind: .string, required: true, doc: "新名字"),
                             ParamSpec(name: "index", kind: .int, required: false, doc: "项目索引,省略=当前")]) { store, a in
            guard let name = strArg(a, "name") else { return "错误:缺 name" }
            let pid: ProjectID?
            if let i = intArg(a, "index"), store.document.projects.indices.contains(i) { pid = store.document.projects[i].id }
            else { pid = store.document.currentProjectID }
            guard let id = pid else { return "错误:没有项目" }
            store.dispatch(.renameProject(id, name))
            return "已重命名为「\(name)」"
        },
        AgentAction(type: "select_project", domain: .navigate,
                    doc: "切换到第 index 个项目(0基),换出它的时间线。",
                    params: [ParamSpec(name: "index", kind: .int, required: true, doc: "项目索引,0基")]) { store, a in
            let i = intArg(a, "index") ?? -1
            guard store.document.projects.indices.contains(i) else { return "错误:index 无效" }
            store.dispatch(.selectProject(store.document.projects[i].id))
            return "已切到项目「\(store.document.projects[i].name)」"
        },
        AgentAction(type: "remove_project", domain: .navigate,
                    doc: "删除第 index 个项目(省略=当前)。删当前会切到剩下的项目或回到无项目门控。",
                    params: [ParamSpec(name: "index", kind: .int, required: false, doc: "项目索引,省略=当前")]) { store, a in
            let pid: ProjectID?
            if let i = intArg(a, "index"), store.document.projects.indices.contains(i) { pid = store.document.projects[i].id }
            else { pid = store.document.currentProjectID }
            guard let id = pid else { return "错误:没有项目" }
            store.dispatch(.removeProject(id))
            return "已删除项目"
        },
    ]

    // MARK: - system 域(文件读写/目录/命令)

    static let system: [AgentAction] = [
        AgentAction(type: "read_file", domain: .system,
                    doc: "读取本地文件内容(文本,前 2000 行)。返回文件文本或错误。path 必须是绝对路径。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "文件绝对路径")]) { _, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            let url = URL(fileURLWithPath: p)
            guard FileManager.default.fileExists(atPath: p) else { return "错误:文件不存在 \(p)" }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                if lines.count > 2000 {
                    let head = lines.prefix(2000).joined(separator: "\n")
                    return "\(head)\n…(共 \(lines.count) 行,已截断到前 2000 行)"
                }
                return text
            } catch { return "错误:读取失败 \(error.localizedDescription)" }
        },
        AgentAction(type: "write_file", domain: .system,
                    doc: "把文本写入本地文件(覆盖已有内容)。⚠️ 需要用户确认才能执行。path 必须是绝对路径。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "文件绝对路径"),
                             ParamSpec(name: "content", kind: .string, required: true, doc: "要写入的文本内容")]) { store, a in
            guard let p = strArg(a, "path"), let content = strArg(a, "content") else { return "错误:缺 path 或 content" }
            let exists = FileManager.default.fileExists(atPath: p)
            let msg = exists ? "覆盖已有文件 \(p)(\(content.count) 字符)" : "创建新文件 \(p)(\(content.count) 字符)"
            // 通过 confirm 机制让用户确认;实际写入由 confirm 回调执行
            store.requestAgentConfirm(tool: "write_file", message: msg, args: a) { confirmed in
                guard confirmed else { return "用户取消了写入" }
                do {
                    try content.write(toFile: p, atomically: true, encoding: .utf8)
                    return "已写入 \(p)(\(content.count) 字符)"
                } catch { return "错误:写入失败 \(error.localizedDescription)" }
            }
            return "__PENDING_CONFIRM__"
        },
        AgentAction(type: "edit_file", domain: .system,
                    doc: "编辑本地文件:把 oldText 替换为 newText(精确匹配)。⚠️ 需要用户确认。path 必须是绝对路径。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "文件绝对路径"),
                             ParamSpec(name: "oldText", kind: .string, required: true, doc: "要替换的原文"),
                             ParamSpec(name: "newText", kind: .string, required: true, doc: "替换后的新文本")]) { store, a in
            guard let p = strArg(a, "path"), let old = strArg(a, "oldText"), let new = strArg(a, "newText") else {
                return "错误:缺参数"
            }
            guard FileManager.default.fileExists(atPath: p) else { return "错误:文件不存在 \(p)" }
            let msg = "编辑 \(URL(fileURLWithPath: p).lastPathComponent):把 \"\(old.prefix(50))\" 替换为 \"\(new.prefix(50))\""
            store.requestAgentConfirm(tool: "edit_file", message: msg, args: a) { confirmed in
                guard confirmed else { return "用户取消了编辑" }
                do {
                    var text = try String(contentsOfFile: p, encoding: .utf8)
                    guard text.contains(old) else { return "错误:文件中未找到要替换的文本" }
                    text = text.replacingOccurrences(of: old, with: new)
                    try text.write(toFile: p, atomically: true, encoding: .utf8)
                    return "已编辑 \(URL(fileURLWithPath: p).lastPathComponent)"
                } catch { return "错误:编辑失败 \(error.localizedDescription)" }
            }
            return "__PENDING_CONFIRM__"
        },
        AgentAction(type: "list_directory", domain: .system,
                    doc: "列出目录下的文件和子目录(最多 200 项)。path 省略则列出用户桌面。",
                    params: [ParamSpec(name: "path", kind: .string, required: false, doc: "目录绝对路径,省略=桌面")]) { _, a in
            let p = strArg(a, "path") ?? (NSHomeDirectory() + "/Desktop")
            let url = URL(fileURLWithPath: p)
            guard FileManager.default.fileExists(atPath: p) else { return "错误:目录不存在 \(p)" }
            do {
                let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                let prefix = items.prefix(200)
                var out = "\(p)/ (\(items.count) 项)\n"
                for item in prefix {
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let size = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    let tag = isDir ? "📁" : "📄"
                    let sizeStr = isDir ? "" : " \(humanSize(size))"
                    out += "  \(tag) \(item.lastPathComponent)\(sizeStr)\n"
                }
                if items.count > 200 { out += "  …(共 \(items.count) 项,已截断)" }
                return out
            } catch { return "错误:读取目录失败 \(error.localizedDescription)" }
        },
        AgentAction(type: "run_command", domain: .system,
                    doc: "在本机 shell(/bin/bash -lc)执行命令,返回退出码 + stdout/stderr(前 8000 字符)。"
                       + "用途:ffprobe/ffmpeg 探测音视频与音量、python 做数据分析(如找静音区间)等。"
                       + "⚠️ 高危命令(rm -rf/sudo/dd/mkfs/关机/管道执行远程脚本等)会弹确认卡片,用户点允许才执行;"
                       + "普通命令(python/ffmpeg/ffprobe/ls 等)直接后台执行(不冻结界面)。cwd 可选工作目录。",
                    params: [ParamSpec(name: "command", kind: .string, required: true, doc: "shell 命令"),
                             ParamSpec(name: "cwd", kind: .string, required: false, doc: "工作目录(绝对路径),省略=默认")]) { store, a in
            guard let command = strArg(a, "command"), !command.isEmpty else { return "错误:缺 command" }
            let cwd = strArg(a, "cwd")
            if isDangerousCommand(command) {
                // 高危 → 确认卡片;确认后同步执行(这类命令 rm/sudo 通常很快)
                store.requestAgentConfirm(tool: "run_command", message: "⚠️ 高危命令,确认执行?\n\(command)", args: a) { confirmed in
                    guard confirmed else { return "用户拒绝执行该命令" }
                    return runShell(command, cwd: cwd)
                }
                return "__PENDING_CONFIRM__"
            }
            // 普通命令 → 后台线程执行(ffmpeg/python 可能耗时,主线程不冻结),结果经 agentAsyncResult 回传。
            store.agentAsyncResult = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let out = runShell(command, cwd: cwd)
                DispatchQueue.main.async { store.agentAsyncResult = (UUID(), out) }
            }
            return "__PENDING_ASYNC__"
        },
    ]

    /// 高危命令判定:破坏性删除 / 提权 / 磁盘 / 关机 / 管道执行远程脚本 → 需用户确认。
    /// 普通命令(python/ffmpeg/ffprobe/ls/grep…)直接放行。
    static func isDangerousCommand(_ cmd: String) -> Bool {
        let c = " " + cmd.lowercased() + " "
        let patterns = [
            "rm -rf", "rm -fr", "rm -r ", "rm -f ", " rm -r", " rm -f", "rmdir ",
            "sudo ", "dd if=", "dd of=", "mkfs", "diskutil ", ":(){",
            "shutdown", "reboot", " halt ", "killall", "pkill ", "launchctl ",
            "chmod -r", "chown -r", "chmod 777", "| sh", "|sh", "| bash", "|bash",
            "> /dev", "mv /", "> /etc", "> /usr", "> /bin", "> /system", "> /library",
        ]
        return patterns.contains { c.contains($0) }
    }

    /// 同步执行 shell 命令(应在后台线程调用),返回 "退出码 N\n<输出>"(截断 8000 字符,120s 超时)。
    static func runShell(_ command: String, cwd: String?) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", command]   // 登录 shell:带上用户 PATH(conda/ffmpeg/python)
        if let cwd, FileManager.default.fileExists(atPath: cwd) {
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return "错误:无法执行 \(error.localizedDescription)" }
        // 120s 超时:后台读输出,超时则终止。
        let sem = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            sem.signal()
        }
        if sem.wait(timeout: .now() + 120) == .timedOut {
            proc.terminate()
            return "错误:命令超时(120s)已终止:\(command)"
        }
        proc.waitUntilExit()
        var out = String(data: data, encoding: .utf8) ?? ""
        if out.count > 8000 { out = String(out.prefix(8000)) + "\n…(输出已截断到 8000 字符)" }
        return "退出码 \(proc.terminationStatus)\n" + (out.isEmpty ? "(无输出)" : out)
    }

    /// 人类可读的文件大小。
    private static func humanSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1fMB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.1fGB", Double(bytes) / 1024 / 1024 / 1024)
    }
}
