import AppKit
import CoreText
import CoreGraphics

/// 把 TitleSpec 渲染成【整帧透明背景的 CGImage】(尺寸=renderSize),文字按 position 偏移居中绘制。
/// 合成器把它当图片层叠在下层视频上。用 NSAttributedString 绘制(描边+字体+颜色)。
enum TitleRenderer {
    static func render(_ spec: TitleSpec, size: CGSize) -> CGImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let w = Int(size.width), h = Int(size.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        let color = NSColor(hex: spec.colorHex)
        let font = spec.bold
            ? NSFont.boldSystemFont(ofSize: CGFloat(spec.fontSize))
            : NSFont.systemFont(ofSize: CGFloat(spec.fontSize))
        let para = NSMutableParagraphStyle()
        para.alignment = [.left, .center, .right][max(0, min(2, spec.align))]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para,
            // 轻微描边/阴影增强可读性(深底浅字时仍清晰)。
            .strokeColor: NSColor.black.withAlphaComponent(0.6),
            .strokeWidth: -3.0,
        ]
        let str = NSAttributedString(string: spec.text, attributes: attrs)
        let textSize = str.size()
        // 居中 + position 偏移。注意 CGContext 原点在左下,position.y 向下为正 → 减。
        let cx = size.width / 2, cy = size.height / 2
        let originX = cx - textSize.width / 2 + spec.position.x
        let originY = cy - textSize.height / 2 - spec.position.y
        str.draw(in: CGRect(x: originX, y: originY, width: textSize.width + 4, height: textSize.height + 4))

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
