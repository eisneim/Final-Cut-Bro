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
    var size: CGSize? {
        switch self {
        case .r720:     return CGSize(width: 1280, height: 720)
        case .r1080:    return CGSize(width: 1920, height: 1080)
        case .r2160:    return CGSize(width: 3840, height: 2160)
        case .original: return nil
        }
    }
}

struct ExportSettings {
    var codec: ExportCodec      = .h264
    var quality: ExportQuality  = .medium
    var resolution: ExportResolution = .r1080
    var includeAudio: Bool      = true
}
