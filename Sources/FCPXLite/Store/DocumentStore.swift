import Foundation
import Observation

/// 顶层单一数据源。命令层通过 apply 作用于 sequence,统一 commit。
@Observable final class DocumentStore {
    var document: Document
    var ui: UIState
    var agentMessages: [AgentMessage] = []
    var agentBusy: Bool = false
    /// 用户配置的 LLM provider 列表(磁盘持久化,非文档/非撤销范围)。
    var providers: [ProviderConfig] = ProviderPersistence.load()
    @ObservationIgnored private var agentTask: Task<Void, Never>?
    init(document: Document, ui: UIState = UIState()) {
        self.document = document
        self.ui = ui
        if !providers.contains(where: { $0.id == self.ui.providerId }) {
            self.ui.providerId = providers.first?.id ?? ""
        }
    }

    // MARK: - LLM Provider 管理(设置里增删改,持久化)

    /// 当前选中的 provider(选中失效时回退到第一个)。
    func currentProvider() -> ProviderConfig? {
        providers.first { $0.id == ui.providerId } ?? providers.first
    }
    func addProvider(_ p: ProviderConfig) {
        providers.append(p); ProviderPersistence.save(providers)
        if currentProvider() == nil || ui.providerId.isEmpty { ui.providerId = p.id }
    }
    func updateProvider(_ p: ProviderConfig) {
        guard let i = providers.firstIndex(where: { $0.id == p.id }) else { return }
        providers[i] = p; ProviderPersistence.save(providers)
    }
    func deleteProvider(_ id: String) {
        providers.removeAll { $0.id == id }
        if ui.providerId == id { ui.providerId = providers.first?.id ?? "" }
        ProviderPersistence.save(providers)
    }
    func selectProvider(_ id: String) { ui.providerId = id }

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

    /// 改选中 clip 的 effects(走命令层,可撤销)。
    func updateSelectedEffects(_ f: (inout [Effect]) -> Void) {
        guard let id = ui.selectedClipID, var clip = selectedClip() else { return }
        f(&clip.effects)
        dispatch(.setEffects(id, clip.effects))
    }

    /// V 键:停用/启用选中片段(停用→不参与预览/导出,时间线变暗)。
    func toggleSelectedEnabled() {
        guard let id = ui.selectedClipID, let clip = selectedClip() else { return }
        dispatch(.setEnabled(id, !clip.enabled))
    }

    // MARK: - Agent 对话(UI 按钮与 harness 共用同一路径)

    /// 发送输入框里的内容给 Agent(读 ui.agentInput,清空,跑流式循环)。
    func sendAgentMessage() {
        let text = ui.agentInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !agentBusy else { return }
        ui.agentInput = ""
        guard let provider = currentProvider(), provider.hasKey else {
            agentMessages.append(AgentMessage(role: .assistant,
                text: "未配置可用的 AI provider(缺 API key)。点右上角 ⚙ 在设置里添加 provider 并填入 key。"))
            return
        }
        let svc = StreamingOpenAIBackend(provider: provider)
        let me = self
        agentTask = Task { @MainActor in
            let service = AgentService(store: me, backend: svc)
            await service.send(userText: text)
        }
    }

    /// 停止正在输出的 Agent。
    func stopAgent() {
        agentTask?.cancel()
        agentTask = nil
        agentBusy = false
    }

