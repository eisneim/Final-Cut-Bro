import Foundation

/// 项目持久化:保存/打开 .fcbro 项目文件。全量(素材引用 + 所有项目 + 时间线 + 效果)。
extension DocumentStore {
    /// 保存整个文档到 .fcbro 项目文件。
    func saveProject(to url: URL) throws {
        try ProjectPersistence.save(document, to: url)
    }

    /// 从 .fcbro 打开项目:整体替换当前文档并复位 UI/撤销栈。
    func openProject(from url: URL) throws {
        replaceDocument(try ProjectPersistence.load(from: url))
    }
}
