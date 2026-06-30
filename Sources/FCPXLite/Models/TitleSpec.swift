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

    enum CodingKeys: String, CodingKey {
        case text, fontSize, colorHex, bold, positionX, positionY, align
    }
    init() {}
    init(text: String, fontSize: Double = 96, colorHex: String = "#FFFFFF",
         bold: Bool = true, position: CGPoint = .zero, align: Int = 1) {
        self.text = text; self.fontSize = fontSize; self.colorHex = colorHex
        self.bold = bold; self.position = position; self.align = align
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
    }
}
