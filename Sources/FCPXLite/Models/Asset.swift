import Foundation

enum MediaKind: String, Codable { case video, audio, image }

/// 素材库条目:只引用源文件,不拷贝/不转码。
struct Asset: Identifiable, Codable, Equatable {
    let id: AssetID
    var url: URL
    var kind: MediaKind
    var duration: Time
    var naturalSize: CGSize
    var frameRate: Double?
    var hasAudio: Bool

    enum CodingKeys: String, CodingKey {
        case id, url, kind, duration, naturalSizeWidth, naturalSizeHeight, frameRate, hasAudio
    }

    init(id: AssetID, url: URL, kind: MediaKind, duration: Time, naturalSize: CGSize, frameRate: Double?, hasAudio: Bool) {
        self.id = id
        self.url = url
        self.kind = kind
        self.duration = duration
        self.naturalSize = naturalSize
        self.frameRate = frameRate
        self.hasAudio = hasAudio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AssetID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        kind = try container.decode(MediaKind.self, forKey: .kind)
        duration = try container.decode(Time.self, forKey: .duration)
        let width = try container.decode(Double.self, forKey: .naturalSizeWidth)
        let height = try container.decode(Double.self, forKey: .naturalSizeHeight)
        naturalSize = CGSize(width: width, height: height)
        frameRate = try container.decodeIfPresent(Double.self, forKey: .frameRate)
        hasAudio = try container.decode(Bool.self, forKey: .hasAudio)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(kind, forKey: .kind)
        try container.encode(duration, forKey: .duration)
        try container.encode(naturalSize.width, forKey: .naturalSizeWidth)
        try container.encode(naturalSize.height, forKey: .naturalSizeHeight)
        try container.encodeIfPresent(frameRate, forKey: .frameRate)
        try container.encode(hasAudio, forKey: .hasAudio)
    }

    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id &&
        lhs.url == rhs.url &&
        lhs.kind == rhs.kind &&
        lhs.duration == rhs.duration &&
        lhs.naturalSize.width == rhs.naturalSize.width &&
        lhs.naturalSize.height == rhs.naturalSize.height &&
        lhs.frameRate == rhs.frameRate &&
        lhs.hasAudio == rhs.hasAudio
    }
}

