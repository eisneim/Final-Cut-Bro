import Foundation

/// 主轴元素:clip 或显式空隙(gap)。gap 带 id,可像 clip 一样被选中/拖动/修剪。
enum Element: Codable, Equatable {
    case clip(Clip)
    case gap(id: GapID, duration: Time)

    var duration: Time {
        switch self {
        case .clip(let c): return c.duration
        case .gap(_, let d): return d
        }
    }

    var asClip: Clip? {
        if case .clip(let c) = self { return c }
        return nil
    }

    var gapID: GapID? {
        if case .gap(let id, _) = self { return id }
        return nil
    }

    /// 便捷构造:自动分配 id。
    static func gap(duration: Time) -> Element { .gap(id: GapID(), duration: duration) }
}
