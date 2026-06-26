import Foundation

/// 有理数时间(CMTime 语义)。时间线上所有位置/时长都用它,避免浮点累积误差。
struct Time: Equatable, Comparable, Hashable, Codable {
    var value: Int64
    var timescale: Int32

    init(value: Int64, timescale: Int32) {
        precondition(timescale > 0, "timescale 必须为正")
        self.value = value
        self.timescale = timescale
    }

    static let zero = Time(value: 0, timescale: 600)

    static func seconds(_ s: Double, timescale: Int32 = 600) -> Time {
        Time(value: Int64((s * Double(timescale)).rounded()), timescale: timescale)
    }

    var seconds: Double { Double(value) / Double(timescale) }

    private static func commonize(_ a: Time, _ b: Time) -> (Int64, Int64, Int32) {
        if a.timescale == b.timescale { return (a.value, b.value, a.timescale) }
        let ts = lcm(a.timescale, b.timescale)
        let av = a.value * Int64(ts / a.timescale)
        let bv = b.value * Int64(ts / b.timescale)
        return (av, bv, ts)
    }

    static func + (l: Time, r: Time) -> Time {
        let (a, b, ts) = commonize(l, r)
        return Time(value: a + b, timescale: ts)
    }

    static func - (l: Time, r: Time) -> Time {
        let (a, b, ts) = commonize(l, r)
        return Time(value: a - b, timescale: ts)
    }

    static func * (l: Time, ratio: Double) -> Time {
        Time(value: Int64((Double(l.value) * ratio).rounded()), timescale: l.timescale)
    }

    static func < (l: Time, r: Time) -> Bool {
        let (a, b, _) = commonize(l, r)
        return a < b
    }

    static func == (l: Time, r: Time) -> Bool {
        let (a, b, _) = commonize(l, r)
        return a == b
    }

    func hash(into hasher: inout Hasher) {
        // 规约到最简分数再 hash,保证与 ==(整数 commonize)一致,不用 Double
        let v = value < 0 ? -value : value
        let g = Self.gcd64(v, Int64(timescale))
        hasher.combine(value / g)
        hasher.combine(Int64(timescale) / g)
    }

    private static func gcd64(_ a: Int64, _ b: Int64) -> Int64 {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a == 0 ? 1 : a
    }

    func clamped(to range: ClosedRange<Time>) -> Time {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }

    var fcpxmlString: String {
        value == 0 ? "0s" : "\(value)/\(timescale)s"
    }
}

private func gcd(_ a: Int32, _ b: Int32) -> Int32 {
    var a = abs(a), b = abs(b)
    while b != 0 { (a, b) = (b, a % b) }
    return a == 0 ? 1 : a
}

private func lcm(_ a: Int32, _ b: Int32) -> Int32 {
    let result = Int64(a) / Int64(gcd(a, b)) * Int64(b)
    precondition(result <= Int64(Int32.max), "lcm overflow: \(a), \(b)")
    return Int32(result)
}
