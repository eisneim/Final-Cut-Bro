import SwiftUI

/// 分块流式文本 —— SwiftUI 没有 Virtual DOM,一个不断增长的 Text 每次都 O(N) 重排 → O(N²) 卡死。
/// 解法:把文本切成块,每块一个【独立 SwiftUI Text】。块边界由前缀确定(greedy),
/// 所以已产生的块内容【永不变化】→ SwiftUI 靠稳定 id 跳过它们的重排,只有【最后一个活跃块】
/// 在增长时重排(≤ chunkSize,O(1))。总重排成本 O(N) 而非 O(N²)。
///
/// 用 SwiftUI Text(不是 NSTextView):Text 自己正确上报高度,内容始终可见(不会因高度=0 被隐藏)。
struct ChunkedStreamingView: View {
    let text: String
    let streaming: Bool
    var chunkSize: Int = 140
    var font: Font = Tokens.Typeface.label
    var color: Color = Tokens.Palette.textPrimary

    var body: some View {
        let blocks = Self.computeBlocks(text, chunk: chunkSize)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                Text(idx == blocks.count - 1 && streaming ? block + " ▌" : block)
                    .font(font)
                    .foregroundStyle(color)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 贪心切块:块边界只依赖前缀 → 已产生的块内容稳定不变(SwiftUI 得以跳过)。
    /// 优先在换行处收块(保持文字流不被硬断);超长无换行行到 3×chunkSize 强制收。
    static func computeBlocks(_ s: String, chunk: Int) -> [String] {
        guard !s.isEmpty else { return [] }
        var blocks: [String] = []
        var cur = ""
        var curCount = 0
        for ch in s {
            cur.append(ch)
            curCount += 1
            if (curCount >= chunk && ch == "\n") || curCount >= chunk * 3 {
                blocks.append(cur); cur = ""; curCount = 0
            }
        }
        if !cur.isEmpty { blocks.append(cur) }
        return blocks
    }
}
