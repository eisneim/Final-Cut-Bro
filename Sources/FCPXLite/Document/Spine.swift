import Foundation

/// 主时间线:有序元素数组,首尾相接,磁性隐含在顺序里。
struct Sequence: Codable, Equatable {
    var spine: [Element]
}

/// 一个项目(对应 FCP 的 Project):自带格式(分辨率/帧率)与时间线。
struct Project: Identifiable, Codable, Equatable {
    let id: ProjectID
    var name: String
    var formatWidth: Int
    var formatHeight: Int
    var frameRate: Double
    var sequence: Sequence

    init(id: ProjectID = ProjectID(), name: String,
         formatWidth: Int, formatHeight: Int, frameRate: Double,
         sequence: Sequence = Sequence(spine: [])) {
        self.id = id; self.name = name
        self.formatWidth = formatWidth; self.formatHeight = formatHeight
        self.frameRate = frameRate; self.sequence = sequence
    }
}

/// 顶层文档:共享素材库 + 多个项目 + 当前项目。
/// 旧代码(以及大量测试/导出/合成)用 `document.sequence`/`formatWidth` 等单项目接口,
/// 这里用计算属性代理到【当前项目】,保持向后兼容;无项目时给出空时间线/默认格式。
struct Document: Codable, Equatable {
    var assetLibrary: [Asset]
    var projects: [Project]
    var currentProjectID: ProjectID?

    /// 向后兼容 init:建一个默认项目(老调用点/测试都走这条)。
    init(formatWidth: Int, formatHeight: Int, frameRate: Double,
         assetLibrary: [Asset], sequence: Sequence) {
        let p = Project(name: "项目 1", formatWidth: formatWidth, formatHeight: formatHeight,
                        frameRate: frameRate, sequence: sequence)
        self.assetLibrary = assetLibrary
        self.projects = [p]
        self.currentProjectID = p.id
    }

    /// 多项目 init。
    init(assetLibrary: [Asset], projects: [Project], currentProjectID: ProjectID?) {
        self.assetLibrary = assetLibrary
        self.projects = projects
        self.currentProjectID = currentProjectID
    }

    // MARK: - 当前项目代理

    var currentProjectIndex: Int? {
        if let id = currentProjectID, let i = projects.firstIndex(where: { $0.id == id }) { return i }
        return projects.isEmpty ? nil : 0
    }
    var currentProject: Project? { currentProjectIndex.map { projects[$0] } }

    /// 是否已有可用项目(无项目 → 时间轴门控)。
    var hasProject: Bool { currentProject != nil }

    /// 当前项目的时间线(读写代理)。无项目时读到空、写入被忽略。
    var sequence: Sequence {
        get { currentProject?.sequence ?? Sequence(spine: []) }
        set { if let i = currentProjectIndex { projects[i].sequence = newValue } }
    }

    var formatWidth: Int { currentProject?.formatWidth ?? 1920 }
    var formatHeight: Int { currentProject?.formatHeight ?? 1080 }
    var frameRate: Double { currentProject?.frameRate ?? 25 }
}
