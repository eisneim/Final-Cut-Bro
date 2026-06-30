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

    /// 主轴插入下标:跳过所有"结束 ≤ 播放头"的元素 → 在播放头所在/之后的编辑点插入。
    private func spineInsertIndexAtPlayhead() -> Int {
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
        case let .selectClip(id):                ui.selectedClipID = id; ui.selectedGapID = nil; ui.selectedTransitionClipID = nil
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

    /// 在播放头处加一个标题(连接到上方 lane 1;无主轴片段则插主轴)。默认 5s。
    @discardableResult
    func addTitleAtPlayhead(text: String = "标题") -> ClipID {
        var spec = TitleSpec(); spec.text = text
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(5), title: spec)
        let host = spineIndexAtPlayhead()
        if host < document.sequence.spine.count {
            var acc = 0.0
            for i in 0..<host { acc += document.sequence.spine[i].duration.seconds }
            let offset = max(0, ui.playhead.seconds - acc)
            dispatch(.connect(title, host: host, lane: 1, offset: .seconds(offset)))
        } else {
            dispatch(.insertClip(title, at: document.sequence.spine.count))
        }
        dispatch(.selectClip(title.id))
        return title.id
    }

    /// 改选中标题片段的规格(inspector / on-screen 编辑)。
    func updateSelectedTitle(_ f: (inout TitleSpec) -> Void) {
        guard let id = ui.selectedClipID, let clip = selectedClip(), var spec = clip.title else { return }
        f(&spec)
        dispatch(.setTitle(id, spec))
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
        // 选中转场 → 删除 = 把 crossfade 归零(移除转场,不删片段)。
        if let tid = ui.selectedTransitionClipID {
            if let idx = TimelineGeometry.spineIndex(ofClipID: tid, in: document.sequence) {
                dispatch(.setCrossfade(at: idx, duration: .zero))
            }
            dispatch(.selectTransition(nil)); return
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