    /// 唯一的"动作"入口。手动 UI 和未来 Agent 都只发 EditorAction。
    func dispatch(_ action: EditorAction) {
        switch action {
        case let .insertClip(c, i):              apply { Mutations.insertClip(c, at: i, in: $0) }
        case let .overwrite(c, t):               apply { Mutations.overwrite(c, atTime: t, in: $0) }
        case let .rippleDelete(i):               apply { Mutations.rippleDelete(at: i, in: $0) }
        case let .liftDelete(i):                 apply { Mutations.liftDelete(at: i, in: $0) }
        case let .moveClip(from, to):            apply { Mutations.moveClip(from: from, to: to, in: $0) }
        case let .trimRight(i, dur, assetDur):   apply { Mutations.rippleTrimRight(at: i, newDuration: dur, assetDuration: assetDur, in: $0) }
        case let .trimLeft(i, deltaIn):          apply { Mutations.rippleTrimLeft(at: i, deltaIn: deltaIn, in: $0) }
        case let .blade(i, localTime):           apply { Mutations.blade(at: i, localTime: localTime, in: $0) }
        case let .removeConnected(id):           apply { Mutations.removeConnected(clipID: id, in: $0) }
        case let .bladeConnected(id, localTime): apply { Mutations.bladeConnected(clipID: id, localTime: localTime, in: $0) }
        case let .connect(c, host, lane, off):   apply { Mutations.connectClip(c, toHostIndex: host, lane: lane, offset: off, in: $0) }
        case let .relocateClip(id, lane, t):     apply { Mutations.relocate(clipID: id, toLane: lane, atTime: t, in: $0) }
        case let .positionMove(id, t):           apply { Mutations.positionMove(clipID: id, atTime: t, in: $0) }
        case let .positionMoveToLane(id, lane, t): apply { Mutations.positionMoveToLane(clipID: id, toLane: lane, atTime: t, in: $0) }
        case let .setGapDuration(i, dur):        apply { Mutations.setGapDuration(at: i, duration: dur, in: $0) }
        case let .setInspector(v):               ui.showInspector = v
        case let .setShowEffects(v):             ui.showEffects = v
        case let .setShowExport(v):              ui.showExport = v
        case let .createProject(p):
            snapshot(); document.projects.append(p); document.currentProjectID = p.id
        case let .selectProject(id):
            snapshot(); document.currentProjectID = id; ui.selectedClipID = nil; ui.playhead = .zero
        case let .setShowProjectModal(v):        ui.showProjectModal = v
        case let .importAsset(a):                snapshot(); document.assetLibrary.append(a)
        case let .selectClip(id):                ui.selectedClipID = id; ui.selectedGapID = nil
        case let .selectGap(id):                 ui.selectedGapID = id; ui.selectedClipID = nil
        case let .setGapDurationByID(id, dur):   apply { Mutations.setGapDurationByID(id, duration: dur, in: $0) }
        case let .moveGap(id, t):                apply { Mutations.moveGap(id, toTime: t, in: $0) }
        case let .removeGap(id):                 apply { Mutations.removeGap(id, in: $0) }
        case let .setTool(t):                    ui.currentTool = t
        case let .setZoom(z):                    ui.pxPerSecond = max(1, min(400, z))   // 下限1px/秒:1小时电影可整屏展现
        case let .setPlayhead(t):                ui.playhead = t
        case let .setTimelineFraction(f):        ui.timelineFraction = max(0.15, min(0.85, f))
        case let .selectAsset(id):
            // 单选:清除多选集,只保留这一个(同时更新 anchor)
            ui.selectedAssetID = id
            ui.selectedAssetIDs = id.map { [$0] } ?? []
        case let .toggleAssetSelected(id):
            // ⌘-click:切换单个素材的选中状态;anchor 更新到该素材
            if ui.selectedAssetIDs.contains(id) {
                ui.selectedAssetIDs.remove(id)
            } else {
                ui.selectedAssetIDs.insert(id)
                ui.selectedAssetID = id   // 更新 anchor
            }
        case let .selectAssetRange(id):
            // ⇧-click:从 anchor 到 id 在 assetLibrary 顺序中选中区间
            let ids = document.assetLibrary.map(\.id)
            guard let toIdx = ids.firstIndex(of: id) else { break }
            let fromIdx = ui.selectedAssetID.flatMap { ids.firstIndex(of: $0) } ?? toIdx
            let lo = min(fromIdx, toIdx)
            let hi = max(fromIdx, toIdx)
            for i in lo...hi { ui.selectedAssetIDs.insert(ids[i]) }
            // anchor 不变(FCP 行为:Shift 不移动 anchor)
        case .selectAllAssets:
            // ⌘A:选中全部素材(不影响时间轴选中)
            ui.selectedAssetIDs = Set(document.assetLibrary.map(\.id))
            ui.selectedAssetID = document.assetLibrary.last?.id   // anchor 设为最后一个
        case .clearAssetSelection:
            ui.selectedAssetIDs = []
            ui.selectedAssetID = nil
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
        case let .setEffects(id, fx):    apply { Mutations.setEffects(clipID: id, fx, in: $0) }
        case let .setVolumeKeyframes(id, kfs): apply { Mutations.setVolumeKeyframes(clipID: id, kfs, in: $0) }
        case let .setEnabled(id, on):    apply { Mutations.setEnabled(clipID: id, on, in: $0) }
        }
    }

    // MARK: - 高层编辑操作(工具栏按钮与键盘快捷键共用)

    /// 追加所选素材到主轴末尾。
    func appendSelected() {
        guard let clip = clipFromSelection() else { return }
        dispatch(.insertClip(clip, at: document.sequence.spine.count))
    }

    /// 批量追加多选素材到主轴末尾(按 assetLibrary 顺序)。
    func appendAllSelected() {
        let ordered = document.assetLibrary.filter { ui.selectedAssetIDs.contains($0.id) }
        for asset in ordered {
            dispatch(.insertClip(
                Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration),
                at: document.sequence.spine.count
            ))
        }
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

