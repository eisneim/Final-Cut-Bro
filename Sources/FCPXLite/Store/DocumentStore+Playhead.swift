import Foundation

extension DocumentStore {
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

    /// 在播放头处切割主轴 clip(FCP: ⌘B)。skimming 时改在【skimmer(鼠标竖线)】处切割 —— 鼠标位置才是切点,不是红色播放头。
    func bladeAtPlayhead() {
        let playhead = Time.seconds(ui.timelineSkimSeconds ?? ui.playhead.seconds)
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
    func connectedPlacement(_ id: ClipID) -> (start: Time, duration: Time)? {
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
        // 片段:支持【多选批量删除】。连接片段按 id 删(顺序无关),主轴片段每次重新解析
        // 索引后 ripple 删(删一个会使后面索引移位),整批合成单次 undo。
        let ids = effectiveSelection()
        guard !ids.isEmpty else { return }
        transaction {
            for cid in ids where TimelineGeometry.spineIndex(ofClipID: cid, in: document.sequence) == nil {
                dispatch(.removeConnected(cid))            // 连接片段
            }
            var spineIDs = Array(ids).filter { TimelineGeometry.spineIndex(ofClipID: $0, in: document.sequence) != nil }
            while let cid = spineIDs.popLast() {
                if let idx = TimelineGeometry.spineIndex(ofClipID: cid, in: document.sequence) {
                    dispatch(.rippleDelete(at: idx))        // 主轴片段:重新解析索引再删
                }
            }
        }
        dispatch(.selectClips([], anchor: nil))
    }

    /// 从素材库批量删除素材(素材池右键"删除"支持多选),整批单次 undo。
    /// 时间线上引用被删素材的片段会标红"素材丢失"(不自动删除,保留 FCP 行为)。
    func removeAssets(_ ids: Set<AssetID>) {
        guard !ids.isEmpty else { return }
        transaction { for id in ids { dispatch(.removeAsset(id)) } }
    }

    func clipFromSelection() -> Clip? {
        let assetID = ui.selectedAssetID ?? document.assetLibrary.first?.id
        guard let id = assetID,
              let asset = document.assetLibrary.first(where: { $0.id == id }) else { return nil }
        return Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration)
    }

    // MARK: - 快速 trim 到播放头(⌥[ 裁当前片段头 / ⌥] 裁当前片段尾)

    /// ⌥[ : 裁头到播放头。选中的是【连接片段】(字幕/音乐)→ 裁它;否则裁光标所在主轴片段。
    func trimLeftOfPlayhead() {
        if let (clip, absStart) = selectedConnectedClip() {
            let deltaIn = ui.playhead.seconds - absStart.seconds
            guard deltaIn > 0, deltaIn < clip.duration.seconds else { return }
            let isMedia = clip.title == nil
            dispatch(.setConnectedTiming(clip.id,
                offset: .seconds(clip.offset.seconds + deltaIn),
                sourceIn: isMedia ? .seconds(clip.sourceIn.seconds + deltaIn) : nil,
                duration: .seconds(clip.duration.seconds - deltaIn)))
            return
        }
        guard let (i, clipStart, _) = clipAtPlayhead() else { return }
        let deltaIn = ui.playhead - clipStart    // 头部要去掉的时长 = 光标 − 片段起点
        guard deltaIn > .zero else { return }
        dispatch(.trimLeft(at: i, deltaIn: deltaIn))
    }

    /// ⌥] : 裁尾到播放头。选中的是【连接片段】→ 裁它;否则裁光标所在主轴片段。
    func trimRightOfPlayhead() {
        if let (clip, absStart) = selectedConnectedClip() {
            var newDur = ui.playhead.seconds - absStart.seconds
            guard newDur > 0.1 else { return }
            if clip.title == nil {   // 媒体:不超素材尾
                let assetDur = document.assetDuration(of: clip).seconds
                newDur = min(newDur, max(0.1, assetDur - clip.sourceIn.seconds))
            }
            dispatch(.setConnectedTiming(clip.id, offset: nil, sourceIn: nil, duration: .seconds(newDur)))
            return
        }
        guard let (i, clipStart, clip) = clipAtPlayhead() else { return }
        let newDur = ui.playhead - clipStart     // 新时长 = 光标 − 片段起点
        guard newDur > .zero else { return }
        let assetDur = document.assetDuration(of: clip)
        dispatch(.trimRight(at: i, newDuration: newDur, assetDuration: assetDur))
    }

    /// 选中的是连接片段则返回(clip, 绝对起点);否则 nil。
    func selectedConnectedClip() -> (clip: Clip, absStart: Time)? {
        guard let id = ui.selectedClipID,
              TimelineGeometry.spineIndex(ofClipID: id, in: document.sequence) == nil,  // 主轴里没有 = 连接
              let clip = selectedClip(), let absStart = clipAbsStart(id) else { return nil }
        return (clip, absStart)
    }

    /// 找到光标所在的主轴片段(spine 下标、绝对起点、clip)。光标不在任何片段内返回 nil。
    func clipAtPlayhead() -> (index: Int, start: Time, clip: Clip)? {
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

    func spineIndexAtPlayhead() -> Int {
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
