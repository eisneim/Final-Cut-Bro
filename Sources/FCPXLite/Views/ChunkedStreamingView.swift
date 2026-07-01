import SwiftUI
import AppKit

/// 分块流式文本渲染——SwiftUI 没有 Virtual DOM,每次文本增长都触发整个 view tree 重算。
/// 解法:把增长的文本切成固定大小的块(默认 300 字),每块用独立 NSTextView 渲染,
/// 渲染一次就冻结(previous chunks never touched),只更新最后一块 → O(chunk_size) per flush。
///
/// 相当于在 SwiftUI 里手动做 React 的 Virtual DOM diffing:只重渲染变化的叶子节点。
struct ChunkedStreamingView: View {
    let text: String
    let streaming: Bool
    var chunkSize: Int = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 已冻结的块:每块只渲染一次,text 变长时这些块的 id 不变 → SwiftUI 跳过。
            ForEach(frozenChunks, id: \.self) { chunk in
                ChunkTextView(text: chunk)
            }
            // 活跃块(最后一块):每次 flush 只更新这一个 → O(chunk_size),不是 O(total)。
            if !activeChunk.isEmpty {
                ChunkTextView(text: activeChunk + (streaming ? " ▌" : ""))
            }
        }
        .background(Tokens.Palette.elevated)
        .cornerRadius(8)
    }

    /// 已完成的块(每块 chunkSize 字),渲染后冻结。
    private var frozenChunks: [String] {
        let count = text.count / chunkSize
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let start = text.index(text.startIndex, offsetBy: i * chunkSize)
            let end = text.index(text.startIndex, offsetBy: min((i + 1) * chunkSize, text.count))
            return String(text[start..<end])
        }
    }

    /// 当前活跃块(不满一块的尾部),每次 flush 只更新这个。
    private var activeChunk: String {
        let frozenCount = (text.count / chunkSize) * chunkSize
        guard frozenCount < text.count else { return "" }
        let start = text.index(text.startIndex, offsetBy: frozenCount)
        return String(text[start...])
    }
}

/// 单个文本块:用 AppKit NSTextView 渲染(比 SwiftUI Text 高效,尤其对 CJK 文字)。
/// 一旦渲染完就不会再更新(冻结块),所以即使块内文本较长也无所谓——只画一次。
private struct ChunkTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSTextView {
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textColor = .white
        tv.font = NSFont.systemFont(ofSize: NSFont.labelFontSize)
        tv.textContainerInset = NSSize(width: 8, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.string = text
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        // 冻结块:text 不变 → 跳过;活跃块:text 变了 → 只更新这一个。
        guard tv.string != text else { return }
        tv.string = text
    }
}
