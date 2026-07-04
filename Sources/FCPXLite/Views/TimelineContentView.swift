import AppKit

/// AppKit 自定义画布:绘制标尺、片段、播放头;处理鼠标(选择/移动播放头/切割)、
/// 鼠标滚轮横向滚动、素材拖入。状态由 SwiftUI 通过 `apply(state:)` 推入,纯渲染。
///
/// 坐标:isFlipped = true,y 向下增长,标尺在顶部。x = 秒 * pxPerSecond。
final class TimelineContentView: NSView {

    // MARK: - 布局常量
    static let rulerHeight: CGFloat = 24
    static let laneHeight: CGFloat = 44
    static let laneGap: CGFloat = 4

    // MARK: - 注入状态(由 updateNSView 推入)
    private(set) var sequence = Sequence(spine: [])
    private(set) var assetLibrary: [Asset] = []
    private(set) var pxPerSecond: CGFloat = 60
    private(set) var playheadSeconds: Double = 0
    private(set) var selectedClipID: ClipID? = nil
    private(set) var selectedClipIDs: Set<ClipID> = []
    private(set) var selectedGapID: GapID? = nil
    private(set) var selectedTransitionClipID: ClipID? = nil
    private(set) var currentTool: EditTool = .select
    private(set) var snappingEnabled: Bool = true
    /// 主时间轴 skimming 开启态(由 apply 推入)。开→鼠标划过驱动 skimmer 线+预览。
    private(set) var timelineSkimming: Bool = false
    /// 是否正在播放(由 apply 推入)。播放优先级高于 skimming:播放中隐藏 skimmer、hover 不再 skim。
    private(set) var isPlaying: Bool = false
    /// 当前 skimmer 竖线的 x(画布坐标,nil=无)。纯本地状态,由 mouseMoved 驱动、定向失效重画。
    var skimmerX: CGFloat? = nil
    /// clip 条高度(可调)与 画面/波形 占比(filmstrip 占上方比例)。
    private(set) var laneH: CGFloat = 72
    private(set) var vaRatio: CGFloat = 0.6

    /// dispatch 闭包,避免对 store 的强引用环;由 representable 注入。
    var dispatch: ((EditorAction) -> Void)?
    /// 拖拽实时编辑(slip/slide):firstTick=true 压一次撤销,transform 从拖拽起点序列重算。
    var dragEdit: ((Bool, @escaping (Sequence) -> Sequence) -> Void)?
    /// 拖拽手势级撤销合并:手势内首次改动前调 begin(快照一次+进入合并态),mouseUp 调 end。
    var beginInteractiveEdit: (() -> Void)?
    var endInteractiveEdit: (() -> Void)?
    /// 本次手势是否已 begin 过(保证一次手势只快照一次)。
    var didBeginInteractive = false

    // MARK: - 拖动片段状态(Pass 2)
    /// 正在拖动的片段 id(nil = 未拖动 / 在擦洗播放头)。
    var dragClipID: ClipID?
    /// 光标相对该片段起点的 x 偏移(像素),保证拖动时片段不"跳"。
    var dragGrabDX: CGFloat = 0
    /// 鼠标按下时的起点(用于判断是否构成"真拖动")。
    var dragStartPoint: NSPoint?
    /// 当前光标位置(画布坐标),draw 用它画 ghost。
    var dragCurrentPoint: NSPoint?
    /// 超过此像素位移才算真拖动,避免误把"点选"当成微移。
    static let dragThresholdPx: CGFloat = 3

