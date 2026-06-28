import AppKit
import ObjectiveC

/// 音量 level 线交互:
/// - select 工具下,优先于 clip-move 拦截
/// - Option+click → 添加关键帧
/// - 拖关键帧 → 改值/时间
/// - 拖线(无关键帧) → 改整段音量
/// - 拖 fade 手柄 → 改 fade inSeconds/outSeconds
extension TimelineContentView {

    // MARK: - 拖拽状态

    enum VolumeDragKind {
        case keyframe(ClipID, UUID)        // 拖某关键帧
        case wholeLine(ClipID)             // 拖整段 level 线(无关键帧)
        case fadeHandle(ClipID, isFadeIn: Bool) // 拖 fade 手柄
    }

    // 使用 associated state 存在 NSView 关联对象里(避免污染主类属性命名空间)
    private static var _volumeDragKey = "volumeDragState"

    struct VolumeDragState {
        var kind: VolumeDragKind
        var startPoint: NSPoint
        var startVolume: Double        // 拖线时初始 volume
        var startKeyframes: [VolumeKeyframe] // 拖关键帧时初始列表
        var startFadeSeconds: Double   // 拖 fade 手柄时初始秒数
    }

    var volumeDragState: VolumeDragState? {
        get { objc_getAssociatedObject(self, &Self._volumeDragKey) as? VolumeDragState }
        set { objc_setAssociatedObject(self, &Self._volumeDragKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // MARK: - 命中测试

    static let volumeHitPx: CGFloat = 8   // level 线 ±命中宽度
    static let kfHitPx: CGFloat = 8       // 关键帧圆点命中半径
    static let fadeHandleHitPx: CGFloat = 14 // fade 手柄命中宽度

    /// 返回在 audio region 内 level 线的 y 坐标(当前)。
    func levelLineY(for clip: Clip, in rect: NSRect) -> CGFloat? {
        guard let region = audioRegion(for: clip, in: rect) else { return nil }
        let sorted = clip.volumeKeyframes.sorted { $0.time < $1.time }
        if sorted.isEmpty {
            return volumeToY(volume: clip.adjust.volume, in: region)
        }
        // 近似:返回首关键帧 y(用于 hover 光标)
        return volumeToY(volume: sorted.first!.value, in: region)
    }

    /// 检查 pt 是否在某 clip 的关键帧圆点上,返回 (clipID, keyframeID)。
    func hitTestKeyframe(at pt: NSPoint) -> (ClipID, UUID)? {
        for p in placed {
            guard let clip = clipByID(p.clipID),
                  let asset = assetLibrary.first(where: { $0.id == clip.assetID }),
                  asset.hasAudio else { continue }
            let rect = clipRect(p)
            guard let region = audioRegion(for: clip, in: rect) else { continue }
            for kf in clip.volumeKeyframes {
                let x = kfX(time: kf.time, clipDuration: clip.duration, in: rect)
                let y = volumeToY(volume: kf.value, in: region)
                let dist = hypot(pt.x - x, pt.y - y)
                if dist <= Self.kfHitPx { return (clip.id, kf.id) }
            }
        }
        return nil
    }

    /// 检查 pt 是否在某 clip 的 level 线上(±volumeHitPx),返回 clipID。
    func hitTestLevelLine(at pt: NSPoint) -> ClipID? {
        for p in placed {
            guard let clip = clipByID(p.clipID),
                  let asset = assetLibrary.first(where: { $0.id == clip.assetID }),
                  asset.hasAudio else { continue }
            let rect = clipRect(p)
            guard let region = audioRegion(for: clip, in: rect) else { continue }
            guard region.contains(pt) else { continue }
            // 找 pt.x 对应的 level 线 y
            let lineY = levelLineYAtX(pt.x, clip: clip, rect: rect, region: region)
            if abs(pt.y - lineY) <= Self.volumeHitPx { return clip.id }
        }
        return nil
    }

    /// 检查 pt 是否在某 clip 的 fade 手柄上,返回 (clipID, isFadeIn)。
    func hitTestFadeHandle(at pt: NSPoint) -> (ClipID, Bool)? {
        for p in placed {
            guard let clip = clipByID(p.clipID),
                  let asset = assetLibrary.first(where: { $0.id == clip.assetID }),
                  asset.hasAudio else { continue }
            let rect = clipRect(p)
            guard let region = audioRegion(for: clip, in: rect) else { continue }
            // 左手柄 (淡入)
            let leftHitRect = NSRect(x: region.minX - 2, y: region.minY,
                                     width: Self.fadeHandleHitPx, height: region.height)
            if leftHitRect.contains(pt) { return (clip.id, true) }
            // 右手柄 (淡出)
            let rightHitRect = NSRect(x: region.maxX - Self.fadeHandleHitPx + 2, y: region.minY,
                                      width: Self.fadeHandleHitPx, height: region.height)
            if rightHitRect.contains(pt) { return (clip.id, false) }
        }
        return nil
    }

    /// 计算 level 线在给定 x 坐标处的 y 值。
    private func levelLineYAtX(_ x: CGFloat, clip: Clip, rect: NSRect, region: NSRect) -> CGFloat {
        let sorted = clip.volumeKeyframes.sorted { $0.time < $1.time }
        if sorted.isEmpty {
            return volumeToY(volume: clip.adjust.volume, in: region)
        }
        let durSecs = clip.duration.seconds
        guard durSecs > 0 else { return volumeToY(volume: sorted[0].value, in: region) }
        let frac = Double((x - rect.minX) / rect.width)
        let t = frac * durSecs
        // 找对应关键帧区间
        if t <= sorted[0].time.seconds {
            return volumeToY(volume: sorted[0].value, in: region)
        }
        if t >= sorted[sorted.count - 1].time.seconds {
            return volumeToY(volume: sorted[sorted.count - 1].value, in: region)
        }
        for i in 0..<(sorted.count - 1) {
            let k0 = sorted[i], k1 = sorted[i + 1]
            if t >= k0.time.seconds && t <= k1.time.seconds {
                let span = k1.time.seconds - k0.time.seconds
                guard span > 0 else { return volumeToY(volume: k0.value, in: region) }
                let alpha = (t - k0.time.seconds) / span
                let vol = k0.value + alpha * (k1.value - k0.value)
                return volumeToY(volume: vol, in: region)
            }
        }
        return volumeToY(volume: sorted[0].value, in: region)
    }

    // MARK: - mouseDown 拦截(select 工具)

    /// 在 mouseDown 的开头检查音量 level 线交互,返回 true 表示已拦截(调用方应 return)。
    func volumeMouseDown(with event: NSEvent, at pt: NSPoint) -> Bool {
        guard currentTool == .select else { return false }

        // 1. Option+click → 添加关键帧
        if event.modifierFlags.contains(.option) {
            if let lineClipID = hitTestLevelLine(at: pt) {
                volumeOptionClickAddKeyframe(at: pt, clipID: lineClipID)
                return true
            }
        }

        // 2. 关键帧圆点拖拽
        if let (clipID, kfID) = hitTestKeyframe(at: pt) {
            guard let clip = clipByID(clipID) else { return false }
            volumeDragState = VolumeDragState(
                kind: .keyframe(clipID, kfID),
                startPoint: pt,
                startVolume: clip.adjust.volume,
                startKeyframes: clip.volumeKeyframes,
                startFadeSeconds: 0
            )
            dispatch?(.selectClip(clipID))
            return true
        }

        // 3. Fade 手柄拖拽
        if let (clipID, isFadeIn) = hitTestFadeHandle(at: pt) {
            guard let clip = clipByID(clipID) else { return false }
            let fade = clip.effects.first { $0.enabled && $0.kind == .fade }
            let secs = isFadeIn
                ? (fade?.params["inSeconds"] ?? 0)
                : (fade?.params["outSeconds"] ?? 0)
            volumeDragState = VolumeDragState(
                kind: .fadeHandle(clipID, isFadeIn: isFadeIn),
                startPoint: pt,
                startVolume: clip.adjust.volume,
                startKeyframes: clip.volumeKeyframes,
                startFadeSeconds: secs
            )
            dispatch?(.selectClip(clipID))
            return true
        }

        // 4. Level 线整体拖拽(无关键帧)
        if let lineClipID = hitTestLevelLine(at: pt) {
            guard let clip = clipByID(lineClipID) else { return false }
            // 只在无关键帧时激活整体音量拖拽
            if clip.volumeKeyframes.isEmpty {
                volumeDragState = VolumeDragState(
                    kind: .wholeLine(lineClipID),
                    startPoint: pt,
                    startVolume: clip.adjust.volume,
                    startKeyframes: [],
                    startFadeSeconds: 0
                )
                dispatch?(.selectClip(lineClipID))
                return true
            }
        }

        return false
    }

    /// Option+click:在 level 线上添加关键帧。
    private func volumeOptionClickAddKeyframe(at pt: NSPoint, clipID: ClipID) {
        guard let clip = clipByID(clipID) else { return }
        guard let placedItem = placed.first(where: { $0.clipID == clipID }) else { return }
        let rect = clipRect(placedItem)
        guard let region = audioRegion(for: clip, in: rect) else { return }
        let durSecs = clip.duration.seconds
        guard durSecs > 0 else { return }
        let frac = Double(max(0, min(rect.maxX, pt.x)) - rect.minX) / Double(rect.width)
        let t = Time.seconds(max(0, min(durSecs, frac * durSecs)))
        let vol = yToVolume(y: pt.y, in: region)
        let newKF = VolumeKeyframe(time: t, value: vol)
        var kfs = clip.volumeKeyframes
        kfs.append(newKF)
        kfs.sort { $0.time < $1.time }
        dispatch?(.setVolumeKeyframes(clipID, kfs))
    }

    // MARK: - mouseDragged 拦截

    /// 在 mouseDragged 开头检查,返回 true 表示已拦截。
    func volumeMouseDragged(with event: NSEvent, at pt: NSPoint) -> Bool {
        guard let state = volumeDragState else { return false }
        switch state.kind {
        case let .keyframe(clipID, kfID):
            handleKeyframeDrag(at: pt, clipID: clipID, kfID: kfID, state: state)
            return true
        case let .wholeLine(clipID):
            handleWholeLineDrag(at: pt, clipID: clipID, state: state)
            return true
        case let .fadeHandle(clipID, isFadeIn):
            handleFadeHandleDrag(at: pt, clipID: clipID, isFadeIn: isFadeIn, state: state)
            return true
        }
    }

    private func handleKeyframeDrag(at pt: NSPoint, clipID: ClipID, kfID: UUID, state: VolumeDragState) {
        guard let clip = clipByID(clipID),
              let placedItem = placed.first(where: { $0.clipID == clipID }) else { return }
        let rect = clipRect(placedItem)
        guard let region = audioRegion(for: clip, in: rect) else { return }
        var kfs = state.startKeyframes
        guard let idx = kfs.firstIndex(where: { $0.id == kfID }) else { return }
        // 更新值
        kfs[idx].value = yToVolume(y: pt.y, in: region)
        // 更新时间(限在 clip 内)
        let durSecs = clip.duration.seconds
        let frac = Double(max(rect.minX, min(rect.maxX, pt.x)) - rect.minX) / Double(rect.width)
        kfs[idx].time = Time.seconds(max(0, min(durSecs, frac * durSecs)))
        // 保持排序(不改 id)
        kfs.sort { $0.time < $1.time }
        dispatch?(.setVolumeKeyframes(clipID, kfs))
    }

    private func handleWholeLineDrag(at pt: NSPoint, clipID: ClipID, state: VolumeDragState) {
        guard let clip = clipByID(clipID),
              let placedItem = placed.first(where: { $0.clipID == clipID }) else { return }
        let rect = clipRect(placedItem)
        guard let region = audioRegion(for: clip, in: rect) else { return }
        let newVol = yToVolume(y: pt.y, in: region)
        var adj = clip.adjust
        adj.volume = newVol
        dispatch?(.setAdjust(clipID, adj))
    }

    private func handleFadeHandleDrag(at pt: NSPoint, clipID: ClipID, isFadeIn: Bool, state: VolumeDragState) {
        guard let clip = clipByID(clipID),
              let placedItem = placed.first(where: { $0.clipID == clipID }) else { return }
        _ = clipRect(placedItem)  // rect used for bounds reference
        let clipDur = clip.duration.seconds
        // 拖拽距离(x)转换为秒数
        let dx = pt.x - state.startPoint.x
        let dSec = Double(dx) / Double(pxPerSecond)
        var newSec: Double
        if isFadeIn {
            newSec = max(0, min(clipDur, state.startFadeSeconds + dSec))
        } else {
            newSec = max(0, min(clipDur, state.startFadeSeconds - dSec))
        }
        // 更新 effects 中的 fade
        var effects = clip.effects
        if let i = effects.firstIndex(where: { $0.kind == .fade }) {
            if isFadeIn { effects[i].params["inSeconds"] = newSec }
            else { effects[i].params["outSeconds"] = newSec }
        } else {
            var fade = Effect.make(.fade)
            fade.params["inSeconds"] = isFadeIn ? newSec : 0
            fade.params["outSeconds"] = isFadeIn ? 0 : newSec
            effects.append(fade)
        }
        dispatch?(.setEffects(clipID, effects))
    }

    // MARK: - mouseUp 清理

    func volumeMouseUp() {
        volumeDragState = nil
    }

    // MARK: - resetCursorRects 扩展

    /// 为音频 clip 的 level 线区域添加 resizeUpDown 光标。
    func addVolumeLineCursorRects() {
        guard currentTool == .select else { return }
        for p in placed {
            guard let clip = clipByID(p.clipID),
                  let asset = assetLibrary.first(where: { $0.id == clip.assetID }),
                  asset.hasAudio else { continue }
            let rect = clipRect(p)
            guard let region = audioRegion(for: clip, in: rect) else { continue }
            // 在 audio region 中间 ±6px 横条添加 resizeUpDown 光标
            let midY = region.midY
            let stripH: CGFloat = 12
            let stripRect = NSRect(x: region.minX, y: midY - stripH/2,
                                   width: region.width, height: stripH)
            addCursorRect(stripRect, cursor: .resizeUpDown)
        }
    }
}
