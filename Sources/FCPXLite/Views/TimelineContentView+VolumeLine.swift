import AppKit

/// 音频音量 level 线绘制:水平线映射 volume→y,关键帧圆点,首尾 fade 三角手柄。
/// 只在 hasAudio 的 clip 上绘制,分视频+音频(waveRect)和纯音频(整 rect)两区域。
extension TimelineContentView {

    // MARK: - 音量区域辅助

    /// 返回 clip 的音频波形区域(与 drawWaveform 使用的区域一致)。
    func audioRegion(for clip: Clip, in rect: NSRect) -> NSRect? {
        guard let asset = assetLibrary.first(where: { $0.id == clip.assetID }),
              asset.hasAudio else { return nil }
        if asset.kind == .audio {
            return rect
        } else {
            let videoH = rect.height * vaRatio
            return NSRect(x: rect.minX, y: rect.minY + videoH,
                         width: rect.width, height: rect.height - videoH)
        }
    }

    // MARK: - 座标转换辅助(供 draw 与 drag 共用)

    /// volume(0–2) → y 在 region 内(volume=0→bottom, volume=2→top)。
    func volumeToY(volume: Double, in region: NSRect) -> CGFloat {
        let clamped = max(0, min(2, volume))
        // isFlipped=true: minY=top, maxY=bottom
        return region.maxY - CGFloat(clamped / 2.0) * region.height
    }

    /// y → volume(0–2),限定在 region 内。
    func yToVolume(y: CGFloat, in region: NSRect) -> Double {
        let frac = Double((region.maxY - y) / region.height)
        return max(0, min(2, frac * 2.0))
    }

    /// 关键帧的画布 x(相对 clip 起点 time → clip rect x 范围内)。
    func kfX(time: Time, clipDuration: Time, in rect: NSRect) -> CGFloat {
        guard clipDuration.seconds > 0 else { return rect.minX }
        let frac = CGFloat(time.seconds / clipDuration.seconds)
        return rect.minX + frac * rect.width
    }

    // MARK: - 绘制入口

    /// 在单个 clip 上绘制音量 level 线、关键帧圆点、首尾 fade 手柄。
    /// 在 drawClip 的 restoreGraphicsState 之后调用。
    func drawVolumeLine(clip: Clip, in rect: NSRect) {
        guard let region = audioRegion(for: clip, in: rect) else { return }
        guard region.height > 4 else { return }

        let lineColor = NSColor.white.withAlphaComponent(0.7)
        let dotColor  = NSColor.white.withAlphaComponent(0.9)
        let handleColor = NSColor(red: 1.0, green: 0.75, blue: 0.2, alpha: 0.85) // 黄橙色

        let sorted = clip.volumeKeyframes.sorted { $0.time < $1.time }

        // --- 1. Level 线 ---
        let linePath = NSBezierPath()
        linePath.lineWidth = 1.5

        if sorted.isEmpty {
            // 无关键帧:平线
            let y = volumeToY(volume: clip.adjust.volume, in: region)
            linePath.move(to: NSPoint(x: region.minX, y: y))
            linePath.line(to: NSPoint(x: region.maxX, y: y))
        } else {
            // 有关键帧:折线
            // 首关键帧之前:水平延伸
            let firstY = volumeToY(volume: sorted[0].value, in: region)
            let firstX = kfX(time: sorted[0].time, clipDuration: clip.duration, in: rect)
            linePath.move(to: NSPoint(x: region.minX, y: firstY))
            linePath.line(to: NSPoint(x: firstX, y: firstY))
            // 关键帧之间
            for kf in sorted {
                let x = kfX(time: kf.time, clipDuration: clip.duration, in: rect)
                let y = volumeToY(volume: kf.value, in: region)
                linePath.line(to: NSPoint(x: x, y: y))
            }
            // 末关键帧之后:水平延伸
            let lastKF = sorted[sorted.count - 1]
            let lastX = kfX(time: lastKF.time, clipDuration: clip.duration, in: rect)
            let lastY = volumeToY(volume: lastKF.value, in: region)
            linePath.move(to: NSPoint(x: lastX, y: lastY))
            linePath.line(to: NSPoint(x: region.maxX, y: lastY))
        }
        lineColor.setStroke()
        linePath.stroke()

        // --- 2. 关键帧圆点 ---
        let dotR: CGFloat = 4
        for kf in sorted {
            let x = kfX(time: kf.time, clipDuration: clip.duration, in: rect)
            let y = volumeToY(volume: kf.value, in: region)
            let dotRect = NSRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)
            let dot = NSBezierPath(ovalIn: dotRect)
            dotColor.setFill()
            dot.fill()
        }

        // --- 3. Fade 手柄(左:淡入三角,右:淡出三角) ---
        let triSize: CGFloat = 8
        let fadeIn  = clip.effects.first { $0.enabled && $0.kind == .fade }?.params["inSeconds"]  ?? 0
        let fadeOut = clip.effects.first { $0.enabled && $0.kind == .fade }?.params["outSeconds"] ?? 0
        let vol0 = sorted.isEmpty ? clip.adjust.volume : sorted[0].value
        let volN = sorted.isEmpty ? clip.adjust.volume : sorted[sorted.count - 1].value

        // 左手柄:在 region 左边缘,y = 淡入起点(volume=0)到终点(vol0)的中点 y
        let leftLineY = volumeToY(volume: vol0, in: region)
        drawFadeHandle(at: NSPoint(x: region.minX + 2, y: leftLineY),
                       size: triSize, pointing: .right,
                       active: fadeIn > 0, color: handleColor)

        // 右手柄:在 region 右边缘
        let rightLineY = volumeToY(volume: volN, in: region)
        drawFadeHandle(at: NSPoint(x: region.maxX - 2, y: rightLineY),
                       size: triSize, pointing: .left,
                       active: fadeOut > 0, color: handleColor)
    }

    private enum HandleDirection { case left, right }

    private func drawFadeHandle(at center: NSPoint, size: CGFloat,
                                 pointing dir: HandleDirection, active: Bool, color: NSColor) {
        let tri = NSBezierPath()
        let h = size, w = size * 0.7
        switch dir {
        case .right:
            // 向右尖三角
            tri.move(to: NSPoint(x: center.x,     y: center.y - h/2))
            tri.line(to: NSPoint(x: center.x,     y: center.y + h/2))
            tri.line(to: NSPoint(x: center.x + w, y: center.y))
        case .left:
            // 向左尖三角
            tri.move(to: NSPoint(x: center.x,     y: center.y - h/2))
            tri.line(to: NSPoint(x: center.x,     y: center.y + h/2))
            tri.line(to: NSPoint(x: center.x - w, y: center.y))
        }
        tri.close()
        (active ? color : color.withAlphaComponent(0.4)).setFill()
        tri.fill()
        color.withAlphaComponent(0.6).setStroke()
        tri.lineWidth = 1
        tri.stroke()
    }
}
