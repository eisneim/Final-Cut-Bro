// Sources/FCPXLite/Export/ExportSettings.swift
import Foundation

enum ExportCodec: String, CaseIterable {
    case h264, h265, prores
    var label: String {
        switch self {
        case .h264:   return "H.264"
        case .h265:   return "H.265 (HEVC)"
        case .prores: return "ProRes 422"
        }
    }
}

enum ExportQuality: String, CaseIterable {
    case low, medium, high
    var label: String {
        switch self {
        case .low:    return "低(小文件)"
        case .medium: return "中(平衡)"
        case .high:   return "高(大文件)"
        }
    }
}

enum ExportResolution: String, CaseIterable {
    case r720, r1080, r2160, original
    var label: String {
        switch self {
        case .r720:     return "720p"
        case .r1080:    return "1080p"
        case .r2160:    return "4K"
        case .original: return "原始"
        }
    }
    /// Returns target render size; `.original` returns nil (caller uses document format).
    /// 注:此属性是【旧的固定横屏尺寸】,会把竖屏项目拉成横屏 —— 已弃用,导出改用
    /// renderSize(projectWidth:projectHeight:)(保持项目宽高比)。保留仅为兼容旧调用。
    var size: CGSize? {
        switch self {
        case .r720:     return CGSize(width: 1280, height: 720)
        case .r1080:    return CGSize(width: 1920, height: 1080)
        case .r2160:    return CGSize(width: 3840, height: 2160)
        case .original: return nil
        }
    }

    /// 目标渲染尺寸,【始终保持项目宽高比,绝不拉伸】。
    /// 分辨率数字 = 目标【短边】(720p 竖屏 = 720 宽,720p 横屏 = 720 高)。
    /// .original 用项目原始尺寸。结果取偶数(H.264/H.265 编码器要求宽高为偶)。
    func renderSize(projectWidth: Int, projectHeight: Int) -> CGSize {
        let w = Double(max(1, projectWidth)), h = Double(max(1, projectHeight))
        func even(_ v: Double) -> Double { let n = Int(v.rounded()); return Double(n - (n % 2)) }
        let target: Double
        switch self {
        case .original: return CGSize(width: even(w), height: even(h))
        case .r720:  target = 720
        case .r1080: target = 1080
        case .r2160: target = 2160
        }
        let scale = target / min(w, h)   // 短边缩放到目标,长边按比例
        return CGSize(width: even(w * scale), height: even(h * scale))
    }
}

struct ExportSettings {
    var codec: ExportCodec      = .h264
    var quality: ExportQuality  = .medium
    var resolution: ExportResolution = .r1080
    var includeAudio: Bool      = true
}
