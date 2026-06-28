// Sources/FCPXLite/Engine/Composition/VideoEffectFilters.swift
import CoreImage

/// 把 clip 的视频特效链应用到 CIImage(按列表顺序;只处理 isVideo 且 enabled)。
enum VideoEffectFilters {
    static func apply(_ effects: [Effect], to image: CIImage) -> CIImage {
        var img = image
        for e in effects where e.enabled && e.kind.isVideo {
            switch e.kind {
            case .color:
                let f = CIFilter(name: "CIColorControls")!
                f.setValue(img, forKey: kCIInputImageKey)
                f.setValue(e.params["brightness"] ?? 0, forKey: kCIInputBrightnessKey)
                f.setValue(e.params["contrast"] ?? 1, forKey: kCIInputContrastKey)
                f.setValue(e.params["saturation"] ?? 1, forKey: kCIInputSaturationKey)
                img = f.outputImage ?? img
            case .blur:
                let r = e.params["radius"] ?? 0
                if r > 0 {
                    let f = CIFilter(name: "CIGaussianBlur")!
                    f.setValue(img, forKey: kCIInputImageKey)
                    f.setValue(r, forKey: kCIInputRadiusKey)
                    img = f.outputImage ?? img
                }
            case .fade:
                break   // 音频特效,视频链不处理
            }
        }
        return img
    }
}
