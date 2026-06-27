import AVFoundation
import AppKit

/// 时间线媒体缓存:异步生成 clip 的缩略图序列(filmstrip)与音频波形峰值,按 assetID 缓存。
/// 生成完成后调用 onUpdate 触发画布重绘。AppKit 画布在 draw 时请求,未就绪先返回 nil 并后台生成。
final class TimelineMediaCache {
    static let shared = TimelineMediaCache()

    /// 任一资源生成完成后回调(由画布设为 needsDisplay)。
    var onUpdate: (() -> Void)?

    private var thumbs: [String: [CGImage]] = [:]
    private var thumbsLoading: Set<String> = []
    private var waves: [String: [Float]] = [:]
    private var wavesLoading: Set<String> = []
    private let q = DispatchQueue(label: "fcpxlite.mediacache", qos: .utility)

    // MARK: - 缩略图序列(每资源固定生成 N 张不同帧,绘制时按需采样)

    static let thumbCount = 24

    func thumbnails(for asset: Asset) -> [CGImage]? {
        let key = asset.id.raw
        if let t = thumbs[key] { return t }
        guard asset.kind != .audio, !thumbsLoading.contains(key) else { return nil }
        thumbsLoading.insert(key)
        q.async { [weak self] in
            let imgs = Self.genThumbs(asset, count: Self.thumbCount)
            DispatchQueue.main.async {
                self?.thumbs[key] = imgs
                self?.thumbsLoading.remove(key)
                self?.onUpdate?()
            }
        }
        return nil
    }

    private static func genThumbs(_ asset: Asset, count: Int) -> [CGImage] {
        if asset.kind == .image {
            if let img = NSImage(contentsOf: asset.url),
               let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return Array(repeating: cg, count: count)
            }
            return []
        }
        let av = AVURLAsset(url: asset.url)
        let gen = AVAssetImageGenerator(asset: av)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 90)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        let dur = CMTimeGetSeconds(av.duration)
        var out: [CGImage] = []
        for i in 0..<count {
            let frac = count == 1 ? 0.0 : Double(i) / Double(count - 1)
            let t = CMTime(seconds: dur * frac, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: t, actualTime: nil) { out.append(cg) }
        }
        return out
    }

    // MARK: - 音频波形峰值(每资源固定 N 桶,按 presentation time 分桶;绘制时重采样)

    static let waveBuckets = 2000

    func waveform(for asset: Asset) -> [Float]? {
        let key = asset.id.raw
        if let w = waves[key] { return w }
        guard asset.hasAudio, !wavesLoading.contains(key) else { return nil }
        wavesLoading.insert(key)
        q.async { [weak self] in
            let peaks = Self.genWaveform(asset, buckets: Self.waveBuckets)
            DispatchQueue.main.async {
                self?.waves[key] = peaks
                self?.wavesLoading.remove(key)
                self?.onUpdate?()
            }
        }
        return nil
    }

    private static func genWaveform(_ asset: Asset, buckets: Int) -> [Float] {
        let av = AVURLAsset(url: asset.url)
        guard let track = av.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: av) else { return [] }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        reader.startReading()

        let totalDur = CMTimeGetSeconds(av.duration)
        guard totalDur > 0 else { return [] }
        var peaks = [Float](repeating: 0, count: buckets)
        while reader.status == .reading, let sb = output.copyNextSampleBuffer() {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            var bufPeak: Float = 0
            if let bb = CMSampleBufferGetDataBuffer(sb) {
                var length = 0
                var dataPtr: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                            totalLengthOut: &length, dataPointerOut: &dataPtr)
                if let dp = dataPtr {
                    let n = length / 2
                    dp.withMemoryRebound(to: Int16.self, capacity: n) { p in
                        var i = 0
                        while i < n { let v = abs(Float(p[i])) / Float(Int16.max); if v > bufPeak { bufPeak = v }; i += 16 }
                    }
                }
            }
            if pts.isFinite {
                let b = min(buckets - 1, max(0, Int(pts / totalDur * Double(buckets))))
                if bufPeak > peaks[b] { peaks[b] = bufPeak }
            }
            CMSampleBufferInvalidate(sb)
        }
        return peaks
    }
}
