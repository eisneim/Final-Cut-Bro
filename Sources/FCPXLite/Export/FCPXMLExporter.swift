// Sources/FCPXLite/Export/FCPXMLExporter.swift
import Foundation

/// Document → FCPXML 字符串(纯字符串拼装,无语义转换)。概念与 FCPXML 一一对应。
/// 验收线:结构合法可解析 + 基础剪辑信息正确;字幕以 <title> 导出(文本/字号/颜色/对齐/描边),
/// 引用内置 Basic Title 生成器(uid 若在目标机不解析,文本样式仍随 text-style 落盘,不丢内容)。
enum FCPXMLExporter {
    static func export(_ document: Document) -> String {
        let fr = document.frameRate > 0 ? document.frameRate : 25
        // FCP 惯用 100/N00s 形式(30fps→100/3000s, 25fps→100/2500s)。
        let frameDur = "100/\(Int(fr.rounded()) * 100)s"
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<!DOCTYPE fcpxml>\n<fcpxml version=\"1.10\">\n"

        // resources:每个 asset 一个 <asset>,共用一个 <format>;有字幕则加一个 Basic Title 生成器
        s += "  <resources>\n"
        // 真实 FCP 对自定义分辨率【不写 name】(写 name 必须匹配 FCP 预定义标识符,否则判非法)+ 带 colorSpace。
        s += "    <format id=\"r0\" frameDuration=\"\(frameDur)\" width=\"\(document.formatWidth)\" height=\"\(document.formatHeight)\" colorSpace=\"1-1-1 (Rec. 709)\"/>\n"
        for (i, a) in document.assetLibrary.enumerated() {
            let dur = time(a.duration)
            let hasV = a.kind != .audio ? "1" : "0"
            let hasA = a.hasAudio ? "1" : "0"
            s += "    <asset id=\"a\(i)\" name=\"\(esc(a.url.lastPathComponent))\" duration=\"\(dur)\" hasVideo=\"\(hasV)\" hasAudio=\"\(hasA)\" format=\"r0\">\n"
            s += "      <media-rep kind=\"original-media\" src=\"\(esc(a.url.absoluteString))\"/>\n"
            s += "    </asset>\n"
        }
        if hasAnyTitle(document) {
            // 内置 Basic Title 生成器。子目录段是 "Bumper:Opener.localized"(真实 FCP 导出即此),
            // ".../" 前缀是 FCP 对内置模板目录的占位,原样保留由 FCP 解析。
            s += "    <effect id=\"r_title\" name=\"Basic Title\" uid=\".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti\"/>\n"
        }
        s += "  </resources>\n"

        // library → event → project → sequence → spine
        s += "  <library>\n    <event name=\"Final Cut Bro\">\n      <project name=\"Final Cut Bro Project\">\n"
        s += "        <sequence format=\"r0\">\n          <spine>\n"
        for el in document.sequence.spine {
            switch el {
            case .gap(_, let d):
                s += "            <gap duration=\"\(time(d))\"/>\n"
            case .clip(let c):
                s += clipXML(c, document: document, indent: "            ")
            }
        }
        s += "          </spine>\n        </sequence>\n"
        s += "      </project>\n    </event>\n  </library>\n</fcpxml>\n"
        return s
    }

    /// 单个 clip → <asset-clip>(或标题片段 → <title>),递归嵌入连接子项(带 lane/offset)。
    private static func clipXML(_ c: Clip, document: Document, indent: String) -> String {
        // 标题片段:不引用真实 asset,序列化成 <title>。
        // (修复:此前对 title 走 firstIndex(assetID) 找不到直接 return "" → 字幕被静默丢弃)
        if let spec = c.title {
            return titleXML(c, spec: spec, indent: indent)
        }
        guard let idx = document.assetLibrary.firstIndex(where: { $0.id == c.assetID }) else { return "" }
        let name = esc(document.assetLibrary[idx].url.lastPathComponent)
        let dur = time(c.duration)
        let start = time(c.sourceIn)
        var attrs = "ref=\"a\(idx)\" name=\"\(name)\" duration=\"\(dur)\" start=\"\(start)\""
        if c.lane != 0 { attrs += " lane=\"\(c.lane)\" offset=\"\(time(c.offset))\"" }
        if c.connected.isEmpty {
            return "\(indent)<asset-clip \(attrs)/>\n"
        }
        var s = "\(indent)<asset-clip \(attrs)>\n"
        for child in c.connected {
            s += clipXML(child, document: document, indent: indent + "  ")
        }
        s += "\(indent)</asset-clip>\n"
        return s
    }

    /// 标题片段 → <title>:引用共享的 Basic Title 生成器,文本与样式写进 <text>/<text-style-def>。
    private static func titleXML(_ c: Clip, spec: TitleSpec, indent: String) -> String {
        let dur = time(c.duration)
        let tsid = "ts_" + c.id.raw.replacingOccurrences(of: "-", with: "")
        // 生成器约定 start 走 3600s 基线(与真实 FCP 导出一致);offset/lane 决定它在时间线上的位置。
        var attrs = "ref=\"r_title\" name=\"\(esc(spec.text))\" duration=\"\(dur)\" start=\"3600s\""
        if c.lane != 0 { attrs += " lane=\"\(c.lane)\" offset=\"\(time(c.offset))\"" }
        let font = spec.fontName ?? "PingFang SC"
        let alignName = ["left", "center", "right"][min(max(spec.align, 0), 2)]
        var s = "\(indent)<title \(attrs)>\n"
        // DTD 子元素顺序:param*, text*, text-style-def*, note?, (…adjust-transform?…), … —— 先文本再 adjust-transform。
        s += "\(indent)  <text>\n"
        s += "\(indent)    <text-style ref=\"\(tsid)\">\(esc(spec.text))</text-style>\n"
        s += "\(indent)  </text>\n"
        s += "\(indent)  <text-style-def id=\"\(tsid)\">\n"
        var ts = "font=\"\(esc(font))\" fontSize=\"\(Int(spec.fontSize.rounded()))\" fontColor=\"\(rgba(spec.colorHex))\" bold=\"\(spec.bold ? 1 : 0)\" alignment=\"\(alignName)\""
        if spec.strokeWidth > 0 { ts += " strokeColor=\"\(rgba(spec.strokeColorHex))\" strokeWidth=\"\(Int(spec.strokeWidth.rounded()))\"" }
        s += "\(indent)    <text-style \(ts)/>\n"
        s += "\(indent)  </text-style-def>\n"
        // 位置:TitleSpec.position 相对画面中心、y 向下为正(渲染像素);FCP transform y 向上为正 → 翻 y。
        // 用 adjust-transform(模板无关)而非模板专属的「位置」param,才能配内置 Basic Title。
        // 必须排在 text/text-style-def 之后(DTD 要求),否则 FCP 报 "Element title content does not follow the DTD"。
        if spec.position.x != 0 || spec.position.y != 0 {
            s += "\(indent)  <adjust-transform position=\"\(fmt(Double(spec.position.x))) \(fmt(Double(-spec.position.y)))\"/>\n"
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
