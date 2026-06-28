import Foundation

/// 特效种类。color/blur 是视频滤镜(Core Image);fade 是音频淡入淡出(AVAudioMix 斜坡)。
enum EffectKind: String, Codable, CaseIterable {
    case color   // CIColorControls: brightness/contrast/saturation
    case blur    // CIGaussianBlur: radius
    case fade    // 音频淡入淡出: inSeconds/outSeconds

    var isVideo: Bool { self != .fade }

    var defaultParams: [String: Double] {
        switch self {
        case .color: return ["brightness": 0, "contrast": 1, "saturation": 1]
        case .blur:  return ["radius": 0]
        case .fade:  return ["inSeconds": 0, "outSeconds": 0]
        }
    }
}

/// 可堆叠特效。挂在 clip 上,列表顺序 = 视频滤镜链应用顺序。params 扁平键值。
struct Effect: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: EffectKind
    var enabled: Bool
    var params: [String: Double]

    static func make(_ kind: EffectKind) -> Effect {
        Effect(id: UUID(), kind: kind, enabled: true, params: kind.defaultParams)
    }
}