    // MARK: - 工具拖拽状态(D)
    enum TrimEdge { case head, tail }
    /// 修剪工具:正在拖的 clip 边缘。grabDX = 抓取点与边缘的 x 偏移(保持"指哪打哪",边缘不跳到光标中心)。
    /// orig* = 拖拽起点的该 clip 绝对起点/入点/时长 —— 头部 trim 用它算【绝对目标】,避免逐 tick 累积(反向/跑飞)。
    var trimDrag: (clipID: ClipID, index: Int, edge: TrimEdge, grabDX: CGFloat,
                   origStart: Double, origSourceIn: Double, origDuration: Double)?
    /// Roll 编辑:select 工具 + ⌥ 拖两片段交界切点。orig* = 拖拽起点两侧入点/时长(绝对重算,不累积)。
    var rollDrag: (leftIndex: Int, rightIndex: Int, leftClipID: ClipID, rightClipID: ClipID, startX: CGFloat,
                   origLeftSourceIn: Double, origLeftDur: Double, origRightSourceIn: Double, origRightDur: Double)?
    /// Slip/Slide:修剪工具拖片段中段。slip 改入出点(不动位置时长);slide(⌥)移片段并调两侧。
    /// origin = 拖拽开始时的序列快照(每 tick 从 origin 按总位移重算,不累积);firstTick 决定是否压一次撤销。
    var slipDrag: (index: Int, startX: CGFloat, isSlide: Bool, origin: Sequence, firstTick: Bool)?
    /// Gap 拖动:移动整个 gap(记 id + 抓取偏移)。
    var dragGapID: GapID?
    var dragGapGrabDX: CGFloat = 0
    /// Gap 修剪:拖 gap 边缘改时长。
    var gapTrim: (gapID: GapID, edge: TrimEdge, startSec: Double)?
    /// 手工具:上一次拖动 x(用于滚动增量)。
    var handLastX: CGFloat?
    /// 缩放工具:拖动起点 x + 起始 pxPerSecond。
    var zoomStartX: CGFloat?
    var zoomStartPx: CGFloat = 60
    /// 转场调宽:拖转场边缘改 crossfadeIn 时长。seamX=接缝位置,startDur=起始时长。
    var transitionDrag: (clipIndex: Int, seamX: CGFloat, startDur: Double)?
    /// 连接片段(字幕/连接音频)边缘 trim:拖首/尾改时长(不走主轴 ripple)。
    var connTrimDrag: (clipID: ClipID, edge: TrimEdge, grabDX: CGFloat)?
    /// 框选(marquee):空白处按下拖拽,框内片段/字幕批量选中。start/current = 画布坐标。
    var marqueeStart: NSPoint?
    var marqueeCurrent: NSPoint?
    /// 在播放头线上按下拖拽 = 擦洗播放头(空白处拖则是框选)。
    var scrubbingPlayhead = false
    /// 边缘命中阈值(像素)。
    static let edgeHitPx: CGFloat = 6

    /// 派生:当前布局。按 sequenceVersion 缓存 —— 一次拖拽 tick 内 draw + 多次命中测试复用一次 Layout.compute。
    var placed: [Placed] {
        if let c = placedCache, c.version == sequenceVersion { return c.value }
        let v = Layout.compute(sequence)
        placedCache = (sequenceVersion, v)
        return v
    }
    private var placedCache: (version: Int, value: [Placed])?
    /// sequence 实际变化时(在 apply 里)bump,使 placed 缓存失效。
    private(set) var sequenceVersion = 0
    /// assetLibrary 变化时(在 apply 里)bump,使 assetMap 缓存失效。
    private(set) var assetVersion = 0

    /// clipID → Clip(主轴+连接子项)映射,按 sequenceVersion 缓存。draw/命中测试 O(1) 取 clip,
    /// 消除逐 clip 全 spine 扫描的 O(N²)(drawClip/clipLabel/转场/音量命中共用)。
    var clipMap: [ClipID: Clip] {
        if let c = clipMapCache, c.version == sequenceVersion { return c.value }
        var m: [ClipID: Clip] = [:]
        for el in sequence.spine {
            if case .clip(let c) = el { m[c.id] = c; for ch in c.connected { m[ch.id] = ch } }
        }
        clipMapCache = (sequenceVersion, m)
        return m
    }
    private var clipMapCache: (version: Int, value: [ClipID: Clip])?

