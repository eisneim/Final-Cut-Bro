import AppKit

/// 时间轴定向失效的矩形数学 —— 供 apply() 决定"只重画哪一小块",避免整块 92ms 全画。
extension TimelineContentView {

    /// 选择锚点 + 多选集合 → 统一的 clipID 集合。
    func selectionClipIDUnion(_ anchor: ClipID?, _ set: Set<ClipID>) -> Set<ClipID> {
        var ids = set
        if let a = anchor { ids.insert(a) }
        return ids
    }

    /// 播放头从 oldX 移到 newX 的脏区:一条全高竖条,x 方向 ±5 覆盖顶部三角手柄。
    func playheadDirtyRect(oldX: CGFloat, newX: CGFloat) -> NSRect {
        let lo = min(oldX, newX) - 5
        let hi = max(oldX, newX) + 5
        return NSRect(x: lo, y: 0, width: hi - lo, height: bounds.height)
    }

    /// 一组 clip 的选中脏区:各自 clipRect 外扩 3pt(含选中边框)后并集;空集返回 nil。
    func selectionDirtyRect(_ ids: Set<ClipID>) -> NSRect? {
        guard !ids.isEmpty else { return nil }
        var out: NSRect? = nil
        for p in placed where ids.contains(p.clipID) {
            out = unionRect(out, clipRect(p).insetBy(dx: -3, dy: -3))
        }
        return out
    }

    /// 可空并集:nil ∪ r = r。
    func unionRect(_ a: NSRect?, _ b: NSRect?) -> NSRect? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return x.union(y)
        }
    }
}
