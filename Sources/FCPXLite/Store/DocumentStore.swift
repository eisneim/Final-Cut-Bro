import Observation

/// 顶层单一数据源。命令层通过 apply 作用于 sequence,统一 commit。
@Observable final class DocumentStore {
    var document: Document
    var ui: UIState
    init(document: Document, ui: UIState = UIState()) {
        self.document = document
        self.ui = ui
    }

    /// 内部 commit 原语:把一个 Sequence→Sequence 命令作用到文档并写回(并记录撤销快照)。
    func apply(_ transform: (Sequence) -> Sequence) {
        snapshot()
        document.sequence = transform(document.sequence)
    }

    // MARK: - 撤销 / 重做

    private var undoStack: [Document] = []
    private var redoStack: [Document] = []
    private let undoLimit = 80

    /// 文档变更前快照(供撤销)。清空重做栈。
    private func snapshot() {
        undoStack.append(document)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Inspector

    /// 当前选中的 clip(主轴或连接子项)。
    func selectedClip() -> Clip? {
        guard let id = ui.selectedClipID else { return nil }
        for el in document.sequence.spine {
            if case .clip(let c) = el {
                if c.id == id { return c }
                for ch in c.connected where ch.id == id { return ch }
            }
        }
        return nil
    }

    /// 修改选中 clip 的 Adjustments(走命令层,可撤销)。
    func updateSelectedAdjust(_ f: (inout Adjustments) -> Void) {
        guard let id = ui.selectedClipID, var clip = selectedClip() else { return }
        f(&clip.adjust)
        dispatch(.setAdjust(id, clip.adjust))
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
        case let .positionMove(id, t):           apply { Mutations.positionMove(clipID: id, atTime: t, in: $0) }
        case let .setGapDuration(i, dur):        apply { Mutations.setGapDuration(at: i, duration: dur, in: $0) }
        case let .setInspector(v):               ui.showInspector = v
        case let .setEffects(v):                 ui.showEffects = v
        case let .importAsset(a):                snapshot(); document.assetLibrary.append(a)
        case let .selectClip(id):                ui.selectedClipID = id
        case let .setTool(t):                    ui.currentTool = t
        case let .setZoom(z):                    ui.pxPerSecond = max(8, min(400, z))
        case let .setPlayhead(t):                ui.playhead = t
        case let .setTimelineHeight(h):          ui.timelineHeight = max(120, min(640, h))
        case let .selectAsset(id):               ui.selectedAssetID = id
        case let .setPlaying(v):                 ui.isPlaying = v
        case .togglePlay:                        ui.isPlaying.toggle()
        case .toggleSnapping:                    ui.snappingEnabled.toggle()
        case let .setPanelWidth(panel, w):
            let cw = max(80, min(700, w))
            switch panel {
            case .sidebar:   ui.sidebarWidth = cw
            case .browser:   ui.browserWidth = cw
            case .inspector: ui.inspectorWidth = cw
            case .chat:      ui.chatWidth = cw
            }
        case let .setClipHeight(h):      ui.clipHeight = max(40, min(160, h))
        case let .setVideoAudioRatio(r): ui.videoAudioRatio = max(0.1, min(0.9, r))
        case let .setAdjust(id, a):      apply { Mutations.setAdjust(clipID: id, a, in: $0) }
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

    // MARK: - 播放头 / 切割 / 删除(键盘快捷键共用)

    /// 按帧步进播放头(FCP: ←/→ ±1 帧,⇧←/→ ±10 帧)。
    func nudgePlayhead(frames: Int) {
        let fps = document.frameRate > 0 ? document.frameRate : 25
        let secs = max(0, ui.playhead.seconds + Double(frames) / fps)
        dispatch(.setPlayhead(Time.seconds(secs)))
    }

    /// 播放头跳到时间线开头(FCP: Home)。
    func playheadToStart() { dispatch(.setPlayhead(.zero)) }

    /// 播放头跳到时间线结尾(FCP: End)。
    func playheadToEnd() {
        var total = Time.zero
        for el in document.sequence.spine { total = total + el.duration }
        dispatch(.setPlayhead(total))
    }

    /// 在播放头处切割主轴 clip(FCP: ⌘B)。
    func bladeAtPlayhead() {
        let playhead = ui.playhead
        var elapsed = Time.zero
        for (i, el) in document.sequence.spine.enumerated() {
            let start = elapsed
            elapsed = elapsed + el.duration
            if case .clip = el, playhead > start, playhead < elapsed {
                dispatch(.blade(at: i, localTime: playhead - start))
                return
            }
        }
    }

    /// 删除选中的主轴 clip(FCP: Delete,ripple 合拢)。
    func deleteSelected() {
        guard let id = ui.selectedClipID,
              let idx = TimelineGeometry.spineIndex(ofClipID: id, in: document.sequence) else { return }
        dispatch(.rippleDelete(at: idx))
        dispatch(.selectClip(nil))
    }

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
