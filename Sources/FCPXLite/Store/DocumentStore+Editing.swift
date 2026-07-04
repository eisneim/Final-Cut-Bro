import Foundation

extension DocumentStore {
    // MARK: - 高层编辑操作(工具栏按钮与键盘快捷键共用)

    /// 基于素材的分辨率/帧率新建项目 —— 保证项目格式与该素材完全一致(竖屏素材→竖屏项目)。
    /// 宽高向下取偶(项目格式要求 2 的倍数);帧率缺失/非法时回退 25。
    /// 新项目直接把该素材放到主轴上并切换过去,不必再手动加轨道。
    func createProject(fromAsset asset: Asset) {
        var w = max(2, Int(asset.naturalSize.width.rounded()))
        var h = max(2, Int(asset.naturalSize.height.rounded()))
        if w % 2 != 0 { w -= 1 }
        if h % 2 != 0 { h -= 1 }
        let fps = (asset.frameRate ?? 0) > 0 ? asset.frameRate! : 25
        let name = asset.url.deletingPathExtension().lastPathComponent
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration)
        let p = Project(name: name.isEmpty ? "未命名项目" : name,
                        formatWidth: w, formatHeight: h, frameRate: fps,
                        sequence: Sequence(spine: [.clip(clip)]))
        dispatch(.createProject(p))
        dispatch(.setPlayhead(.zero))
    }

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
    func addTitleAtPlayhead(text: String = "标题", duration: Time = .seconds(5)) -> ClipID {
        var spec = TitleSpec(); spec.text = text
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: duration, title: spec)
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

    /// 把素材源区间 [from,to] 作为片段追加到主时间线末尾,并把播放头移到该片段起点。
    /// 用于按 ASR 时间戳批量提取保留段拼成成片(不走 blade+delete,无时间漂移)。
    @discardableResult
    func appendSourceRange(assetID: AssetID, from: Double, to: Double) -> Double {
        let clip = Clip(assetID: assetID, sourceIn: .seconds(max(0, from)), duration: .seconds(max(0.01, to - from)))
        var acc = 0.0
        for el in document.sequence.spine { acc += el.duration.seconds }   // 新片段时间线起点
        dispatch(.insertClip(clip, at: document.sequence.spine.count))
        dispatch(.setPlayhead(.seconds(acc)))
        return acc
    }

    /// 改选中标题片段的规格(inspector / on-screen 编辑)。多选时对【全部选中的标题】施加同一闭包(单次 undo)。
    /// 同一闭包既支持绝对设值($0.fontSize = v → 全部设成 v),也支持相对增量($0.position.y += dy → 各自 bump)。
    func updateSelectedTitle(_ f: (inout TitleSpec) -> Void) {
        let titles = clipsByIDs(effectiveSelection()).filter { $0.clip.title != nil }
        guard !titles.isEmpty else { return }
        transaction {
            for (id, clip) in titles {
                guard var spec = clip.title else { continue }
                f(&spec)
                dispatch(.setTitle(id, spec))
            }
        }
    }

}
