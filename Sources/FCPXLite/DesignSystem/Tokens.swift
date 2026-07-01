import SwiftUI

/// 设计令牌 —— 全部源自 design/style.md 截图实采。视图只引用这里,严禁裸 hex。
enum Tokens {
    enum Palette {
        static let titlebar      = Color(hex: "#3B3B3B")
        static let chrome        = Color(hex: "#212121")
        static let canvas        = Color(hex: "#1A1A1A")
        static let effectsPanel  = Color(hex: "#1F1F1F")
        static let chatPanel     = Color(hex: "#1E1E1E")
        static let elevated      = Color(hex: "#2C2C2C")

        static let textPrimary   = Color(hex: "#EAEAEA")
        static let textCool      = Color(hex: "#DCE2FF")
        static let textIcon      = Color(hex: "#EEEEEE")
        static let textMuted     = Color(hex: "#696969")

        static let clipBlue      = Color(hex: "#243553")
        static let clipBlueEdge  = Color(hex: "#3E5E96")
        static let selectYellow  = Color(hex: "#FFD754")
        static let selectClipBorder = Color(hex: "#FFDB86")
        static let waveform      = Color(hex: "#8C9CBD")
        static let playhead      = Color.white
        static let onAccent      = Color.white   // 彩色气泡/clip 上的文字

        static let windowClose    = Color(hex: "#FF5F57")
        static let windowMinimize = Color(hex: "#FEBC2E")
        static let windowZoom     = Color(hex: "#28C840")
        static let divider        = Color(hex: "#000000")
    }

    enum Metric {
        static let titlebarHeight: CGFloat = 30
        static let toolbarHeight: CGFloat = 26
        static let topBarHeight: CGFloat = 46   // 顶部主工具条(面板切换组 + 导出),比原 26 高
        static let timelineToolbarHeight: CGFloat = 24
        static let librariesWidth: CGFloat = 200
        static let browserWidth: CGFloat = 280
        static let inspectorWidth: CGFloat = 320
        static let chatWidth: CGFloat = 320
        static let effectsWidth: CGFloat = 360
        static let dividerWidth: CGFloat = 1
    }

    enum Typeface {
        static let label = Font.system(size: 11)
        static let body = Font.system(size: 12)
        static let timecode = Font.system(size: 13).monospaced()
        static let title = Font.system(size: 13, weight: .medium)
    }
}
