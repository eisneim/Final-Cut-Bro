import SwiftUI
import AppKit

/// 流式 assistant 气泡:用 AppKit NSTextView 替代 SwiftUI Text。
/// SwiftUI Text 每次重设全文 → 重算全部文字排版 → 文本越长越卡(O(N²) 总量)。
/// NSTextView 底层是 NSTextStorage → 只做增量 layout → 几乎 O(1) append,几千字也流畅。
struct StreamingTextView: NSViewRepresentable {
    let text: String
    let streaming: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textColor = .white
        tv.font = NSFont.systemFont(ofSize: NSFont.labelFontSize)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = tv
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        let display = streaming ? text + " ▌" : text
        // 仅当内容实际变化才替换(避免无意义 layout)
        guard tv.string != display else { return }
        let str = NSAttributedString(string: display, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: NSFont.labelFontSize),
        ])
        tv.textStorage?.setAttributedString(str)
        tv.scrollToEndOfDocument(nil)
    }
}