    /// assetID → Asset 映射,按 assetVersion 缓存。取代散布的 assetLibrary.first{...} 线性查找。
    var assetMap: [AssetID: Asset] {
        if let c = assetMapCache, c.version == assetVersion { return c.value }
        var m: [AssetID: Asset] = [:]
        for a in assetLibrary { m[a.id] = a }
        assetMapCache = (assetVersion, m)
        return m
    }
    private var assetMapCache: (version: Int, value: [AssetID: Asset])?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
        TimelineMediaCache.shared.onUpdate = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    #if DEBUG
    /// 几何自省(供 DebugControlServer /layout 用):暴露画布真实尺寸与各 clip rect,便于自动化诊断渲染。
    func debugGeometryJSON() -> [String: Any] {
        var clips: [[String: Any]] = []
        for p in placed {
            let r = clipRect(p)
            clips.append(["lane": p.lane, "connected": p.isConnected,
                          "x": Double(r.minX), "y": Double(r.minY),
                          "w": Double(r.width), "h": Double(r.height)])
        }
        let lane0 = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                              laneHeight: laneH, laneGap: Self.laneGap,
                                              contentHeight: bounds.height)
        var gaps: [[String: Any]] = []
        var acc = Time.zero
        for el in sequence.spine {
            if case .gap(_, let d) = el {
                let x = TimelineGeometry.x(forSeconds: acc.seconds, pxPerSecond: pxPerSecond)
                let w = TimelineGeometry.x(forSeconds: d.seconds, pxPerSecond: pxPerSecond)
                gaps.append(["x": Double(x), "y": Double(lane0), "w": Double(w), "durationSec": d.seconds])
            }
            acc = acc + el.duration
        }
        return [
            "frameH": Double(frame.height), "boundsH": Double(bounds.height),
            "clipViewH": Double(enclosingScrollView?.contentView.bounds.height ?? -1),
            "scrollViewH": Double(enclosingScrollView?.bounds.height ?? -1),
            "rulerHeight": Double(Self.rulerHeight), "laneHeight": Double(laneH),
            "lane0TopY": Double(lane0), "clips": clips, "gaps": gaps
        ]
    }
    #endif

    // MARK: - 状态推入

    struct State {
        let sequence: Sequence
        let assetLibrary: [Asset]
        let pxPerSecond: CGFloat
        let playheadSeconds: Double
        let selectedClipID: ClipID?
        let selectedClipIDs: Set<ClipID>
        let selectedGapID: GapID?
        let selectedTransitionClipID: ClipID?
        let currentTool: EditTool
        let snappingEnabled: Bool
        let clipHeight: CGFloat
        let vaRatio: CGFloat
        let timelineSkimming: Bool
        let isPlaying: Bool
    }

    func apply(state: State) {
        // ---- 赋值前捕获旧值(供定向失效)----
        let oldPlayheadX = TimelineGeometry.x(forSeconds: playheadSeconds, pxPerSecond: pxPerSecond)
        let oldSelClipID = selectedClipID
        let oldSelClipIDs = selectedClipIDs
        let oldSelGap = selectedGapID
        let oldSelTrans = selectedTransitionClipID
        let oldTool = currentTool
        let oldSkimming = timelineSkimming
        let oldSelectionRect = selectionDirtyRect(selectionClipIDUnion(oldSelClipID, oldSelClipIDs))

        // ---- 结构/尺寸变化(需全画,不可避免)----
        let sequenceChanged = sequence != state.sequence
        let assetChanged = assetLibrary != state.assetLibrary
        let structuralChanged = sequenceChanged
            || pxPerSecond != state.pxPerSecond
            || laneH != state.clipHeight
            || vaRatio != state.vaRatio
            || assetChanged

        // ---- 赋值 ----
        sequence = state.sequence
        assetLibrary = state.assetLibrary
        pxPerSecond = state.pxPerSecond
        playheadSeconds = state.playheadSeconds
        selectedClipID = state.selectedClipID
        selectedClipIDs = state.selectedClipIDs
        selectedGapID = state.selectedGapID
        selectedTransitionClipID = state.selectedTransitionClipID
        currentTool = state.currentTool
        snappingEnabled = state.snappingEnabled
        laneH = state.clipHeight
        vaRatio = state.vaRatio
        timelineSkimming = state.timelineSkimming
        isPlaying = state.isPlaying

        if sequenceChanged { sequenceVersion &+= 1; placedCache = nil }
        if assetChanged { assetVersion &+= 1 }
        // 关掉 skimming 或开始播放 → 清除 skimmer 竖线并擦除(rare event,全画可接受)。
        if (oldSkimming && !timelineSkimming) || isPlaying, skimmerX != nil {
            skimmerX = nil
            needsDisplay = true
        }
        // 工具切换 → 立即换光标(鼠标在视图内时马上生效,不等移动)。
        if oldTool != currentTool, let win = window {
            let mp = convert(win.mouseLocationOutsideOfEventStream, from: nil)
            if visibleRect.contains(mp) { cursorForPoint(mp).set() }
        }

        // ---- 定向失效 ----
        if structuralChanged { needsDisplay = true; return }   // 全画

        // gap/转场选择变化少见,算它们的 rect 易错 → 回退全画
        if oldSelGap != selectedGapID || oldSelTrans != selectedTransitionClipID {
            needsDisplay = true; return
        }

        var dirty: NSRect? = nil
        let newPlayheadX = TimelineGeometry.x(forSeconds: playheadSeconds, pxPerSecond: pxPerSecond)
        if oldPlayheadX != newPlayheadX {
            dirty = unionRect(dirty, playheadDirtyRect(oldX: oldPlayheadX, newX: newPlayheadX))
        }
        if oldSelClipID != selectedClipID || oldSelClipIDs != selectedClipIDs {
            dirty = unionRect(dirty, oldSelectionRect)
            dirty = unionRect(dirty, selectionDirtyRect(selectionClipIDUnion(selectedClipID, selectedClipIDs)))
        }
        if let d = dirty { setNeedsDisplay(d) }
        // 都没变(仅 tool/snapping)→ 不重画
    }


    // MARK: - 几何辅助

    func clipRect(_ p: Placed) -> NSRect {
        let x = TimelineGeometry.x(forSeconds: p.absStart.seconds, pxPerSecond: pxPerSecond)
        let w = max(2, TimelineGeometry.x(forSeconds: p.duration.seconds, pxPerSecond: pxPerSecond))
        let y = TimelineGeometry.laneTopY(lane: p.lane,
                                          rulerHeight: Self.rulerHeight,
                                          laneHeight: laneH,
                                          laneGap: Self.laneGap,
                                          contentHeight: bounds.height)
        return NSRect(x: x, y: y, width: w, height: laneH)
    }

    /// 命中测试:返回点中的 Placed(优先靠上的 lane / 先绘制的)。
    func hitTestClip(at point: NSPoint) -> Placed? {
        for p in placed where clipRect(p).contains(point) {
            return p
        }
        return nil
    }

    func clipLabel(for placed: Placed) -> String {
        guard let c = sequence.clip(id: placed.clipID) else { return "clip" }
        return assetFilename(c.assetID) ?? "clip"
    }

    private func assetFilename(_ id: AssetID) -> String? {
        guard let asset = assetMap[id] else { return nil }
        return asset.url.deletingPathExtension().lastPathComponent
    }

    static func timecode(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - 鼠标交互
    // mouseDown / mouseDragged / mouseUp(选择/拖动片段换轨/切割/擦洗播放头)在
    // TimelineContentView+Drag.swift 扩展里。

    // MARK: - 鼠标滚轮横向滚动

    override func scrollWheel(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else {
            super.scrollWheel(with: event)
            return
        }
        let clip = scrollView.contentView
        let visibleW = clip.bounds.width
        let contentW = bounds.width
        // 内容没溢出 → 交回默认处理
        guard contentW > visibleW else {
            super.scrollWheel(with: event)
            return
        }

        // 触控板横向(deltaX)优先保留默认行为
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event)
            return
        }

        // 普通鼠标滚轮:垂直 delta 翻译成横向滚动
        let dy = event.scrollingDeltaY
        let currentX = clip.bounds.origin.x
        var newX = currentX - dy
        newX = max(0, min(newX, contentW - visibleW))
        clip.scroll(to: NSPoint(x: newX, y: 0))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - 素材拖入

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: .string) else {
            return false
        }
        let assetID = AssetID(raw: raw)
        guard let asset = assetLibrary.first(where: { $0.id == assetID }) else {
            // fail-fast:看得见的问题,但不崩溃(拖入未知 id)
            print("[TimelineContentView] 未找到 assetID: \(raw)")
            return false
        }
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration)
        let index = TimelineGeometry.insertionIndex(forX: dropPoint.x,
                                                    sequence: sequence,
                                                    pxPerSecond: pxPerSecond)
        dispatch?(.insertClip(clip, at: index))
        return true
    }
}
