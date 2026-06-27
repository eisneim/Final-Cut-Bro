import Foundation

enum EditTool: String, Codable, CaseIterable {
    case select, trim, position, range, blade, zoom, hand

    var label: String {
        switch self {
        case .select:   return "选择"
        case .trim:     return "修剪"
        case .position: return "位置"
        case .range:    return "范围选择"
        case .blade:    return "切割"
        case .zoom:     return "缩放"
        case .hand:     return "手"
        }
    }

    var shortcut: String {
        switch self {
        case .select:   return "A"
        case .trim:     return "T"
        case .position: return "P"
        case .range:    return "R"
        case .blade:    return "B"
        case .zoom:     return "Z"
        case .hand:     return "H"
        }
    }
}
