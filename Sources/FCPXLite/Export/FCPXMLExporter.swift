// Sources/FCPXLite/Export/FCPXMLExporter.swift
import Foundation

/// Document → FCPXML 字符串(纯字符串拼装,无语义转换)。概念与 FCPXML 一一对应。
///
/// 关键时间语义(经 srt-to-fcpxml 参考代码 + 官方 DTD 验证):
/// - spine 顶层 clip 的 `offset` = 绝对时间线位置(这里用累加游标 cursor 显式写出)。
/// - 连接子项(lane≠0,如字幕)的 `offset` 是【父级本地坐标】,原点是父 clip 的 `start`(=sourceIn),
///   即 childOffset = 宿主.sourceIn + 子项相对 offset。FCP 导入时算 父offset+(childOffset−父start) 得绝对位置。
///   若直接写相对值会漏掉 sourceIn,字幕全部偏早(大 sourceIn 时堆到 0)。
/// - 字幕位置用 <adjust-transform position>,单位是【画幅百分比,1=1%】,原点画面中心、y 向上为正(非像素!)。
enum FCPXMLExporter {
    static func export(_ document: Document) -> String {
        let fr = document.frameRate > 0 ? document.frameRate : 25
        let frameDur = "100/\(Int(fr.rounded()) * 100)s"   // FCP 惯用 100/N00s(30fps→100/3000s)
        let w = document.formatWidth, h = document.formatHeight
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<!DOCTYPE fcpxml>\n<fcpxml version=\"1.10\">\n"

        // resources:每个 asset 一个 <asset>,共用一个 <format>;有字幕则加一个字幕生成器
        s += "  <resources>\n"
        // 真实 FCP 对自定义分辨率【不写 name】(写 name 必须匹配 FCP 预定义标识符,否则判非法)+ 带 colorSpace。
        s += "    <format id=\"r0\" frameDuration=\"\(frameDur)\" width=\"\(w)\" height=\"\(h)\" colorSpace=\"1-1-1 (Rec. 709)\"/>\n"
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

        // library → event → project → sequence → spine
        s += "  <library>\n    <event name=\"Final Cut Bro\">\n      <project name=\"Final Cut Bro Project\">\n"
        s += "        <sequence format=\"r0\">\n          <spine>\n"
        var cursor = Time.zero   // 绝对时间线游标
        for el in document.sequence.spine {
            switch el {
            case .gap(_, let d):
                s += "            <gap offset=\"\(time(cursor))\" duration=\"\(time(d))\"/>\n"
            case .clip(let c):
                s += clipXML(c, timelineOffset: cursor, document: document, frameW: w, frameH: h, indent: "            ")
            }
            cursor = cursor + el.duration
        }
        s += "          </spine>\n        </sequence>\n"
        s += "      </project>\n    </event>\n  </library>\n</fcpxml>\n"
        return s
    }

    /// spine 顶层 clip → <asset-clip>(或标题 → <title>),offset = 绝对时间线位置 timelineOffset。
    private static func clipXML(_ c: Clip, timelineOffset: Time, document: Document,
                                frameW: Int, frameH: Int, indent: String) -> String {
        // 顶层标题(少见:字幕通常是连接子项)。
        if let spec = c.title {
            return titleXML(c, spec: spec, offset: timelineOffset, frameW: frameW, frameH: frameH, indent: indent)
        }
        guard let idx = document.assetLibrary.firstIndex(where: { $0.id == c.assetID }) else { return "" }
        let name = esc(document.assetLibrary[idx].url.lastPathComponent)
        let attrs = "ref=\"a\(idx)\" name=\"\(name)\" offset=\"\(time(timelineOffset))\" duration=\"\(time(c.duration))\" start=\"\(time(c.sourceIn))\""
        if c.connected.isEmpty {
            return "\(indent)<asset-clip \(attrs)/>\n"
        }
        var s = "\(indent)<asset-clip \(attrs)>\n"
        // 连接子项 offset 用父级本地坐标(原点 = 本 clip 的 start = sourceIn)。
        for child in c.connected {
            s += connectedXML(child, parentStart: c.sourceIn, document: document, frameW: frameW, frameH: frameH, indent: indent + "  ")
        }
        s += "\(indent)</asset-clip>\n"
        return s
    }

