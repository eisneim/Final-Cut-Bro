import Observation

/// 顶层单一数据源。命令层通过 apply 作用于 sequence,统一 commit。
@Observable final class DocumentStore {
    var document: Document
    var ui: UIState
    init(document: Document, ui: UIState = UIState()) {
        self.document = document
        self.ui = ui
    }

    /// 内部 commit 原语:把一个 Sequence→Sequence 命令作用到文档并写回。
    func apply(_ transform: (Sequence) -> Sequence) {
        document.sequence = transform(document.sequence)
    }

    /// 唯一的"动作"入口。手动 UI 和未来 Agent 都只发 EditorAction。
    func dispatch(_ action: EditorAction) {
        switch action {
        case let .insertClip(c, i):              apply { Mutations.insertClip(c, at: i, in: $0) }
        case let .rippleDelete(i):               apply { Mutations.rippleDelete(at: i, in: $0) }
        case let .liftDelete(i):                 apply { Mutations.liftDelete(at: i, in: $0) }
        case let .moveClip(from, to):            apply { Mutations.moveClip(from: from, to: to, in: $0) }
        case let .trimRight(i, dur, assetDur):   apply { Mutations.rippleTrimRight(at: i, newDuration: dur, assetDuration: assetDur, in: $0) }
        case let .trimLeft(i, deltaIn):          apply { Mutations.rippleTrimLeft(at: i, deltaIn: deltaIn, in: $0) }
        case let .blade(i, localTime):           apply { Mutations.blade(at: i, localTime: localTime, in: $0) }
        case let .connect(c, host, lane, off):   apply { Mutations.connectClip(c, toHostIndex: host, lane: lane, offset: off, in: $0) }
        case let .setInspector(v):               ui.showInspector = v
        case let .setEffects(v):                 ui.showEffects = v
        }
    }
}
