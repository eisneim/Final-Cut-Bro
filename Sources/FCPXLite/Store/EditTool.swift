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

    var icon: String {
        switch self {
        case .select:   return "cursorarrow"
        case .trim:     return "arrow.left.and.right.square"
        case .position: return "arrow.up.and.down.and.arrow.left.and.right"
        case .range:    return "selection.pin.in.out"
        case .blade:    return "scissors"
        case .zoom:     return "magnifyingglass"
        case .hand:     return "hand.raised"
        }
    }
}
