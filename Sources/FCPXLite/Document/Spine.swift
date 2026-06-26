import Foundation

/// 主时间线:有序元素数组,首尾相接,磁性隐含在顺序里。
struct Sequence: Codable, Equatable {
    var spine: [Element]
}

struct Project: Codable, Equatable {
    var formatWidth: Int
    var formatHeight: Int
    var frameRate: Double
    var assetLibrary: [Asset]
    var sequence: Sequence
}

typealias Document = Project
