import Foundation

enum InvariantViolation: Error, Equatable {
    case spineOverlap
    case laneCollision
    case negativeDuration
}

/// 三条磁性不变量校验。命令层每次 mutation 后调用(debug 断言;测试显式调用)。
enum Invariants {
    static func check(_ sequence: Sequence) throws {
        // 不变量 1/3:无负/零时长
        for el in sequence.spine {
            if el.duration.seconds <= 0 { throw InvariantViolation.negativeDuration }
            if case .clip(let c) = el {
                for conn in c.connected where conn.duration.seconds <= 0 {
                    throw InvariantViolation.negativeDuration
                }
            }
        }
        // 不变量 3:泳道隔离 —— 同 lane 的 connected 不得时间重叠
        let placed = Layout.compute(sequence).filter(\.isConnected)
        for i in placed.indices {
            for j in placed.indices where j > i {
                let a = placed[i], b = placed[j]
                guard a.lane == b.lane else { continue }
                let aEnd = a.absStart + a.duration
                let bEnd = b.absStart + b.duration
                let overlap = a.absStart < bEnd && b.absStart < aEnd
                if overlap { throw InvariantViolation.laneCollision }
            }
        }
        // 不变量 1(主轴连续)由 layout 前缀和结构保证,无需额外校验重叠。
    }
}
