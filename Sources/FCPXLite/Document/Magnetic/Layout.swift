import Foundation

/// 算出来的绝对位置(不存储在文档里)。供画布绘制与合成引擎使用。
struct Placed: Equatable {
    let clipID: ClipID
    let absStart: Time
    let duration: Time
    let lane: Int
    let isConnected: Bool
}

/// 纯函数布局:Sequence → [Placed]。磁性的"绝对位置"在这里实时算。
enum Layout {
    static func compute(_ sequence: Sequence) -> [Placed] {
        var out: [Placed] = []
        var t = Time.zero
        for element in sequence.spine {
            if case .clip(let c) = element {
                out.append(Placed(clipID: c.id, absStart: t, duration: c.duration,
                                  lane: 0, isConnected: false))
                for conn in c.connected {
                    out.append(Placed(clipID: conn.id, absStart: t + conn.offset,
                                      duration: conn.duration, lane: conn.lane,
                                      isConnected: true))
                }
            }
            t = t + element.duration
        }
        return out.sorted {
            if $0.absStart != $1.absStart { return $0.absStart < $1.absStart }
            return $0.lane < $1.lane
        }
    }
}
