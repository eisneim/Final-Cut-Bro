// Sources/FCPXLite/Export/FCPXMLExporter.swift
import Foundation

/// Document → FCPXML 字符串(纯字符串拼装,无语义转换)。概念与 FCPXML 一一对应。
///
/// 关键语义(经 srt-to-fcpxml 参考代码 + 官方 DTD 验证):
/// - 所有时间【按帧对齐】:秒→round(秒×fps)=帧,写成 `帧×100/(fps×100)s`。否则 FCP 报"此项目不在编辑帧边界上"。
/// - spine 顶层 clip 的 `offset` = 绝对时间线(整数帧游标累加,保证首尾相接不漂移)。
/// - 连接子项(lane≠0,如字幕)的 `offset` = 父级本地坐标:宿主 sourceIn 帧 + 子项相对 offset 帧
///   (FCP 导入算 父offset+(childOffset−父start) 得绝对位置;直接写相对值会漏 sourceIn → 字幕堆到 0)。
/// - 字幕位置 `<adjust-transform position>` 单位=画幅百分比(1=1%),原点中心、y 向上为正(非像素)。
/// - 字幕 fontSize 按分辨率缩放(以 1080 高为基准:4K→×2),否则高分辨率下字太小。
enum FCPXMLExporter {
    private static let fontRefHeight = 1080.0   // fontSize 缩放基准高度

    static func export(_ document: Document) -> String {
        let fr = document.frameRate > 0 ? document.frameRate : 25
        let fps = max(1, Int(fr.rounded()))
        let w = document.formatWidth, h = document.formatHeight
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<!DOCTYPE fcpxml>\n<fcpxml version=\"1.10\">\n"

        s += "  <resources>\n"
        // 真实 FCP 对自定义分辨率【不写 name】+ 带 colorSpace;frameDuration 用 100/N00s。
        s += "    <format id=\"r0\" frameDuration=\"100/\(fps * 100)s\" width=\"\(w)\" height=\"\(h)\" colorSpace=\"1-1-1 (Rec. 709)\"/>\n"
        for (i, a) in document.assetLibrary.enumerated() {
            let hasV = a.kind != .audio ? "1" : "0"
            let hasA = a.hasAudio ? "1" : "0"
            s += "    <asset id=\"a\(i)\" name=\"\(esc(a.url.lastPathComponent))\" duration=\"\(time(a.duration))\" hasVideo=\"\(hasV)\" hasAudio=\"\(hasA)\" format=\"r0\">\n"
            s += "      <media-rep kind=\"original-media\" src=\"\(esc(a.url.absoluteString))\"/>\n"
            s += "    </asset>\n"
        }
        if hasAnyTitle(document) {
            // Custom.moti:跨版本/语言最稳、无预设动画的基础字幕生成器(srt-to-fcpxml 参考代码同款)。
            s += "    <effect id=\"r_title\" name=\"Custom\" uid=\".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti\"/>\n"
        }
        s += "  </resources>\n"

        s += "  <library>\n    <event name=\"Final Cut Bro\">\n      <project name=\"Final Cut Bro Project\">\n"
        s += "        <sequence format=\"r0\">\n          <spine>\n"
        var cursorF = 0   // 绝对时间线游标(整数帧)
        for el in document.sequence.spine {
            let durF = frames(el.duration.seconds, fps)
            switch el {
            case .gap(_, let d):
                s += "            <gap offset=\"\(frameStr(cursorF, fps))\" duration=\"\(frameStr(frames(d.seconds, fps), fps))\"/>\n"
            case .clip(let c):
                s += clipXML(c, offsetF: cursorF, document: document, fps: fps, frameW: w, frameH: h, indent: "            ")
            }
            cursorF += durF
        }
        s += "          </spine>\n        </sequence>\n"
        s += "      </project>\n    </event>\n  </library>\n</fcpxml>\n"
        return s
    }

    /// spine 顶层 clip → <asset-clip>(或标题 → <title>),offset = 绝对时间线帧 offsetF。
    private static func clipXML(_ c: Clip, offsetF: Int, document: Document,
                               fps: Int, frameW: Int, frameH: Int, indent: String) -> String {
        if let spec = c.title {
            return titleXML(c, spec: spec, offsetF: offsetF, fps: fps, frameW: frameW, frameH: frameH, indent: indent)
        }
        guard let idx = document.assetLibrary.firstIndex(where: { $0.id == c.assetID }) else { return "" }
        let name = esc(document.assetLibrary[idx].url.lastPathComponent)
        let attrs = "ref=\"a\(idx)\" name=\"\(name)\" offset=\"\(frameStr(offsetF, fps))\" duration=\"\(frameStr(frames(c.duration.seconds, fps), fps))\" start=\"\(frameStr(frames(c.sourceIn.seconds, fps), fps))\""
        if c.connected.isEmpty { return "\(indent)<asset-clip \(attrs)/>\n" }
        var s = "\(indent)<asset-clip \(attrs)>\n"
        let startF = frames(c.sourceIn.seconds, fps)   // 连接子项 offset 原点 = 本 clip 的 start
        for child in c.connected {
            s += connectedXML(child, parentStartF: startF, document: document, fps: fps, frameW: frameW, frameH: frameH, indent: indent + "  ")
        }
        s += "\(indent)</asset-clip>\n"
        return s
    }

