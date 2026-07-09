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
    /// Agent 请求用户确认(write_file/edit_file/run_command 等危险操作)。
    @ObservationIgnored var agentConfirm: AgentConfirm? = nil
    /// run_command 后台命令(ffmpeg/python 等)执行完的结果(AgentService 轮询取用)。
    @ObservationIgnored var agentAsyncResult: (id: UUID, result: String)? = nil
    /// 复制/粘贴剪贴板(瞬时缓冲,不进文档/不撤销)。
    @ObservationIgnored var clipboard: Clip?
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

    /// 拖拽会话实时编辑:firstTick=true 时先快照(整段拖拽合成【一次】撤销),之后只替换序列不再堆 undo。
    /// transform 通常从【拖拽起点的序列快照】按总位移重算,保证幂等(不累积)。
    func dragEdit(firstTick: Bool, _ transform: (Sequence) -> Sequence) {
        if firstTick { snapshot() }
        document.sequence = transform(document.sequence)
    }

    /// 用一个新文档整体替换当前状态(打开 .fcbro 项目文件用):
    /// 清空撤销/重做栈(新文档没有历史),复位播放头与选择,避免旧选择指向不存在的 id。
    func replaceDocument(_ doc: Document) {
        document = doc
        undoStack.removeAll(); redoStack.removeAll()
        ui.playhead = .zero
        ui.selectedClipID = nil; ui.selectedClipIDs = []
        ui.selectedAssetID = nil; ui.selectedAssetIDs = []
    }

    // MARK: - 撤销 / 重做

    private var undoStack: [Document] = []
    private var redoStack: [Document] = []
    private let undoLimit = 80
    private var inTransaction = false
    /// 拖拽手势级合并态(与 inTransaction 解耦,避免二者互相踩)。
    private var interactiveOpen = false
    /// 是否处于"合并/事务"态 → snapshot 只清 redo 不堆 undo。
    private var isGrouping: Bool { inTransaction || interactiveOpen }

    /// 把内部多次 dispatch/apply 合成【一次】撤销(批量动作用,如 build_subtitle_cut)。
    /// 开头快照一次,期间所有 snapshot() 被吞掉;结束后这一整批可被单次 undo 还原。
    func transaction(_ body: () -> Void) {
        if isGrouping { body(); return }   // 已在合并态(事务或拖拽)→ 不重复快照、不动标志位
        snapshot()
        inTransaction = true
        defer { inTransaction = false }
        body()
    }

    /// 文档变更前快照(供撤销)。清空重做栈。合并态内不再堆叠(已在开头快照过一次)。
    private func snapshot() {
        if isGrouping { redoStack.removeAll(); return }
        undoStack.append(document)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// 拖拽手势级撤销合并:手势内【首次真正改动前】调用 → 快照一次并进入合并态。
    /// 其后每个 tick 的 apply/dispatch 不再堆 undo。mouseUp 调 endInteractiveEdit 结束。
    /// 效果:一整段拖拽(如把结尾从 0 拖到 30)只留【一次】撤销点 → ⌘Z 一步回到拖拽前,而非逐像素回撤。
    /// 用独立的 interactiveOpen 标志(不复用 inTransaction),避免与 transaction{} 互相污染。
    func beginInteractiveEdit() {
        guard !interactiveOpen else { return }   // 幂等:一次手势只快照一次
        if !inTransaction { snapshot() }         // 已在事务里就不重复快照
        interactiveOpen = true
    }
    func endInteractiveEdit() { interactiveOpen = false }

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
        return document.sequence.clip(id: id)
    }

    /// 当前选中的素材(inspector 显示 meta 用)。
    func selectedAsset() -> Asset? {
        guard let id = ui.selectedAssetID else { return nil }
        return document.assetLibrary.first { $0.id == id }
    }

    /// 按 id 集合取出 clip(主轴或连接子项),保持调用方传入顺序无关。
    func clipsByIDs(_ ids: Set<ClipID>) -> [(id: ClipID, clip: Clip)] {
        guard !ids.isEmpty else { return [] }
        var out: [(ClipID, Clip)] = []
        for el in document.sequence.spine {
            if case .clip(let c) = el {
                if ids.contains(c.id) { out.append((c.id, c)) }
                for ch in c.connected where ids.contains(ch.id) { out.append((ch.id, ch)) }
            }
        }
        return out
    }

    /// 当前多选集合(空则退回 anchor 单选)。
    func effectiveSelection() -> Set<ClipID> {
        if !ui.selectedClipIDs.isEmpty { return ui.selectedClipIDs }
        if let id = ui.selectedClipID { return [id] }
        return []
    }

    /// 修改选中 clip 的 Adjustments(走命令层,可撤销)。多选时对【全部选中片段】施加同一闭包,合成单次 undo。
    func updateSelectedAdjust(_ f: (inout Adjustments) -> Void) {
        let targets = clipsByIDs(effectiveSelection())
        guard !targets.isEmpty else { return }
        transaction {
            for (id, clip) in targets {
                var adj = clip.adjust; f(&adj); dispatch(.setAdjust(id, adj))
            }
        }
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

    /// 选中片段在时间线上的绝对起点(主轴或连接均可)。
    func clipAbsStart(_ id: ClipID) -> Time? {
        for p in Layout.compute(document.sequence) where p.clipID == id { return p.absStart }
        return nil
    }

    /// 在播放头处给选中片段加一个变换关键帧:抓取当前 位移/缩放/不透明度,
    /// 时间 = 播放头相对片段起点(clamp 到 [0, 时长])。同时间已有则替换。
    func addTransformKeyframeAtPlayhead() {
        guard let id = ui.selectedClipID, let clip = selectedClip(),
              let absStart = clipAbsStart(id) else { return }
        let relSecs = max(0, min(clip.duration.seconds, ui.playhead.seconds - absStart.seconds))
        let t = Time.seconds(relSecs)
        let kf = TransformKeyframe(time: t,
                                   position: clip.adjust.transform.position,
                                   scale: clip.adjust.transform.scale,
                                   opacity: clip.adjust.opacity)
        var kfs = clip.transformKeyframes.filter { abs($0.time.seconds - relSecs) > 0.001 }  // 同时间替换
        kfs.append(kf)
        kfs.sort { $0.time < $1.time }
        dispatch(.setTransformKeyframes(id, kfs))
    }

    /// 清空选中片段的变换关键帧(回到静态变换)。
    func clearTransformKeyframes() {
        guard let id = ui.selectedClipID else { return }
        dispatch(.setTransformKeyframes(id, []))
    }

    /// 效果/转场面板:给选中片段追加一个特效。
    func addEffectToSelected(_ kind: EffectKind) {
        updateSelectedEffects { $0.append(Effect.make(kind)) }
    }

    /// 从 Finder 拖入的文件 → 导入素材库(拖到窗口任意处都可用,不止素材池)。
    func importDroppedProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                Task { @MainActor in
                    do { self.dispatch(.importAsset(try MediaImporter.importAsset(from: url))) }
                    catch { print("[importDropped] 失败: \(error)") }
                }
            }
        }
    }

    /// Skimming(瞬时 UI,不进 undo):设置/清除当前划过的素材+时间,viewer 覆盖层据此显示帧。
    func setSkim(_ assetID: AssetID?, seconds: Double) {
        ui.skimAssetID = assetID
        ui.skimSeconds = seconds
    }

    /// 效果/转场面板:给选中的【主轴片段】加交叉叠化转场(与前一片段)。返回 false=无法加(未选/首片段/连接片段)。
    @discardableResult
    func addCrossfadeToSelected(seconds: Double) -> Bool {
        guard let id = ui.selectedClipID,
              let idx = TimelineGeometry.spineIndex(ofClipID: id, in: document.sequence),
              idx >= 1 else { return false }
        dispatch(.setCrossfade(at: idx, duration: .seconds(seconds)))
        return true
    }

    // MARK: - 复制 / 粘贴(⌘C / ⌘V)

    /// ⌘C:复制选中片段到剪贴板(深拷贝,粘贴时再换新 id)。
    func copySelected() {
        clipboard = selectedClip()
    }

    /// ⌘V:把剪贴板片段粘贴到播放头处 —— 插入主轴,起点在播放头所在的最近编辑点(不分割已有片段)。
    /// 片段及其连接子项都换新 id(避免 id 撞车)。粘贴后选中新片段。
    func pasteAtPlayhead() {
        guard let src = clipboard else { return }
        guard document.hasProject else { return }
        let dup = src.duplicatedWithNewIDs()
        let idx = spineInsertIndexAtPlayhead()
        dispatch(.insertClip(dup, at: idx))
        dispatch(.selectClip(dup.id))
    }

    /// ⌘⇧V:粘贴【属性】—— 把剪贴板片段的 调整(变换/裁剪/不透明/音量)+ 特效 + 变换/音量关键帧
    /// 应用到【所有选中片段】(FCP 高频:一个片段调好效果,复制,选中其他片段,一键套用)。整批单次 undo。
    func pasteAttributesToSelected() {
        guard let src = clipboard else { return }
        let targets = clipsByIDs(effectiveSelection())
        guard !targets.isEmpty else { return }
        transaction {
            for (id, _) in targets {
                dispatch(.setAdjust(id, src.adjust))
                dispatch(.setEffects(id, src.effects))
                dispatch(.setTransformKeyframes(id, src.transformKeyframes))
                dispatch(.setVolumeKeyframes(id, src.volumeKeyframes))
            }
        }
    }

    /// 主轴插入下标:跳过所有"结束 ≤ 播放头"的元素 → 在播放头所在/之后的编辑点插入。
    func spineInsertIndexAtPlayhead() -> Int {
        let ph = ui.playhead.seconds
        var elapsed = 0.0
        var idx = 0
        for el in document.sequence.spine {
            let end = elapsed + el.duration.seconds
            if end <= ph + 0.0005 { idx += 1; elapsed = end } else { break }
        }
        return idx
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

    /// 停止正在输出的 Agent。清空所有待决/结果槽,避免被取消的一轮遗留结果被下一轮误取(cross-talk)。
    func stopAgent() {
        agentTask?.cancel()
        agentTask = nil
        agentBusy = false
        agentConfirm = nil
        agentConfirmResult = nil
        agentAsyncResult = nil
    }

    /// Agent 请求用户确认(write_file/edit_file/run_command 等危险操作)。
    /// 调用后 AgentService 暂停工具执行,chat UI 显示确认卡片,用户点"允许"/"拒绝"后回调执行。
    func requestAgentConfirm(tool: String, message: String, args: [String: Any],
                              action: @escaping @MainActor (Bool) -> String) {
        agentConfirm = AgentConfirm(tool: tool, message: message, args: args, action: action)
        // 在 chat 里插入一条确认消息(带 confirmID,UI 渲染卡片)
        let cid = agentConfirm!.id
        agentMessages.append(AgentMessage(id: cid, role: .confirm,
                                           text: message, toolName: tool, streaming: false))
    }

    /// 用户点"允许"或"拒绝"。
    func respondAgentConfirm(approve: Bool) {
        guard let c = agentConfirm else { return }
        agentConfirm = nil
        let result = MainActor.assumeIsolated { c.action(approve) }
        // 把确认结果更新到对应消息
        if let idx = agentMessages.firstIndex(where: { $0.id == c.id }) {
            agentMessages[idx].text = (approve ? "✅ 已确认: " : "❌ 已拒绝: ") + c.message
            agentMessages[idx].role = .tool   // 确认完成后变成普通 tool 消息
        }
        // 存储结果供 AgentService 读取(继续工具循环)
        agentConfirmResult = (id: c.id, result: result)
    }

    /// AgentService 等待确认结果的存储槽。
    @ObservationIgnored var agentConfirmResult: (id: UUID, result: String)? = nil

    /// 唯一的"动作"入口。手动 UI 和未来 Agent 都只发 EditorAction。
    func dispatch(_ action: EditorAction) {
        PerfProbe.shared.measure("DocumentStore.dispatch") { dispatchImpl(action) }
    }

    private func dispatchImpl(_ action: EditorAction) {
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
        case let .setShowBrowser(v):             ui.showBrowser = v
        case let .setShowChat(v):                ui.showChat = v
        case let .setShowExport(v):              ui.showExport = v
        case let .setShowSettings(v):            ui.showSettings = v
        case let .createProject(p):
            snapshot(); document.projects.append(p); document.currentProjectID = p.id; ui.inspectorFocus = .project
        case let .selectProject(id):
            snapshot(); document.currentProjectID = id; ui.selectedClipID = nil; ui.playhead = .zero; ui.inspectorFocus = .project
        case let .removeProject(id):
            snapshot()
            document.projects.removeAll { $0.id == id }
            // 删的是当前项目 → 切到剩下的第一个(没有则回到无项目门控)。
            if document.currentProjectID == id {
                document.currentProjectID = document.projects.first?.id
                ui.selectedClipID = nil; ui.selectedGapID = nil; ui.playhead = .zero
            }
        case let .renameProject(id, name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }   // 空名忽略
            snapshot()
            if let i = document.projects.firstIndex(where: { $0.id == id }) {
                document.projects[i].name = trimmed
            }
        case let .setShowProjectModal(v):        ui.showProjectModal = v
        case let .importAsset(a):                snapshot(); document.assetLibrary.append(a)
        case let .removeAsset(id):               snapshot(); document.assetLibrary.removeAll { $0.id == id }; ui.selectedAssetIDs.remove(id); if ui.selectedAssetID == id { ui.selectedAssetID = nil }
        case let .selectClip(id):                ui.selectedClipID = id; ui.selectedClipIDs = id.map { [$0] } ?? []; ui.selectedGapID = nil; ui.selectedTransitionClipID = nil; if id != nil { ui.inspectorFocus = .clip }
        case let .selectClips(ids, anchor):      ui.selectedClipIDs = ids; ui.selectedClipID = anchor ?? ids.first; ui.selectedGapID = nil; ui.selectedTransitionClipID = nil; if !ids.isEmpty { ui.inspectorFocus = .clip }
        case let .selectGap(id):                 ui.selectedGapID = id; ui.selectedClipID = nil; ui.selectedTransitionClipID = nil
        case let .selectTransition(id):          ui.selectedTransitionClipID = id; ui.selectedClipID = nil; ui.selectedGapID = nil
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
            if id != nil { ui.inspectorFocus = .asset }
        case let .toggleAssetSelected(id):
            // ⌘-click:切换单个素材的选中状态;anchor 更新到该素材
            if ui.selectedAssetIDs.contains(id) {
                ui.selectedAssetIDs.remove(id)
            } else {
                ui.selectedAssetIDs.insert(id)
                ui.selectedAssetID = id   // 更新 anchor
            }
            ui.inspectorFocus = .asset
        case let .selectAssetRange(id):
            // ⇧-click:从 anchor 到 id 在 assetLibrary 顺序中选中区间
            let ids = document.assetLibrary.map(\.id)
            guard let toIdx = ids.firstIndex(of: id) else { break }
            let fromIdx = ui.selectedAssetID.flatMap { ids.firstIndex(of: $0) } ?? toIdx
            let lo = min(fromIdx, toIdx)
            let hi = max(fromIdx, toIdx)
            for i in lo...hi { ui.selectedAssetIDs.insert(ids[i]) }
            ui.inspectorFocus = .asset
            // anchor 不变(FCP 行为:Shift 不移动 anchor)
        case .selectAllAssets:
            // ⌘A:选中全部素材(不影响时间轴选中)
            ui.selectedAssetIDs = Set(document.assetLibrary.map(\.id))
            ui.selectedAssetID = document.assetLibrary.last?.id   // anchor 设为最后一个
        case .clearAssetSelection:
            ui.selectedAssetIDs = []
            ui.selectedAssetID = nil
        case let .setPlaying(v):                 ui.isPlaying = v
        case .togglePlay:
            // 播放优先级高于 skimming:skimming 中按空格 → 从 skimmer 位置起播 + 取消 skim。
            if !ui.isPlaying, let s = ui.timelineSkimSeconds {
                ui.playhead = .seconds(s)
                ui.timelineSkimSeconds = nil
            }
            ui.isPlaying.toggle()
        case .toggleSnapping:                    ui.snappingEnabled.toggle()
        case .toggleTimelineSkimming:
            ui.timelineSkimming.toggle()
            if !ui.timelineSkimming { ui.timelineSkimSeconds = nil }   // 关掉即清除 skimmer,预览回到播放头
        case let .setTimelineSkim(s):            ui.timelineSkimSeconds = s
        case let .setPanelWidth(panel, w):
            let cw = max(80, min(700, w))
            switch panel {
            case .sidebar:   ui.sidebarWidth = cw
            case .browser:   ui.browserWidth = cw
            case .inspector: ui.inspectorWidth = cw
            case .chat:      ui.chatWidth = cw
            case .effects:   ui.effectsWidth = cw
            }
        case let .setClipHeight(h):      ui.clipHeight = max(40, min(160, h))
        case let .setVideoAudioRatio(r): ui.videoAudioRatio = max(0.1, min(0.9, r))
        case let .setAssetStripZoom(z):  ui.assetStripZoom = max(2, min(80, z))
        case let .setAdjust(id, a):      apply { Mutations.setAdjust(clipID: id, a, in: $0) }
        case let .setEffects(id, fx):    apply { Mutations.setEffects(clipID: id, fx, in: $0) }
        case let .setVolumeKeyframes(id, kfs): apply { Mutations.setVolumeKeyframes(clipID: id, kfs, in: $0) }
        case let .setTransformKeyframes(id, kfs): apply { Mutations.setTransformKeyframes(clipID: id, kfs, in: $0) }
        case let .slip(i, delta, assetDur): apply { Mutations.slip(at: i, delta: delta, assetDuration: assetDur, in: $0) }
        case let .slide(i, delta, prevDur, nextDur): apply { Mutations.slide(at: i, delta: delta, prevAssetDuration: prevDur, nextAssetDuration: nextDur, in: $0) }
        case let .setCrossfade(i, dur): apply { Mutations.setCrossfade(at: i, duration: dur, in: $0) }
        case let .setTitle(id, spec): apply { Mutations.setTitle(clipID: id, spec, in: $0) }
        case let .setConnectedTiming(id, off, si, dur): apply { Mutations.setClipTiming(clipID: id, offset: off, sourceIn: si, duration: dur, in: $0) }
        case let .relocateConnected(id, lane, t): apply { Mutations.relocateConnected(clipID: id, toLane: lane, atTime: t, in: $0) }
        case let .setEnabled(id, on):    apply { Mutations.setEnabled(clipID: id, on, in: $0) }
        }
    }

}
