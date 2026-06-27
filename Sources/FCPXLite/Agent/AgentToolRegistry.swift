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
            Tool(name: "get_timeline", description: "获取当前时间线与素材库的完整状态摘要(片段、时长、层级、播放头)。在做任何编辑前先调用以了解现状。",
                 parameters: obj([:])),
            Tool(name: "import_asset", description: "从文件路径导入一个媒体素材到素材库。",
                 parameters: obj(["path": str("媒体文件的绝对路径")], required: ["path"])),
            Tool(name: "append_clip", description: "把素材库中第 assetIndex 个素材追加到主时间线末尾。",
                 parameters: obj(["assetIndex": int("素材库索引,从0开始")], required: ["assetIndex"])),
            Tool(name: "insert_clip", description: "在时间线 atSeconds 秒处把第 assetIndex 个素材插入主时间线(后续片段右移)。",
                 parameters: obj(["assetIndex": int("素材库索引"), "atSeconds": num("插入的时间位置(秒)")], required: ["assetIndex", "atSeconds"])),
            Tool(name: "connect_clip", description: "把第 assetIndex 个素材作为连接片段叠加到 atSeconds 处、第 lane 层(lane>0在主轴上方,<0在下方)。用于画中画/叠加。",
                 parameters: obj(["assetIndex": int("素材库索引"), "atSeconds": num("时间位置(秒)"), "lane": int("层级,正数在上,默认1")], required: ["assetIndex", "atSeconds"])),
            Tool(name: "delete_clip", description: "删除主时间线第 spineIndex 个片段(ripple 删除,后续合拢)。",
                 parameters: obj(["spineIndex": int("主轴片段索引,从0")], required: ["spineIndex"])),
            Tool(name: "blade_clip", description: "在 atSeconds 处把所在的主轴片段切成两段。",
                 parameters: obj(["atSeconds": num("切割的时间位置(秒)")], required: ["atSeconds"])),
            Tool(name: "move_clip", description: "把主轴第 spineIndex 个片段移动到第 lane 层、atSeconds 处。lane=0放回主轴,lane!=0变连接片段。",
                 parameters: obj(["spineIndex": int("主轴片段索引"), "lane": int("目标层级"), "atSeconds": num("目标时间(秒)")], required: ["spineIndex", "lane", "atSeconds"])),
            Tool(name: "trim_clip", description: "修剪主轴第 spineIndex 个片段的首或尾。edge=head 改入点,edge=tail 改时长。",
                 parameters: obj(["spineIndex": int("片段索引"), "edge": enm(["head", "tail"], "修剪哪一端"), "seconds": num("head:入点偏移; tail:新时长(秒)")], required: ["spineIndex", "edge", "seconds"])),
            Tool(name: "set_adjust", description: "调整主轴第 spineIndex 个片段的画面参数:不透明度/缩放/位置(用于层级显示、画中画大小)。",
                 parameters: obj(["spineIndex": int("片段索引"), "opacity": num("不透明度0-1,可选"), "scale": num("缩放0.1-4,可选"), "posX": num("水平位移px,可选"), "posY": num("垂直位移px,可选")], required: ["spineIndex"])),
            Tool(name: "set_playhead", description: "把播放头移到 atSeconds 秒。",
                 parameters: obj(["atSeconds": num("时间位置(秒)")], required: ["atSeconds"])),
            Tool(name: "undo", description: "撤销上一次编辑。", parameters: obj([:])),
            Tool(name: "redo", description: "重做。", parameters: obj([:])),
        ]
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
        switch name {
        case "get_timeline":
            return timelineSummary()
        case "import_asset":
            guard let path = args["path"] as? String else { return "错误:缺少 path" }
            do { let a = try MediaImporter.importAsset(from: URL(fileURLWithPath: path))
                 store.dispatch(.importAsset(a))
                 return "已导入 \(a.url.lastPathComponent)(时长 \(fmt(a.duration.seconds))s),现素材库 \(store.document.assetLibrary.count) 个" }
            catch { return "导入失败:\(error.localizedDescription)" }
        case "append_clip":
            guard let ai = intArg(args, "assetIndex"), let clip = clipFromAsset(ai) else { return "错误:assetIndex 无效" }
            store.dispatch(.insertClip(clip, at: store.document.sequence.spine.count))
            return "已追加,主轴现有 \(spineClipCount()) 个片段"
        case "insert_clip":
            guard let ai = intArg(args, "assetIndex"), let clip = clipFromAsset(ai) else { return "错误:assetIndex 无效" }
            let at = numArg(args, "atSeconds") ?? 0
            store.dispatch(.insertClip(clip, at: spineIndex(atSeconds: at)))
            return "已在 \(fmt(at))s 处插入,主轴现有 \(spineClipCount()) 个片段"
        case "connect_clip":
            guard let ai = intArg(args, "assetIndex"), let clip = clipFromAsset(ai) else { return "错误:assetIndex 无效" }
            let at = numArg(args, "atSeconds") ?? 0
            let lane = intArg(args, "lane") ?? 1
            guard let host = hostSpineIndex(atSeconds: at) else { return "错误:该时间没有主轴片段可挂靠" }
            let hostAbs = spineAbsStart(host)
            store.dispatch(.connect(clip, host: host, lane: lane, offset: .seconds(max(0, at - hostAbs))))
            return "已把素材作为连接片段叠加到 lane \(lane)"
        case "delete_clip":
            guard let si = intArg(args, "spineIndex"), let ei = spineElementIndex(clipIndex: si) else { return "错误:spineIndex 无效" }
            store.dispatch(.rippleDelete(at: ei))
            return "已删除,主轴现有 \(spineClipCount()) 个片段"
        case "blade_clip":
            let at = numArg(args, "atSeconds") ?? 0
            store.dispatch(.setPlayhead(.seconds(at))); store.bladeAtPlayhead()
            return "已在 \(fmt(at))s 处切割,主轴现有 \(spineClipCount()) 个片段"
        case "move_clip":
            guard let si = intArg(args, "spineIndex"), let id = spineClipID(si) else { return "错误:spineIndex 无效" }
            let lane = intArg(args, "lane") ?? 0
            let at = numArg(args, "atSeconds") ?? 0
            store.dispatch(.relocateClip(id, lane: lane, time: .seconds(at)))
            return "已移动片段到 lane \(lane)、\(fmt(at))s"
        case "trim_clip":
            guard let si = intArg(args, "spineIndex"), let ei = spineElementIndex(clipIndex: si),
                  case .clip(let c) = store.document.sequence.spine[ei] else { return "错误:spineIndex 无效" }
            let edge = args["edge"] as? String ?? "tail"
            let sec = numArg(args, "seconds") ?? 0
            let assetDur = store.document.assetLibrary.first { $0.id == c.assetID }?.duration ?? c.duration
            if edge == "head" { store.dispatch(.trimLeft(at: ei, deltaIn: .seconds(sec))) }
            else { store.dispatch(.trimRight(at: ei, newDuration: .seconds(sec), assetDuration: assetDur)) }
            return "已修剪片段 \(edge)"
        case "set_adjust":
            guard let si = intArg(args, "spineIndex"), let id = spineClipID(si),
                  case .clip(var c) = store.document.sequence.spine[spineElementIndex(clipIndex: si)!] else { return "错误:spineIndex 无效" }
            var a = c.adjust
            if let o = numArg(args, "opacity") { a.opacity = o }
            if let s = numArg(args, "scale") { a.transform.scale = CGSize(width: s, height: s) }
            if let x = numArg(args, "posX") { a.transform.position.x = CGFloat(x) }
            if let y = numArg(args, "posY") { a.transform.position.y = CGFloat(y) }
            store.dispatch(.setAdjust(id, a)); _ = c
            return "已调整片段画面参数"
        case "set_playhead":
            let at = numArg(args, "atSeconds") ?? 0
            store.dispatch(.setPlayhead(.seconds(at)))
            return "播放头移到 \(fmt(at))s"
        case "undo": store.undo(); return "已撤销"
        case "redo": store.redo(); return "已重做"
        default: return "未知工具:\(name)"
        }
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
            case .gap(let d): s += "  (间隙 \(fmt(d.seconds))s)\n"; acc += d.seconds
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

    private func clipFromAsset(_ i: Int) -> Clip? {
        guard store.document.assetLibrary.indices.contains(i) else { return nil }
        let a = store.document.assetLibrary[i]
        return Clip(assetID: a.id, sourceIn: .zero, duration: a.duration)
    }
    private func spineClipCount() -> Int { store.document.sequence.spine.reduce(0) { if case .clip = $1 { return $0 + 1 }; return $0 } }
    private func spineClipID(_ clipIndex: Int) -> ClipID? {
        var n = 0
        for el in store.document.sequence.spine { if case .clip(let c) = el { if n == clipIndex { return c.id }; n += 1 } }
        return nil
    }
    private func spineElementIndex(clipIndex: Int) -> Int? {
        var n = 0
        for (i, el) in store.document.sequence.spine.enumerated() { if case .clip = el { if n == clipIndex { return i }; n += 1 } }
        return nil
    }
    private func spineIndex(atSeconds t: Double) -> Int {
        var acc = 0.0; var idx = 0
        for el in store.document.sequence.spine { if acc < t { idx += 1 }; acc += el.duration.seconds }
        return min(idx, store.document.sequence.spine.count)
    }
    private func hostSpineIndex(atSeconds t: Double) -> Int? {
        var acc = 0.0
        for (i, el) in store.document.sequence.spine.enumerated() {
            if case .clip = el, t >= acc, t < acc + el.duration.seconds { return i }
            acc += el.duration.seconds
        }
        // 没有精确命中 → 最后一个 clip
        for i in stride(from: store.document.sequence.spine.count - 1, through: 0, by: -1) {
            if case .clip = store.document.sequence.spine[i] { return i }
        }
        return nil
    }
    private func spineAbsStart(_ elementIndex: Int) -> Double {
        store.document.sequence.spine[0..<elementIndex].reduce(0) { $0 + $1.duration.seconds }
    }
    private func clipName(_ id: ClipID) -> String {
        for el in store.document.sequence.spine {
            if case .clip(let c) = el {
                if c.id == id { return store.document.assetLibrary.first { $0.id == c.assetID }?.url.lastPathComponent ?? "?" }
                for ch in c.connected where ch.id == id { return store.document.assetLibrary.first { $0.id == ch.assetID }?.url.lastPathComponent ?? "?" }
            }
        }
        return "?"
    }
    private func intArg(_ a: [String: Any], _ k: String) -> Int? { (a[k] as? Int) ?? (a[k] as? Double).map(Int.init) ?? (a[k] as? NSNumber)?.intValue }
    private func numArg(_ a: [String: Any], _ k: String) -> Double? { (a[k] as? Double) ?? (a[k] as? Int).map(Double.init) ?? (a[k] as? NSNumber)?.doubleValue }
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
}