    /// 连接子项(lane≠0)→ <title> 或 <asset-clip>。offset = parentStartF + 子项相对 offset 帧(父级本地坐标)。
    private static func connectedXML(_ c: Clip, parentStartF: Int, document: Document,
                                     fps: Int, frameW: Int, frameH: Int, indent: String) -> String {
        let offF = parentStartF + frames(c.offset.seconds, fps)
        if let spec = c.title {
            return titleXML(c, spec: spec, offsetF: offF, fps: fps, frameW: frameW, frameH: frameH, indent: indent)
        }
        guard let idx = document.assetLibrary.firstIndex(where: { $0.id == c.assetID }) else { return "" }
        let name = esc(document.assetLibrary[idx].url.lastPathComponent)
        let attrs = "ref=\"a\(idx)\" name=\"\(name)\" lane=\"\(c.lane)\" offset=\"\(frameStr(offF, fps))\" duration=\"\(frameStr(frames(c.duration.seconds, fps), fps))\" start=\"\(frameStr(frames(c.sourceIn.seconds, fps), fps))\""
        if c.connected.isEmpty { return "\(indent)<asset-clip \(attrs)/>\n" }
        var s = "\(indent)<asset-clip \(attrs)>\n"
        let startF = frames(c.sourceIn.seconds, fps)
        for child in c.connected {
            s += connectedXML(child, parentStartF: startF, document: document, fps: fps, frameW: frameW, frameH: frameH, indent: indent + "  ")
        }
        s += "\(indent)</asset-clip>\n"
        return s
    }

    /// 标题片段 → <title>。offsetF 已是算好的帧(顶层=绝对;连接=parentStartF+相对)。
    private static func titleXML(_ c: Clip, spec: TitleSpec, offsetF: Int,
                                 fps: Int, frameW: Int, frameH: Int, indent: String) -> String {
        let tsid = "ts_" + c.id.raw.replacingOccurrences(of: "-", with: "")
        var attrs = "ref=\"r_title\" name=\"\(esc(spec.text))\" offset=\"\(frameStr(offsetF, fps))\" duration=\"\(frameStr(frames(c.duration.seconds, fps), fps))\" start=\"3600s\""
        if c.lane != 0 { attrs += " lane=\"\(c.lane)\"" }
        let font = spec.fontName ?? "PingFang SC"
        let face = spec.bold ? "Bold" : "Regular"
        let alignName = ["left", "center", "right"][min(max(spec.align, 0), 2)]
        // fontSize 按分辨率缩放(1080 为基准):4K(2160)→×2,否则高分辨率下字太小。
        let fontPx = max(1, Int((spec.fontSize * Double(frameH) / fontRefHeight).rounded()))
        var s = "\(indent)<title \(attrs)>\n"
        // DTD 子元素顺序:text, text-style-def, 然后 adjust-transform。
        s += "\(indent)  <text>\n"
        s += "\(indent)    <text-style ref=\"\(tsid)\">\(esc(spec.text))</text-style>\n"
        s += "\(indent)  </text>\n"
        s += "\(indent)  <text-style-def id=\"\(tsid)\">\n"
        var ts = "font=\"\(esc(font))\" fontSize=\"\(fontPx)\" fontFace=\"\(face)\" fontColor=\"\(rgba(spec.colorHex))\" alignment=\"\(alignName)\""
        if spec.strokeWidth > 0 { ts += " strokeColor=\"\(rgba(spec.strokeColorHex))\" strokeWidth=\"\(Int(spec.strokeWidth.rounded()))\"" }
        s += "\(indent)    <text-style \(ts)/>\n"
        s += "\(indent)  </text-style-def>\n"
        // adjust-transform position:画幅百分比(1=1%),y 向上为正;TitleSpec.position 是像素、y 向下为正 → 换算+翻 y。
        if spec.position.x != 0 || spec.position.y != 0 {
            let px = frameW > 0 ? Double(spec.position.x) / Double(frameW) * 100 : 0
            let py = frameH > 0 ? Double(spec.position.y) / Double(frameH) * 100 : 0
            s += "\(indent)  <adjust-transform position=\"\(fmt(px)) \(fmt(-py))\"/>\n"
        }
        s += "\(indent)</title>\n"
        return s
    }

    // MARK: - 帧对齐时间

    /// 秒 → 整数帧(四舍五入,非负)。
    private static func frames(_ seconds: Double, _ fps: Int) -> Int { max(0, Int((seconds * Double(fps)).rounded())) }
    /// 整数帧 → FCPXML 帧对齐时间串 `帧×100/(fps×100)s`(0 写 "0s")。
    private static func frameStr(_ f: Int, _ fps: Int) -> String { f == 0 ? "0s" : "\(f * 100)/\(fps * 100)s" }

    /// spine 里(含连接子项)是否存在任一标题片段。
    private static func hasAnyTitle(_ document: Document) -> Bool {
        for el in document.sequence.spine {
            if case .clip(let c) = el {
                if c.title != nil { return true }
                if c.connected.contains(where: { $0.title != nil }) { return true }
            }
        }
        return false
    }

    /// #RRGGBB(或 #RGB)→ FCPXML 颜色 "r g b a"(各 0–1)。解析失败回退白色。
    private static func rgba(_ hex: String) -> String {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return "1 1 1 1" }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        return "\(fmt(r)) \(fmt(g)) \(fmt(b)) 1"
    }
    private static func fmt(_ d: Double) -> String { String(format: "%.4g", d) }

    /// FCPXML 有理时间(仅用于 asset 资源自然时长,非编辑点)。
    private static func time(_ t: Time) -> String { t.fcpxmlString }

    /// XML 属性转义。
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
