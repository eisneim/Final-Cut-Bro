import Foundation

/// 轻量性能探针:按 name 聚合调用次数/总耗时/最大耗时,可 dump 报告并 reset。
/// 用途:在关键热点(Layout.compute / updateNSView / dispatch / token 处理)埋点,
/// 跑真实操作路径后 dump 一张表,数据驱动定位瓶颈(不猜)。
///
/// 开销:enabled=false 时 measure 只是一次 bool 判断 + 直接执行闭包(非逃逸,无分配),
/// 生产路径几乎零成本;需要测量时由测试/调试服务器打开。
final class PerfProbe {
    static let shared = PerfProbe()

    struct Stat {
        var count = 0
        var totalMS = 0.0
        var maxMS = 0.0
        var avgMS: Double { count == 0 ? 0 : totalMS / Double(count) }
    }

    /// 关闭时 measure 零记录开销。默认关闭 —— 只有测量场景显式打开。
    var enabled = false
    private var stats: [String: Stat] = [:]
    private let lock = NSLock()

    private init() {}

    /// 包裹一段同步代码计时(毫秒)。enabled=false 直接执行,不记录。
    @inline(__always)
    func measure<T>(_ name: String, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let r = body()
        let dtMS = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000.0
        record(name, dtMS)
        return r
    }

    /// 直接记录一次已测得的耗时(用于无法包裹闭包的异步/跨回调场景)。
    func record(_ name: String, _ ms: Double) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        var s = stats[name] ?? Stat()
        s.count += 1
        s.totalMS += ms
        s.maxMS = max(s.maxMS, ms)
        stats[name] = s
    }

    /// 仅计数(热点被调用几次),不计时 —— 用于统计"一次重画触发多少次 Layout.compute"这类倍数。
    func count(_ name: String) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        var s = stats[name] ?? Stat()
        s.count += 1
        stats[name] = s
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        stats.removeAll()
    }

    func snapshot() -> [String: Stat] {
        lock.lock(); defer { lock.unlock() }
        return stats
    }

    /// 按总耗时降序输出一张对齐表格。
    func report() -> String {
        let snap = snapshot()
        guard !snap.isEmpty else { return "(PerfProbe 无数据 —— 是否 enabled?)" }
        let rows = snap.sorted { $0.value.totalMS > $1.value.totalMS }
        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        func padL(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
        }
        var out = pad("name", 30) + padL("count", 8) + padL("total(ms)", 12)
                + padL("avg(ms)", 11) + padL("max(ms)", 11) + "\n"
        out += String(repeating: "-", count: 72) + "\n"
        for (name, s) in rows {
            out += pad(name, 30)
                + padL("\(s.count)", 8)
                + padL(String(format: "%.2f", s.totalMS), 12)
                + padL(String(format: "%.3f", s.avgMS), 11)
                + padL(String(format: "%.3f", s.maxMS), 11) + "\n"
        }
        return out
    }
}
