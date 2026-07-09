import Foundation

/// 项目文件(.fcbro)= 整个 Document 的可持久化快照。
/// 覆盖:素材库(按【绝对路径】引用,不拷贝媒体)、所有项目、时间线、
/// 每个片段的变换/裁剪/调色/特效/字幕/关键帧/音量。
/// 带 `version` 便于将来模型演进做迁移。移动/重命名源媒体会断链(素材元数据仍在,时间轴照常加载)。
enum ProjectPersistence {
    static let fileExtension = "fcbro"
    static let currentVersion = 1

    /// 磁盘文件结构:版本号 + 文档。
    struct ProjectFile: Codable {
        var version: Int
        var document: Document
    }

    static func encode(_ document: Document) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(ProjectFile(version: currentVersion, document: document))
    }

    static func decode(_ data: Data) throws -> Document {
        try JSONDecoder().decode(ProjectFile.self, from: data).document
    }

    static func save(_ document: Document, to url: URL) throws {
        try encode(document).write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> Document {
        try decode(Data(contentsOf: url))
    }
}
