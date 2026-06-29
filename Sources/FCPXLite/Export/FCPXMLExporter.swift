// Sources/FCPXLite/Export/FCPXMLExporter.swift
import Foundation

/// Document → FCPXML 字符串(纯字符串拼装,无语义转换)。概念与 FCPXML 一一对应。
/// 验收线:结构合法可解析 + 基础剪辑信息正确;自定义 effect 不强求真 FCP 还原。
enum FCPXMLExporter {
    static func export(_ document: Document) -> String {
        let fr = document.frameRate > 0 ? document.frameRate : 25
        let frameDur = "1/\(Int(fr.rounded()))s"
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        s += "<!DOCTYPE fcpxml>\n<fcpxml version=\"1.10\">\n"

        // resources:每个 asset 一个 <asset>,共用一个 <format>
        s += "  <resources>\n"
        s += "    <format id=\"r0\" name=\"FFVideoFormat\" frameDuration=\"\(frameDur)\" width=\"\(document.formatWidth)\" height=\"\(document.formatHeight)\"/>\n"
        for (i, a) in document.assetLibrary.enumerated() {
            let dur = time(a.duration)
            let hasV = a.kind != .audio ? "1" : "0"
            let hasA = a.hasAudio ? "1" : "0"
            s += "    <asset id=\"a\(i)\" name=\"\(esc(a.url.lastPathComponent))\" duration=\"\(dur)\" hasVideo=\"\(hasV)\" hasAudio=\"\(hasA)\" format=\"r0\">\n"
            s += "      <media-rep kind=\"original-media\" src=\"\(esc(a.url.absoluteString))\"/>\n"
            s += "    </asset>\n"
        }
        s += "  </resources>\n"

        // library → event → project → sequence → spine
        s += "  <library>\n    <event name=\"FCPX-lite\">\n      <project name=\"FCPX-lite Project\">\n"
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

    /// 单个 clip → <asset-clip>,递归嵌入连接子项(带 lane/offset)。
    private static func clipXML(_ c: Clip, document: Document, indent: String) -> String {
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
