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
        case let .relocateClip(id, lane, t):     apply { Mutations.relocate(clipID: id, toLane: lane, atTime: t, in: $0) }
        case let .setInspector(v):               ui.showInspector = v
        case let .setEffects(v):                 ui.showEffects = v
        case let .importAsset(a):                document.assetLibrary.append(a)
        case let .selectClip(id):                ui.selectedClipID = id
        case let .setTool(t):                    ui.currentTool = t
        case let .setZoom(z):                    ui.pxPerSecond = max(8, min(400, z))
        case let .setPlayhead(t):                ui.playhead = t
        case let .setTimelineHeight(h):          ui.timelineHeight = max(120, min(640, h))
        case let .selectAsset(id):               ui.selectedAssetID = id
        case let .setPlaying(v):                 ui.isPlaying = v
        case .togglePlay:                        ui.isPlaying.toggle()
        }
    }

    // MARK: - 高层编辑操作(工具栏按钮与键盘快捷键共用)

    /// 追加所选素材到主轴末尾。
    func appendSelected() {
        guard let clip = clipFromSelection() else { return }
        dispatch(.insertClip(clip, at: document.sequence.spine.count))
    }

    /// 在播放头处插入所选素材。
    func insertAtPlayhead() {
        guard let clip = clipFromSelection() else { return }
        dispatch(.insertClip(clip, at: spineIndexAtPlayhead()))
    }

    /// 把所选素材作为连接片段挂到播放头处的主轴 clip 上方(lane 1)。
    func connectAtPlayhead() {
        guard let clip = clipFromSelection() else { return }
        let host = spineIndexAtPlayhead()
        guard host < document.sequence.spine.count else {
            dispatch(.insertClip(clip, at: document.sequence.spine.count))
            return
        }
        dispatch(.connect(clip, host: host, lane: 1, offset: .zero))
    }

    /// 覆盖(TODO: 真覆盖语义;v1 暂同插入)。
    func overwriteAtPlayhead() { insertAtPlayhead() }

    private func clipFromSelection() -> Clip? {
        let assetID = ui.selectedAssetID ?? document.assetLibrary.first?.id
        guard let id = assetID,
              let asset = document.assetLibrary.first(where: { $0.id == id }) else { return nil }
        return Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration)
    }

    private func spineIndexAtPlayhead() -> Int {
        let playhead = ui.playhead
        var elapsed = Time.zero
        for (i, element) in document.sequence.spine.enumerated() {
            if case .clip(let c) = element {
                let end = elapsed + c.duration
                if playhead < end { return i }
                elapsed = end
            }
        }
        return document.sequence.spine.count
    }
}