    /// 覆盖(FCP D):用所选素材覆盖播放头处的区间,裁掉被覆盖内容,总时长不变。
    func overwriteAtPlayhead() {
        guard let clip = clipFromSelection() else { return }
        dispatch(.overwrite(clip, atTime: ui.playhead))
    }

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
        // 优先:若选中的是连接片段且播放头在其范围内,切它(FCP:不在主轨也能切)。
        if let id = ui.selectedClipID, let conn = connectedPlacement(id),
           playhead > conn.start, playhead < conn.start + conn.duration {
            dispatch(.bladeConnected(id, localTime: playhead - conn.start))
            return
        }
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

    /// 选中片段的连接位置(绝对起点+时长),非连接片段返回 nil。
    private func connectedPlacement(_ id: ClipID) -> (start: Time, duration: Time)? {
        for p in Layout.compute(document.sequence) where p.isConnected && p.clipID == id {
            return (p.absStart, p.duration)
        }
        return nil
    }

    /// 删除选中片段(FCP: Delete)。主轴 clip → ripple 合拢;连接片段 → 从宿主移除;gap → 移除。
    func deleteSelected() {
        if let gid = ui.selectedGapID {
            dispatch(.removeGap(gid)); dispatch(.selectGap(nil)); return
        }
        guard let id = ui.selectedClipID else { return }
        if let idx = TimelineGeometry.spineIndex(ofClipID: id, in: document.sequence) {
            dispatch(.rippleDelete(at: idx))
        } else {
            dispatch(.removeConnected(id))   // 连接片段
        }
        dispatch(.selectClip(nil))
    }

    private func clipFromSelection() -> Clip? {
        let assetID = ui.selectedAssetID ?? document.assetLibrary.first?.id
        guard let id = assetID,
              let asset = document.assetLibrary.first(where: { $0.id == id }) else { return nil }
        return Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration)
    }

    // MARK: - 快速 trim 到播放头(⌥[ 裁当前片段头 / ⌥] 裁当前片段尾)

    /// ⌥[ : 只裁【光标所在片段】的头 —— 去掉该片段在光标左侧的部分(入点前移到光标),其它片段不动。
    func trimLeftOfPlayhead() {
        guard let (i, clipStart, _) = clipAtPlayhead() else { return }
        let deltaIn = ui.playhead - clipStart    // 头部要去掉的时长 = 光标 − 片段起点
        guard deltaIn > .zero else { return }
        dispatch(.trimLeft(at: i, deltaIn: deltaIn))
    }

    /// ⌥] : 只裁【光标所在片段】的尾 —— 去掉该片段在光标右侧的部分(时长缩到光标处),其它片段不动。
    func trimRightOfPlayhead() {
        guard let (i, clipStart, clip) = clipAtPlayhead() else { return }
        let newDur = ui.playhead - clipStart     // 新时长 = 光标 − 片段起点
        guard newDur > .zero else { return }
        let assetDur = document.assetLibrary.first { $0.id == clip.assetID }?.duration ?? clip.duration
        dispatch(.trimRight(at: i, newDuration: newDur, assetDuration: assetDur))
    }

    /// 找到光标所在的主轴片段(spine 下标、绝对起点、clip)。光标不在任何片段内返回 nil。
    private func clipAtPlayhead() -> (index: Int, start: Time, clip: Clip)? {
        let playhead = ui.playhead
        var elapsed = Time.zero
        for (i, el) in document.sequence.spine.enumerated() {
            let start = elapsed
            elapsed = elapsed + el.duration
            if case .clip(let c) = el, playhead > start, playhead < elapsed {
                return (i, start, c)
            }
        }
        return nil
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

    // MARK: - 导出

    /// 导出 fcpxml 工程文件(同步写字符串)。失败抛出,不静默。
    func exportFCPXML(to url: URL) throws {
        let xml = FCPXMLExporter.export(document)
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 导出成片(异步,更新 ui.exportProgress)。成功关闭面板;失败把原因写进 ui.exportError。
    func exportMovie(to url: URL, settings: ExportSettings = ExportSettings()) {
        ui.exportError = nil
        ui.exportProgress = 0
        MovieExporter.export(document: document, to: url, settings: settings,
                             progress: { [weak self] p in self?.ui.exportProgress = Double(p) },
                             completion: { [weak self] result in
            guard let self else { return }
            self.ui.exportProgress = nil
            switch result {
            case .success:
                self.ui.showExport = false
            case .failure(let e):
                self.ui.exportError = "导出失败:\(e)"
            }
        })
    }
}
