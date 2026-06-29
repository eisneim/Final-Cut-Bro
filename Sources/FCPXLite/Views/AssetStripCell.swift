import SwiftUI

/// 素材池里一个素材的 FCPX 式 strip:上=缩略图胶片条(按真实宽高比平铺),下=音频波形。
/// 用 Canvas 绘制(复用 TimelineMediaCache 的缩略图/波形),异步生成完成经通知刷新。
struct AssetStripCell: View {
    let asset: Asset
    let width: CGFloat
    let height: CGFloat
    let selected: Bool
    var vaRatio: CGFloat = 0.62
    @State private var refresh = 0

    var body: some View {
        Canvas { ctx, size in
            _ = refresh           // 触发依赖:缓存就绪通知 → refresh+1 → 重绘
            draw(ctx, size)
        }
        .frame(width: width, height: height)
        .background(Color(TimelineColors.canvas))
        .overlay(alignment: .topLeading) {
            Text(asset.url.lastPathComponent)
                .font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.white)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(Color.black.opacity(0.4))
                .padding(2)
                .frame(maxWidth: width, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selected ? Color(TimelineColors.selectBorder) : Color(TimelineColors.clipBlueEdge),
                    lineWidth: selected ? 2 : 1))
        .onReceive(NotificationCenter.default.publisher(for: .mediaCacheUpdated)) { _ in refresh &+= 1 }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let isAudioOnly = asset.kind == .audio
        let filmH = isAudioOnly ? 0 : (asset.hasAudio ? size.height * vaRatio : size.height)
        let waveH = size.height - filmH

        // --- 缩略图胶片条 ---
        if filmH > 1, let thumbs = TimelineMediaCache.shared.thumbnails(for: asset), !thumbs.isEmpty {
            let ar = asset.naturalSize.height > 0 ? asset.naturalSize.width / asset.naturalSize.height : 16.0 / 9.0
            let tileW = max(8, filmH * CGFloat(ar))
            let n = max(1, Int(ceil(size.width / tileW)))
            for i in 0..<n {
                let frac = (Double(i) + 0.5) / Double(n)
                let img = thumbs[min(thumbs.count - 1, max(0, Int(frac * Double(thumbs.count))))]
                let rect = CGRect(x: CGFloat(i) * tileW, y: 0, width: tileW + 1, height: filmH)
                ctx.draw(Image(decorative: img, scale: 1), in: rect)
            }
        } else if filmH > 1 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: filmH)),
                     with: .color(Color(TimelineColors.elevated)))
        }

        // --- 音频波形(实心包络) ---
        if waveH > 1, asset.hasAudio {
            ctx.fill(Path(CGRect(x: 0, y: filmH, width: size.width, height: waveH)),
                     with: .color(Color(TimelineColors.elevated).opacity(0.5)))
            if let peaks = TimelineMediaCache.shared.waveform(for: asset), !peaks.isEmpty {
                let mid = filmH + waveH / 2
                let cols = max(1, Int(size.width))
                var top: [CGPoint] = []
                var bot: [CGPoint] = []
                for c in 0...cols {
                    let f0 = Double(c) / Double(cols)
                    let a = Int(f0 * Double(peaks.count))
                    let b = min(peaks.count, max(a + 1, Int((Double(c + 1) / Double(cols)) * Double(peaks.count))))
                    var pk: Float = 0
                    var i = min(peaks.count - 1, a)
                    while i < b { if peaks[i] > pk { pk = peaks[i] }; i += 1 }
                    let h = CGFloat(min(1, pk)) * (waveH / 2) * 0.95
                    let x = CGFloat(c)
                    top.append(CGPoint(x: x, y: mid - h))
                    bot.append(CGPoint(x: x, y: mid + h))
                }
                var path = Path()
                path.move(to: top.first ?? CGPoint(x: 0, y: mid))
                for p in top { path.addLine(to: p) }
                for p in bot.reversed() { path.addLine(to: p) }
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(TimelineColors.waveform)))
            }
        }
    }
}
