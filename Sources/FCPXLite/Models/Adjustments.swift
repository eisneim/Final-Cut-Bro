import Foundation

struct Transform: Codable, Equatable {
    var position = CGPoint(x: 0, y: 0)
    var scale = CGSize(width: 1, height: 1)
    var rotation = 0.0
    var anchor = CGPoint(x: 0, y: 0)

    enum CodingKeys: String, CodingKey {
        case positionX, positionY, scaleWidth, scaleHeight, rotation, anchorX, anchorY
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let posX = try container.decode(Double.self, forKey: .positionX)
        let posY = try container.decode(Double.self, forKey: .positionY)
        position = CGPoint(x: posX, y: posY)
        let scaleW = try container.decode(Double.self, forKey: .scaleWidth)
        let scaleH = try container.decode(Double.self, forKey: .scaleHeight)
        scale = CGSize(width: scaleW, height: scaleH)
        rotation = try container.decode(Double.self, forKey: .rotation)
        let anchorX = try container.decode(Double.self, forKey: .anchorX)
        let anchorY = try container.decode(Double.self, forKey: .anchorY)
        anchor = CGPoint(x: anchorX, y: anchorY)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
        try container.encode(scale.width, forKey: .scaleWidth)
        try container.encode(scale.height, forKey: .scaleHeight)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(anchor.x, forKey: .anchorX)
        try container.encode(anchor.y, forKey: .anchorY)
    }

    static func == (lhs: Transform, rhs: Transform) -> Bool {
        lhs.position.x == rhs.position.x &&
        lhs.position.y == rhs.position.y &&
        lhs.scale.width == rhs.scale.width &&
        lhs.scale.height == rhs.scale.height &&
        lhs.rotation == rhs.rotation &&
        lhs.anchor.x == rhs.anchor.x &&
        lhs.anchor.y == rhs.anchor.y
    }
}

struct Crop: Codable, Equatable {
    var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0
}

/// Inspector 可调参数,挂在 clip 上。对齐 FCPXML <adjust-*>。
struct Adjustments: Codable, Equatable {
    var transform = Transform()
    var crop = Crop()
    var opacity = 1.0   // → <adjust-blend> / video opacity
    var volume = 1.0    // → <adjust-volume>
}
