import AVFoundation
import AppKit
import Combine

/// Skim 帧提供:给定素材+秒数,异步生成该帧(AVAssetImageGenerator,按素材缓存 generator),
/// 先用 TimelineMediaCache 的缩略图做即时回退,真实帧出来再替换。只保留最新请求(防抖)。
/// 完全独立于时间线 AVPlayer —— 只产出一张图,viewer 覆盖层显示,不碰播放器。
@MainActor
final class SkimFrameProvider: ObservableObject {
    @Published var image: CGImage?

    private var generators: [String: AVAssetImageGenerator] = [:]
    private var reqToken = 0
    private let q = DispatchQueue(label: "fcpxlite.skim", qos: .userInteractive)

    func request(asset: Asset, seconds: Double) {
        // 即时回退:最近的缓存缩略图(24 张),保证移动时不空白。
        if let thumbs = TimelineMediaCache.shared.thumbnails(for: asset), !thumbs.isEmpty {
            let dur = max(0.001, asset.duration.seconds)
            let idx = min(thumbs.count - 1, max(0, Int(seconds / dur * Double(thumbs.count))))
            image = thumbs[idx]
        }
        guard asset.kind != .audio else { image = nil; return }

        reqToken &+= 1
        let token = reqToken
        let key = asset.id.raw
        let gen: AVAssetImageGenerator = {
            if let g = generators[key] { return g }
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: 960, height: 540)
            g.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            g.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            generators[key] = g
            return g
        }()
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        q.async { [weak self] in
            let cg = try? gen.copyCGImage(at: t, actualTime: nil)
            DispatchQueue.main.async {
                guard let self, token == self.reqToken, let cg else { return }   // 只接受最新请求
                self.image = cg
            }
        }
    }

    func clear() { image = nil; reqToken &+= 1 }
}
