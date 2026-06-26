import Foundation

enum InvariantViolation: Error, Equatable {
    case laneCollision
    case negativeDuration
}

/// 三条磁性不变量校验。命令层每次 mutation 后调用(debug 断言;测试显式调用)。
/// 不变量 1(主轴无重叠)由 prefix-sum 结构保证(后一元素起点 = 前一元素终点),
/// 因此 spineOverlap 不可能发生,该枚举 case 已移除。
enum Invariants {
    static func check(_ sequence: Sequence) throws {
        // 不变量 1/3:无负/零时长
        for el in sequence.spine {
            if el.duration <= .zero { throw InvariantViolation.negativeDuration }
            if case .clip(let c) = el {
                for conn in c.connected where conn.duration <= .zero {
                    throw InvariantViolation.negativeDuration
                }
            }
        }
        // 不变量 3:泳道隔离 —— 同 lane 的 connected 不得时间重叠
        // 前提:connected clip 按文档约定 lane != 0(spine clip lane 恒为 0),故这里只在同 lane 间判重叠
        let placed = Layout.compute(sequence).filter(\.isConnected)
        for p in placed where p.lane == 0 {
            throw InvariantViolation.laneCollision   // connected clip 不得占用 lane 0(主轴保留)
        }
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
