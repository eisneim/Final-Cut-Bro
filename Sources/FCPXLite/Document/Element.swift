import Foundation

/// 主轴元素:clip 或显式空隙(gap)。
enum Element: Codable, Equatable {
    case clip(Clip)
    case gap(duration: Time)

    var duration: Time {
        switch self {
        case .clip(let c): return c.duration
        case .gap(let d): return d
        }
    }

    var asClip: Clip? {
        if case .clip(let c) = self { return c }
        return nil
    }
}
