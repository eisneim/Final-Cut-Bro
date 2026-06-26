import Foundation

/// 对照实验数据导出:把布局结果摊成可比对的位置表 / CSV。
struct PlacementRow: Equatable {
    let clipID: String
    let absStartSeconds: Double
    let durationSeconds: Double
    let lane: Int
}

enum ExperimentReport {
    static func placementTable(_ seq: Sequence) -> [PlacementRow] {
        Layout.compute(seq).map {
            PlacementRow(clipID: $0.clipID.raw,
                         absStartSeconds: $0.absStart.seconds,
                         durationSeconds: $0.duration.seconds,
                         lane: $0.lane)
        }
    }

    static func csv(_ seq: Sequence) -> String {
        var lines = ["clipID,absStart,duration,lane"]
        for r in placementTable(seq) {
            lines.append("\(r.clipID),\(r.absStartSeconds),\(r.durationSeconds),\(r.lane)")
        }
        return lines.joined(separator: "\n")
    }
}
