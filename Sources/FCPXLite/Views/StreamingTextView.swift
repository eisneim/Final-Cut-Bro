import SwiftUI
import AppKit

/// 流式 assistant 气泡:用 AppKit NSTextView 替代 SwiftUI Text。
/// 关键:只做【追加】(append delta),不替换全文 → O(1) per flush → 几千字也不卡。
/// SwiftUI Text + setAttributedString 每次都是 O(N) → O(N²) 总量 → 后期 100% CPU。
struct StreamingTextView: NSViewRepresentable {
    let text: String
    let streaming: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

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
        let co = context.coordinator
        let display = streaming ? text + " ▌" : text

        // 首次或非流式:全量设置
        if co.displayedCount == 0 || !streaming {
            let str = NSAttributedString(string: display, attributes: Self.attrs)
            tv.textStorage?.setAttributedString(str)
            co.displayedCount = display.count
            tv.scrollToEndOfDocument(nil)
            return
        }

        // 流式追加:只 append 新增字符 → O(1) 不触碰已有文本的 layout。
        let oldCount = co.displayedCount
        let newCount = display.count
        guard newCount > oldCount else { return }
        let oldEnd = display.index(display.startIndex, offsetBy: oldCount)
        let delta = String(display[oldEnd...])
        let attrDelta = NSAttributedString(string: delta, attributes: Self.attrs)
        tv.textStorage?.append(attrDelta)
        co.displayedCount = newCount
        tv.scrollToEndOfDocument(nil)
    }

    final class Coordinator {
        var displayedCount = 0
    }

    private static let attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.white,
        .font: NSFont.systemFont(ofSize: NSFont.labelFontSize),
    ]
}
