import Foundation
import CoreGraphics

/// 标题(Title)规格:挂在 clip 上(clip.title 非 nil = 标题片段,不引用真实媒体)。
/// 渲染时由 TitleRenderer 把文字画成透明背景的整帧图,合成器当作图片层叠在下层视频上。
struct TitleSpec: Codable, Equatable {
    var text: String = "标题"
    var fontSize: Double = 96
    var colorHex: String = "#FFFFFF"
    var bold: Bool = true
    var position: CGPoint = .zero    // 相对画面中心的偏移(渲染坐标,y 向下为正)
    var align: Int = 1               // 0 左 1 中 2 右
    var fontName: String? = nil      // nil = 系统字体;否则按字体族名(NSFont(name:))
    // 描边(border):宽度 0 = 无描边。默认黑色细描边(深底浅字仍清晰,口播常用)。
    var strokeWidth: Double = 3
    var strokeColorHex: String = "#000000"
    // 阴影(shadow):默认关。开启后按 半径/偏移/颜色 投影。
    var shadowEnabled: Bool = false
    var shadowColorHex: String = "#000000"
    var shadowRadius: Double = 4
    var shadowDX: Double = 0
    var shadowDY: Double = 2          // 向下为正

    enum CodingKeys: String, CodingKey {
        case text, fontSize, colorHex, bold, positionX, positionY, align
        case fontName, strokeWidth, strokeColorHex
        case shadowEnabled, shadowColorHex, shadowRadius, shadowDX, shadowDY
    }
    init() {}
    init(text: String, fontSize: Double = 96, colorHex: String = "#FFFFFF",
         bold: Bool = true, position: CGPoint = .zero, align: Int = 1,
         fontName: String? = nil, strokeWidth: Double = 3, strokeColorHex: String = "#000000",
         shadowEnabled: Bool = false, shadowColorHex: String = "#000000",
         shadowRadius: Double = 4, shadowDX: Double = 0, shadowDY: Double = 2) {
        self.text = text; self.fontSize = fontSize; self.colorHex = colorHex
        self.bold = bold; self.position = position; self.align = align
        self.fontName = fontName; self.strokeWidth = strokeWidth; self.strokeColorHex = strokeColorHex
        self.shadowEnabled = shadowEnabled; self.shadowColorHex = shadowColorHex
        self.shadowRadius = shadowRadius; self.shadowDX = shadowDX; self.shadowDY = shadowDY
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? true
        position = CGPoint(x: try c.decodeIfPresent(Double.self, forKey: .positionX) ?? 0,
                           y: try c.decodeIfPresent(Double.self, forKey: .positionY) ?? 0)
        align = try c.decodeIfPresent(Int.self, forKey: .align) ?? 1
        // 新增样式字段:旧 JSON 缺 → 用默认(保持既有观感)。
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 3
        strokeColorHex = try c.decodeIfPresent(String.self, forKey: .strokeColorHex) ?? "#000000"
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? false
        shadowColorHex = try c.decodeIfPresent(String.self, forKey: .shadowColorHex) ?? "#000000"
        shadowRadius = try c.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? 4
        shadowDX = try c.decodeIfPresent(Double.self, forKey: .shadowDX) ?? 0
        shadowDY = try c.decodeIfPresent(Double.self, forKey: .shadowDY) ?? 2
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(bold, forKey: .bold)
        try c.encode(position.x, forKey: .positionX)
        try c.encode(position.y, forKey: .positionY)
        try c.encode(align, forKey: .align)
        try c.encodeIfPresent(fontName, forKey: .fontName)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokeColorHex, forKey: .strokeColorHex)
        try c.encode(shadowEnabled, forKey: .shadowEnabled)
        try c.encode(shadowColorHex, forKey: .shadowColorHex)
        try c.encode(shadowRadius, forKey: .shadowRadius)
        try c.encode(shadowDX, forKey: .shadowDX)
        try c.encode(shadowDY, forKey: .shadowDY)
    }
}
