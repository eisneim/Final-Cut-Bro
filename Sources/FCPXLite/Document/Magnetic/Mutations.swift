import Foundation

/// 命令层:唯一的文档修改入口。手动 UI 与未来 Agent 工具都只调这里。
/// 每个命令是 Sequence → Sequence 纯函数,执行后断言三条不变量(fail fast)。
enum Mutations {

    static func insertClip(_ clip: Clip, at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        let i = max(0, min(index, s.spine.count))
        s.spine.insert(.clip(clip), at: i)
        assertInvariants(s)
        return s
    }

    /// ripple 删除(默认):移除元素,后续自动左移合拢。
    static func rippleDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        s.spine.remove(at: index)
        assertInvariants(s)
        return s
    }

    /// lift 删除:替换为等长 gap,保留空隙。
    static func liftDelete(at index: Int, in seq: Sequence) -> Sequence {
        var s = seq
        guard s.spine.indices.contains(index) else { return s }
        let d = s.spine[index].duration
        s.spine[index] = .gap(duration: d)
        assertInvariants(s)
        return s
    }

    private static func assertInvariants(_ seq: Sequence) {
        #if DEBUG
        do { try Invariants.check(seq) }
        catch { assertionFailure("磁性不变量被破坏: \(error)") }
        #endif
    }
}
