import CoreGraphics

/// 素材池 FCPX 式 strip 视图的纯布局数学(无 view 依赖,可单测)。
/// 每个素材是一条"缩略图+波形"长条,宽 = 时长×外观缩放(px/秒),夹在 [minTile, 容器宽];
/// 多个素材按宽度【贪心流式换行】铺开(窗口不够宽就换行)。最小缩放 → 小方块 ≈ 网格。
enum AssetStripLayout {
    /// 单个素材条目标宽度:duration×px,夹在 [minTile, availWidth]。
    static func cellWidth(durationSecs: Double, pxPerSecond: Double,
                          minTile: CGFloat, availWidth: CGFloat) -> CGFloat {
        let w = CGFloat(max(0, durationSecs) * max(0, pxPerSecond))
        let hi = max(minTile, availWidth)              // 容器极窄时仍允许到 minTile
        return max(minTile, min(hi, w))
    }

    /// 贪心流式换行:返回每行包含的 item 下标。spacing = item 间距。
    static func flow(itemWidths: [CGFloat], availWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var cur: [Int] = []
        var x: CGFloat = 0
        for (i, w) in itemWidths.enumerated() {
            let need = (cur.isEmpty ? 0 : spacing) + w
            if !cur.isEmpty, x + need > availWidth {
                rows.append(cur)
                cur = [i]; x = w
            } else {
                cur.append(i); x += need
            }
        }
        if !cur.isEmpty { rows.append(cur) }
        return rows
    }
}
