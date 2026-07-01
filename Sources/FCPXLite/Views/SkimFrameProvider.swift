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
    private var lastAssetKey: String?
    private let q = DispatchQueue(label: "fcpxlite.skim", qos: .userInteractive)

    func request(asset: Asset, seconds: Double) {
        let key = asset.id.raw
        let assetChanged = key != lastAssetKey
        lastAssetKey = key
        // 低清缩略图回退【只在首次(空白)或切换到别的素材时】用 —— 否则每次移动都把画面重置成
        // 160×90 缩略图,高清帧还没到又被下次覆盖 → 全程看着像马赛克。同素材内 skim 保留上一张高清帧。
        if (image == nil || assetChanged),
           let thumbs = TimelineMediaCache.shared.thumbnails(for: asset), !thumbs.isEmpty {
            let dur = max(0.001, asset.duration.seconds)
            let idx = min(thumbs.count - 1, max(0, Int(seconds / dur * Double(thumbs.count))))
            image = thumbs[idx]
        }
        guard asset.kind != .audio else { image = nil; return }

        reqToken &+= 1
        let token = reqToken
        let gen: AVAssetImageGenerator = {
            if let g = generators[key] { return g }
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
            g.appliesPreferredTrackTransform = true
            // 1280 边界盒:横屏≈1280×720、竖屏≈720×1280 → 近原生清晰度(旧值 960×540 对竖屏只有 304×540,糊)。
            g.maximumSize = CGSize(width: 1280, height: 1280)
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

    func clear() { image = nil; reqToken &+= 1; lastAssetKey = nil }
}
