import AppKit

/// AppKit 画布专用颜色。SwiftUI 视图必须用 Tokens.Palette;但 AppKit 自定义绘制只能用 NSColor,
/// 无法直接复用 SwiftUI 的 Color。因此这里集中映射 Tokens 里用到的 hex 到 NSColor,
/// 保持与 DesignSystem/Tokens.swift 单一来源一致(改 Tokens 时务必同步这里)。
///
/// 镜像关系(hex 必须与 Tokens.Palette 完全一致):
///   canvas         ← Tokens.Palette.canvas        #1A1A1A
///   chrome         ← Tokens.Palette.chrome        #212121
///   elevated       ← Tokens.Palette.elevated      #2C2C2C
///   clipBlue       ← Tokens.Palette.clipBlue      #243553
///   clipBlueEdge   ← Tokens.Palette.clipBlueEdge  #3E5E96
///   selectBorder   ← Tokens.Palette.selectClipBorder #FFDB86
///   textPrimary    ← Tokens.Palette.textPrimary   #EAEAEA
///   textMuted      ← Tokens.Palette.textMuted     #696969
///   divider        ← Tokens.Palette.divider       #000000
/// 额外:playheadRed 是播放头专用红(#FF3B30,系统红),Tokens 里未定义 Color 版本,
/// 仅 AppKit 画布需要,故只在此声明。
enum TimelineColors {
    static let canvas       = NSColor(hex: "#1A1A1A")
    /// 主轴(lane 0)行底色:比 canvas 略深,让主时间线读起来稍暗。仅 AppKit 画布用。
    static let mainLaneBg   = NSColor(hex: "#141414")
    static let chrome       = NSColor(hex: "#212121")
    static let elevated     = NSColor(hex: "#2C2C2C")
    static let clipBlue     = NSColor(hex: "#243553")
    static let clipBlueEdge = NSColor(hex: "#3E5E96")
    static let selectBorder = NSColor(hex: "#FFDB86")
    static let textPrimary  = NSColor(hex: "#EAEAEA")
    static let textMuted    = NSColor(hex: "#696969")
    static let divider      = NSColor(hex: "#000000")
    static let playheadRed   = NSColor(hex: "#FF3B30")
    /// 位置工具留下的灰色占位间隙(gap):比 clip 灰、可见但不抢眼。
    static let gapFill       = NSColor(hex: "#3A3A3A")
    static let gapBorder     = NSColor(hex: "#555555")
    static let waveform      = NSColor(hex: "#8C9CBD")
}

extension NSColor {
    /// 与 Color(hex:) 同语义的 NSColor 便利构造,sRGB,不透明。fail-fast:格式错误在 DEBUG 断言。
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        let ok = Scanner(string: s).scanHexInt64(&v)
        #if DEBUG
        assert(ok && s.count == 6, "malformed hex: \(hex)")
        #endif
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
