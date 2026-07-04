import Foundation
import CoreGraphics

extension AgentActionCatalog {
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
}
