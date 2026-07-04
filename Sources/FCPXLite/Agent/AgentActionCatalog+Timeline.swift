import Foundation
import CoreGraphics

extension AgentActionCatalog {
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
                let assetDur = store.document.assetDuration(of: c)
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
            let assetDur = store.document.assetDuration(of: c)
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
            let prevDur = store.document.assetDuration(of: prev)
            let nextDur = store.document.assetDuration(of: next)
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
}
