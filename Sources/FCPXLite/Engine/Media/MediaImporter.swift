import AVFoundation
import AppKit
import Foundation

enum MediaImportError: Error, CustomStringConvertible {
    case unsupportedExtension(String)
    case unreadableFile(URL)
    case metadataLoadFailed(URL, Error)

    var description: String {
        switch self {
        case .unsupportedExtension(let ext):
            return "不支持的文件格式: .\(ext) — 支持: \(MediaImporter.allowedExtensions.sorted().joined(separator: ", "))"
        case .unreadableFile(let url):
            return "无法读取文件: \(url.lastPathComponent)"
        case .metadataLoadFailed(let url, let err):
            return "读取元数据失败: \(url.lastPathComponent) — \(err)"
        }
    }
}

enum MediaImporter {

    /// 支持的扩展名白名单(AVFoundation 原生 + 图片)
    static let allowedExtensions: Set<String> = [
        "mov", "mp4", "m4v",
        "wav", "mp3", "m4a", "aac",
        "png", "jpg", "jpeg", "heic"
    ]

    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    private static let audioExtensions: Set<String> = ["wav", "mp3", "m4a", "aac"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    /// 从文件 URL 读取元数据生成 Asset。
    /// fail fast: 不支持的扩展名 / 读取失败 → 抛错(不静默)。
    static func importAsset(from url: URL) throws -> Asset {
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw MediaImportError.unsupportedExtension(ext)
        }

        if videoExtensions.contains(ext) || audioExtensions.contains(ext) {
            return try importAVAsset(from: url, ext: ext)
        } else {
            return try importImageAsset(from: url)
        }
    }

    // MARK: - Private helpers

    private static func importAVAsset(from url: URL, ext: String) throws -> Asset {
        let avAsset = AVURLAsset(url: url)
        let kind: MediaKind = videoExtensions.contains(ext) ? .video : .audio

        // Load duration synchronously using deprecated but reliable API (synchronous, Swift 5.9 compatible)
        let cmDuration = avAsset.duration
        guard cmDuration.isValid, !cmDuration.isIndefinite else {
            throw MediaImportError.unreadableFile(url)
        }
        let duration = Time(value: Int64(cmDuration.value), timescale: cmDuration.timescale)

        var naturalSize = CGSize.zero
        var frameRate: Double? = nil
        let hasAudio = !avAsset.tracks(withMediaType: .audio).isEmpty

        if kind == .video {
            if let videoTrack = avAsset.tracks(withMediaType: .video).first {
                naturalSize = videoTrack.naturalSize
                frameRate = Double(videoTrack.nominalFrameRate)
            }
        }

        return Asset(
            id: AssetID(),
            url: url,
            kind: kind,
            duration: duration,
            naturalSize: naturalSize,
            frameRate: frameRate,
            hasAudio: hasAudio
        )
    }

    private static func importImageAsset(from url: URL) throws -> Asset {
        guard let image = NSImage(contentsOf: url) else {
            throw MediaImportError.unreadableFile(url)
        }
        let size = image.size
        return Asset(
            id: AssetID(),
            url: url,
            kind: .image,
            duration: Time.seconds(5),
            naturalSize: size,
            frameRate: nil,
            hasAudio: false
        )
    }

    /// 生成缩略图(视频抽首帧 / 图片本身 / 音频返回 nil)。
    /// best-effort: 失败返回 nil 不抛。
    static func thumbnail(for asset: Asset) -> NSImage? {
        switch asset.kind {
        case .video:
            return videoThumbnail(from: asset.url)
        case .image:
            return NSImage(contentsOf: asset.url)
        case .audio:
            return nil
        }
    }

    private static func videoThumbnail(from url: URL) -> NSImage? {
        do {
            let avAsset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: avAsset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: .zero)
        } catch {
            return nil
        }
    }
}
