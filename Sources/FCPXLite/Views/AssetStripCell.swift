import SwiftUI

/// 素材池里一个素材的 FCPX 式 strip:上=缩略图胶片条(按真实宽高比平铺),下=音频波形。
/// 支持【多行】:当素材条比池子宽时,整条按时间切成 rows 行,行与行【紧贴】(同一素材的换行看起来是一组)。
/// 用 Canvas 绘制(复用 TimelineMediaCache 的缩略图/波形),异步生成完成经通知刷新。
struct AssetStripCell: View {
    let asset: Asset
    let width: CGFloat        // 每行宽度
    let bandH: CGFloat        // 单行高度
    let rows: Int             // 行数(=1 普通;>1 长素材换行)
    let selected: Bool
    var vaRatio: CGFloat = 0.62
    /// Skim:鼠标在条上移动 → 回调该位置对应的素材秒数(nil=移出,停止 skim)。
    var onSkim: (Double?) -> Void = { _ in }
    @State private var refresh = 0
    /// skim 位置:鼠标局部坐标(nil = 未 hover)。红条只画在光标所在那一行(一个 bandH 高)。
    @State private var skimPoint: CGPoint? = nil

    private var totalHeight: CGFloat { bandH * CGFloat(max(1, rows)) }

    /// 鼠标局部坐标 → 素材秒数(支持多行:每行覆盖一段时间)。
    private func skimSeconds(at p: CGPoint) -> Double {
        let n = max(1, rows)
        let row = min(n - 1, max(0, Int(p.y / bandH)))
        let fx = width > 0 ? max(0, min(1, p.x / width)) : 0
        let frac = (Double(row) + Double(fx)) / Double(n)
        return frac * asset.duration.seconds
    }

    var body: some View {
        Canvas { ctx, size in
            _ = refresh           // 触发依赖:缓存就绪通知 → refresh+1 → 重绘
            let n = max(1, rows)
            for r in 0..<n {
                let f0 = Double(r) / Double(n)
                let f1 = Double(r + 1) / Double(n)
                let rect = CGRect(x: 0, y: CGFloat(r) * bandH, width: size.width, height: bandH)
                drawBand(ctx, in: rect, t0: f0, t1: f1)
            }
            // skim 位置指示:红色竖线,【只画在光标所在那一行】(一个 bandH 高,不再贯穿多行/两层)。
            if let p = skimPoint {
                let row = min(n - 1, max(0, Int(p.y / bandH)))
                let x = max(0, min(size.width, p.x))
                let y0 = CGFloat(row) * bandH
                var bar = Path()
                bar.move(to: CGPoint(x: x, y: y0))
                bar.addLine(to: CGPoint(x: x, y: y0 + bandH))
                ctx.stroke(bar, with: .color(.red.opacity(0.85)), lineWidth: 1.5)
            }
        }
        .frame(width: width, height: totalHeight)
        .background(Color(TimelineColors.canvas))
        .overlay(alignment: .topLeading) {
            Text(asset.url.lastPathComponent)
                .font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.white)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(Color.black.opacity(0.45))
                .padding(2)
                .frame(maxWidth: width, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selected ? Color(TimelineColors.selectBorder) : Color(TimelineColors.clipBlueEdge),
                    lineWidth: selected ? 2 : 1))
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                skimPoint = p
                onSkim(skimSeconds(at: p))   // 移动 → skim 到该帧
            case .ended:
                skimPoint = nil
                onSkim(nil)                  // 移出 → 停止
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaCacheUpdated)) { _ in refresh &+= 1 }
    }

    /// 画一个时间子区间 [t0,t1] 的带:上缩略图、下波形,落在 rect 内。
    private func drawBand(_ ctx: GraphicsContext, in rect: CGRect, t0: Double, t1: Double) {
        let isAudioOnly = asset.kind == .audio
        let filmH = isAudioOnly ? 0 : (asset.hasAudio ? rect.height * vaRatio : rect.height)
        let waveH = rect.height - filmH
        let span = max(1e-6, t1 - t0)

        // --- 缩略图胶片条(只取 [t0,t1] 对应那段帧) ---
        let filmRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: filmH)
        if filmH > 1, let thumbs = TimelineMediaCache.shared.thumbnails(for: asset), !thumbs.isEmpty {
            let ar = asset.naturalSize.height > 0 ? asset.naturalSize.width / asset.naturalSize.height : 16.0 / 9.0
            let tileW = max(8, filmH * CGFloat(ar))
            let n = max(1, Int(ceil(rect.width / tileW)))
            for i in 0..<n {
                let frac = t0 + span * (Double(i) + 0.5) / Double(n)
                let img = thumbs[min(thumbs.count - 1, max(0, Int(frac * Double(thumbs.count))))]
                let tr = CGRect(x: rect.minX + CGFloat(i) * tileW, y: rect.minY, width: tileW + 1, height: filmH)
                ctx.draw(Image(decorative: img, scale: 1), in: tr)
            }
        } else if filmH > 1 {
            ctx.fill(Path(filmRect), with: .color(Color(TimelineColors.elevated)))
        }

        // --- 音频波形(实心包络,只取 [t0,t1]) ---
        if waveH > 1, asset.hasAudio {
            let waveRect = CGRect(x: rect.minX, y: rect.minY + filmH, width: rect.width, height: waveH)
            ctx.fill(Path(waveRect), with: .color(Color(TimelineColors.elevated).opacity(0.5)))
            if let peaks = TimelineMediaCache.shared.waveform(for: asset), !peaks.isEmpty {
                let mid = waveRect.midY
                let cols = max(1, Int(rect.width))
                var top: [CGPoint] = []
                var bot: [CGPoint] = []
                for c in 0...cols {
                    let lf = t0 + span * Double(c) / Double(cols)
                    let rf = t0 + span * Double(c + 1) / Double(cols)
                    let a = Int(lf * Double(peaks.count))
                    let b = min(peaks.count, max(a + 1, Int(rf * Double(peaks.count))))
                    var pk: Float = 0
                    var i = min(peaks.count - 1, max(0, a))
                    while i < b { if peaks[i] > pk { pk = peaks[i] }; i += 1 }
                    let h = CGFloat(min(1, pk)) * (waveH / 2) * 0.95
                    let x = rect.minX + CGFloat(c)
                    top.append(CGPoint(x: x, y: mid - h))
                    bot.append(CGPoint(x: x, y: mid + h))
                }
                var path = Path()
                path.move(to: top.first ?? CGPoint(x: rect.minX, y: mid))
                for p in top { path.addLine(to: p) }
                for p in bot.reversed() { path.addLine(to: p) }
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(TimelineColors.waveform)))
            }
        }
    }
}
