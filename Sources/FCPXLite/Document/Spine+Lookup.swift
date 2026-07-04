import Foundation

/// 按 id 查 clip / 素材的单一真源 —— 消除散落在 store/view/agent 各处的重复扫描循环。
extension Sequence {
    /// 按 id 取 clip(主轴直接元素或某宿主的连接子项)。所有 clip-by-id 查找都应走它。
    func clip(id: ClipID) -> Clip? {
        for el in spine {
            if case .clip(let c) = el {
                if c.id == id { return c }
                if let ch = c.connected.first(where: { $0.id == id }) { return ch }
            }
        }
        return nil
    }

    /// 按 id 取【主轴】clip 及其 spine 下标(连接子项返回 nil)。
    func spineClipAndIndex(id: ClipID) -> (clip: Clip, index: Int)? {
        for (i, el) in spine.enumerated() {
            if case .clip(let c) = el, c.id == id { return (c, i) }
        }
        return nil
    }
}

extension Document {
    /// 按 id 取素材。
    func asset(_ id: AssetID) -> Asset? { assetLibrary.first { $0.id == id } }

    /// 某 clip 的素材时长;素材缺失时回退到 clip 自身时长(单一真源,避免 7 处各写一遍兜底)。
    func assetDuration(of clip: Clip) -> Time {
        asset(clip.assetID)?.duration ?? clip.duration
    }
}
