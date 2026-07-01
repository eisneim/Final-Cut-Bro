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
        PerfProbe.shared.measure("Layout.compute") { computeImpl(sequence) }
    }

    private static func computeImpl(_ sequence: Sequence) -> [Placed] {
        var out: [Placed] = []
        var t = Time.zero
        var prevWasClip = false
        for element in sequence.spine {
            if case .clip(let c) = element {
                // 交叉叠化:本片段头部与【前一主轴片段】尾部重叠 crossfadeIn → 起点前移,
                // 与 CompositionBuilder 的渲染保持一致(否则可见位置 ≠ 渲染位置,播放头/转场都对不上)。
                let start: Time
                if c.crossfadeIn > .zero, prevWasClip, c.transformKeyframes.isEmpty {
                    start = t - c.crossfadeIn
                } else {
                    start = t
                }
                out.append(Placed(clipID: c.id, absStart: start, duration: c.duration,
                                  lane: 0, isConnected: false))
                for conn in c.connected {
                    out.append(Placed(clipID: conn.id, absStart: start + conn.offset,
                                      duration: conn.duration, lane: conn.lane,
                                      isConnected: true))
                }
                t = start + c.duration
                prevWasClip = true
            } else {
                t = t + element.duration
                prevWasClip = false
            }
        }
        return out.sorted {
            if $0.absStart != $1.absStart { return $0.absStart < $1.absStart }
            return $0.lane < $1.lane
        }
    }
}
