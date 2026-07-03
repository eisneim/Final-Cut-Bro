import AppKit

/// 时间轴工具的自定义鼠标光标。macOS 没有内置的放大镜/剃刀/范围光标,
/// 这里用 NSImage 画出来(SF Symbol 或手绘路径),统一带黑色描边 → 在深色时间轴上也看得清。
enum TimelineCursors {
    /// 缩放:放大镜(SF Symbol)。
    static let zoom: NSCursor = symbolCursor("magnifyingglass", hot: { NSPoint(x: $0.width * 0.42, y: $0.height * 0.42) })
    /// 位置:四向移动箭头(SF Symbol)。
    static let move: NSCursor = symbolCursor("arrow.up.and.down.and.arrow.left.and.right", hot: { NSPoint(x: $0.width / 2, y: $0.height / 2) })
    /// 切割:剃刀(手绘)。热点在刀刃切点(底部中央)。
    static let blade: NSCursor = bladeCursor()
    /// 范围选择:[|](手绘)。热点在中央竖线。
    static let range: NSCursor = rangeCursor()

    // MARK: - SF Symbol → 描边光标

    private static func symbolCursor(_ name: String, hot: (NSSize) -> NSPoint) -> NSCursor {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return .arrow }
        let pad: CGFloat = 3
        let size = NSSize(width: ceil(glyph.size.width) + pad * 2, height: ceil(glyph.size.height) + pad * 2)
        let img = NSImage(size: size)
        img.lockFocus()
        let rect = NSRect(x: pad, y: pad, width: glyph.size.width, height: glyph.size.height)
        // 黑色描边:把字形在 8 个偏移位置画成黑色。
        let black = tinted(glyph, .black)
        for dx in [-1.0, 0, 1.0] {
            for dy in [-1.0, 0, 1.0] where !(dx == 0 && dy == 0) {
                black.draw(in: rect.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy)))
            }
        }
        tinted(glyph, .white).draw(in: rect)   // 白色主体压在描边之上
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: hot(size))
    }

    /// 把模板 SF Symbol 上色成指定颜色。
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let out = NSImage(size: image.size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    // MARK: - 手绘:描边路径(黑粗 + 白细)

    /// 画一条带描边的路径:先黑色粗线,再白色细线压上 → 白光标带黑边,任意背景都清晰。
    private static func strokeOutlined(_ build: () -> NSBezierPath) {
        let outline = build(); outline.lineCapStyle = .round; outline.lineJoinStyle = .round
        NSColor.black.setStroke(); outline.lineWidth = 3.5; outline.stroke()
        let core = build(); core.lineCapStyle = .round; core.lineJoinStyle = .round
        NSColor.white.setStroke(); core.lineWidth = 1.6; core.stroke()
    }

    /// 范围选择光标 [|]:左右方括号 + 中央竖线。热点在中央。
    private static func rangeCursor() -> NSCursor {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size)
        img.lockFocus()
        let top: CGFloat = 4, bot: CGFloat = 16, tick: CGFloat = 3
        strokeOutlined {
            let p = NSBezierPath()
            // 左括号 [
            p.move(to: NSPoint(x: 3 + tick, y: top)); p.line(to: NSPoint(x: 3, y: top))
            p.line(to: NSPoint(x: 3, y: bot)); p.line(to: NSPoint(x: 3 + tick, y: bot))
            // 右括号 ]
            p.move(to: NSPoint(x: 17 - tick, y: top)); p.line(to: NSPoint(x: 17, y: top))
            p.line(to: NSPoint(x: 17, y: bot)); p.line(to: NSPoint(x: 17 - tick, y: bot))
            // 中央竖线 |
            p.move(to: NSPoint(x: 10, y: top)); p.line(to: NSPoint(x: 10, y: bot))
            return p
        }
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: NSPoint(x: 10, y: 10))
    }

    /// 切割光标:剃刀 —— 上部平行四边形刀身 + 向下收窄到底部切点。热点在底部切点。
    private static func bladeCursor() -> NSCursor {
        let size = NSSize(width: 20, height: 22)
        let img = NSImage(size: size)
        img.lockFocus()
        // 刀身(平行四边形,白填充黑描边)
        let blade = NSBezierPath()
        blade.move(to: NSPoint(x: 6, y: 21)); blade.line(to: NSPoint(x: 15, y: 21))
        blade.line(to: NSPoint(x: 12, y: 9)); blade.line(to: NSPoint(x: 9, y: 9))
        blade.close()
        NSColor.black.setStroke(); NSColor.white.setFill()
        blade.lineWidth = 1.6; blade.fill(); blade.stroke()
        // 切割竖线:从刀身底收窄到底部切点(热点)
        strokeOutlined {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 10.5, y: 9)); p.line(to: NSPoint(x: 10.5, y: 1))
            return p
        }
        img.unlockFocus()
        // 热点:底部切点(NSCursor 热点为左上原点坐标系 → y 取图像高度附近)
        return NSCursor(image: img, hotSpot: NSPoint(x: 10, y: 21))
    }
}
