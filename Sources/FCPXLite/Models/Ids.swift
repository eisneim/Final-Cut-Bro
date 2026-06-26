import Foundation

struct AssetID: Hashable, Codable {
    let raw: String
    init() { raw = UUID().uuidString }
    init(raw: String) { self.raw = raw }
}

struct ClipID: Hashable, Codable {
    let raw: String
    init() { raw = UUID().uuidString }
    init(raw: String) { self.raw = raw }
}
