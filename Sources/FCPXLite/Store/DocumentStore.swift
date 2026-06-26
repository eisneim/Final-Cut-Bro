import Observation

/// 顶层单一数据源。命令层通过 apply 作用于 sequence,统一 commit。
@Observable final class DocumentStore {
    var document: Document
    init(document: Document) { self.document = document }

    /// 唯一 commit 入口:把一个 Sequence→Sequence 命令作用到文档并写回。
    func apply(_ transform: (Sequence) -> Sequence) {
        document.sequence = transform(document.sequence)
    }
}