    /// 连接子项(lane≠0)→ <title> 或 <asset-clip>。offset = parentStart + 子项相对 offset(父级本地坐标)。
    private static func connectedXML(_ c: Clip, parentStart: Time, document: Document,
                                     frameW: Int, frameH: Int, indent: String) -> String {
        let fcpOffset = parentStart + c.offset
        if let spec = c.title {
            return titleXML(c, spec: spec, offset: fcpOffset, frameW: frameW, frameH: frameH, indent: indent)
        }
        guard let idx = document.assetLibrary.firstIndex(where: { $0.id == c.assetID }) else { return "" }
        let name = esc(document.assetLibrary[idx].url.lastPathComponent)
        let attrs = "ref=\"a\(idx)\" name=\"\(name)\" lane=\"\(c.lane)\" offset=\"\(time(fcpOffset))\" duration=\"\(time(c.duration))\" start=\"\(time(c.sourceIn))\""
        if c.connected.isEmpty {
            return "\(indent)<asset-clip \(attrs)/>\n"
        }
        var s = "\(indent)<asset-clip \(attrs)>\n"
        for child in c.connected {
            s += connectedXML(child, parentStart: c.sourceIn, document: document, frameW: frameW, frameH: frameH, indent: indent + "  ")
        }
        s += "\(indent)</asset-clip>\n"
        return s
    }

    /// 标题片段 → <title>:引用共享字幕生成器,文本/样式进 <text>/<text-style-def>,位置进 <adjust-transform>。
    /// `offset` 是已算好的父级本地坐标(顶层=绝对时间线;连接=parentStart+相对)。
    private static func titleXML(_ c: Clip, spec: TitleSpec, offset: Time,
                                 frameW: Int, frameH: Int, indent: String) -> String {
        let tsid = "ts_" + c.id.raw.replacingOccurrences(of: "-", with: "")
        var attrs = "ref=\"r_title\" name=\"\(esc(spec.text))\" offset=\"\(time(offset))\" duration=\"\(time(c.duration))\" start=\"3600s\""
        if c.lane != 0 { attrs += " lane=\"\(c.lane)\"" }
        let font = spec.fontName ?? "PingFang SC"
        let face = spec.bold ? "Bold" : "Regular"
        let alignName = ["left", "center", "right"][min(max(spec.align, 0), 2)]
        var s = "\(indent)<title \(attrs)>\n"
        // DTD 子元素顺序:param*, text*, text-style-def*, note?, (…adjust-transform?…), … —— 先文本再 adjust-transform。
        s += "\(indent)  <text>\n"
        s += "\(indent)    <text-style ref=\"\(tsid)\">\(esc(spec.text))</text-style>\n"
        s += "\(indent)  </text>\n"
        s += "\(indent)  <text-style-def id=\"\(tsid)\">\n"
        var ts = "font=\"\(esc(font))\" fontSize=\"\(Int(spec.fontSize.rounded()))\" fontFace=\"\(face)\" fontColor=\"\(rgba(spec.colorHex))\" alignment=\"\(alignName)\""
        if spec.strokeWidth > 0 { ts += " strokeColor=\"\(rgba(spec.strokeColorHex))\" strokeWidth=\"\(Int(spec.strokeWidth.rounded()))\"" }
        s += "\(indent)    <text-style \(ts)/>\n"
        s += "\(indent)  </text-style-def>\n"
        // adjust-transform position:单位=画幅百分比(1=1%),原点中心、y 向上为正。
        // TitleSpec.position 是渲染像素、y 向下为正 → 换算成百分比并翻 y 符号。必须排在 text/text-style-def 之后(DTD)。
        if spec.position.x != 0 || spec.position.y != 0 {
            let px = frameW > 0 ? Double(spec.position.x) / Double(frameW) * 100 : 0
            let py = frameH > 0 ? Double(spec.position.y) / Double(frameH) * 100 : 0
            s += "\(indent)  <adjust-transform position=\"\(fmt(px)) \(fmt(-py))\"/>\n"
        }
        s += "\(indent)</title>\n"
        return s
    }

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

    /// FCPXML 有理时间。复用模型的 Time.fcpxmlString(零写 "0s")。
    private static func time(_ t: Time) -> String { t.fcpxmlString }

    /// XML 属性转义。
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
