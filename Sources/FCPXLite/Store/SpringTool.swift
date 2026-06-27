import Foundation

/// 弹簧工具状态机(纯值类型,可测试):按住工具快捷键 = 临时切换,松开还原;
/// 短按(tap)= 永久切换。FCP 行为。
struct SpringTool {
    /// 当前临时持有:切换到的工具 / 之前的工具 / 按下时间。
    private(set) var held: (tool: EditTool, previous: EditTool, downTime: TimeInterval)?

    /// 按下工具键:返回应切到的工具(若已持有或是自动重复则返回 nil 不动作)。
    mutating func keyDown(tool: EditTool, current: EditTool, time: TimeInterval, isRepeat: Bool) -> EditTool? {
        if isRepeat || held != nil { return nil }
        held = (tool, current, time)
        return tool
    }

    /// 松开:返回应还原到的工具(长按→还原 previous;短按→nil 保持)。
    mutating func keyUp(time: TimeInterval, holdThreshold: TimeInterval = 0.25) -> EditTool? {
        guard let h = held else { return nil }
        held = nil
        return (time - h.downTime) > holdThreshold ? h.previous : nil
    }

    /// 当前临时持有的工具的快捷键(用于匹配 keyUp 的键)。
    var heldShortcut: String? { held?.tool.shortcut.lowercased() }
}
