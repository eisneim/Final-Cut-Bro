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
    /// clip 条高度(可调)与 画面/波形 占比(filmstrip 占上方比例)。
    private(set) var laneH: CGFloat = 72
    private(set) var vaRatio: CGFloat = 0.6

    /// dispatch 闭包,避免对 store 的强引用环;由 representable 注入。
    var dispatch: ((EditorAction) -> Void)?
    /// 拖拽实时编辑(slip/slide):firstTick=true 压一次撤销,transform 从拖拽起点序列重算。
    var dragEdit: ((Bool, @escaping (Sequence) -> Sequence) -> Void)?

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
    var trimDrag: (clipID: ClipID, index: Int, edge: TrimEdge, grabDX: CGFloat)?
    /// Roll 编辑:select 工具拖两片段交界切点。
    var rollDrag: (leftIndex: Int, rightIndex: Int, leftClipID: ClipID, rightClipID: ClipID, startX: CGFloat)?
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
    }

    func apply(state: State) {
        // ---- 赋值前捕获旧值(供定向失效)----
        let oldPlayheadX = TimelineGeometry.x(forSeconds: playheadSeconds, pxPerSecond: pxPerSecond)
        let oldSelClipID = selectedClipID
        let oldSelClipIDs = selectedClipIDs
        let oldSelGap = selectedGapID
        let oldSelTrans = selectedTransitionClipID
        let oldTool = currentTool
        let oldSelectionRect = selectionDirtyRect(selectionClipIDUnion(oldSelClipID, oldSelClipIDs))

        // ---- 结构/尺寸变化(需全画,不可避免)----
        let sequenceChanged = sequence != state.sequence
        let structuralChanged = sequenceChanged
            || pxPerSecond != state.pxPerSecond
            || laneH != state.clipHeight
            || vaRatio != state.vaRatio
            || assetLibrary != state.assetLibrary

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

        if sequenceChanged { sequenceVersion &+= 1; placedCache = nil }
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

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        TimelineColors.canvas.setFill()
        dirtyRect.fill()   // 只填脏区(其余绘制已被 AppKit 裁到 dirtyRect)

        drawMainLaneBand()
        drawGaps()

        let ps = placed
        if ps.isEmpty {
            drawEmptyHint()
        } else {
            // per-clip 裁剪:只重画与脏区相交的片段(省掉不可见片段的 filmstrip/波形构建)。
            for p in ps where clipRect(p).intersects(dirtyRect) {
                PerfProbe.shared.count("drawClip")
                drawClip(p)
            }
        }
        // 以下都保持无条件(靠 context 裁剪):转场标记会画到片段 rect 左侧之外、
        // ruler/播放头/框选跨全宽或钉顶,单独 cull 会留残影。
        drawTransitions()

        drawClipsOrHint()
        if currentTool == .position, dragClipID != nil { drawDragGhost() }   // 位置工具拖拽:画 ghost 跟随
        drawRuler(dirty: dirtyRect)      // 刻度尺最后画 → 永远在 clip 之上(拖高的 clip 不会盖住刻度)
        drawPlayhead()   // 播放头红线再压在刻度尺之上
        drawMarquee()    // 框选矩形压在最上层
    }

    /// 某 clip 是否被选中(单选 anchor 或框选多选集合)。
    func isSelected(_ id: ClipID) -> Bool {
        id == selectedClipID || selectedClipIDs.contains(id)
    }

    /// 框选进行中:画半透明矩形。
    private func drawMarquee() {
        guard let s = marqueeStart, let c = marqueeCurrent else { return }
        let rect = NSRect(x: min(s.x, c.x), y: min(s.y, c.y),
                          width: abs(c.x - s.x), height: abs(c.y - s.y))
        guard rect.width > 1 || rect.height > 1 else { return }
        TimelineColors.selectBorder.withAlphaComponent(0.15).setFill()
        rect.fill()
        let path = NSBezierPath(rect: rect)
        TimelineColors.selectBorder.setStroke(); path.lineWidth = 1; path.stroke()
    }

    private func drawClipsOrHint() {
        // bug4: 拖动改为所见即所得实时 relocate,不再画 ghost 分身。
        }

    /// 画主轴上的 .gap(位置工具留下的灰色占位):lane 0 上的灰条,可被修剪工具调长。
    func drawGaps() {
        let y = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                          laneHeight: laneH, laneGap: Self.laneGap,
                                          contentHeight: bounds.height)
        var acc = Time.zero
        for el in sequence.spine {
            if case .gap(let gid, let d) = el {
                let x = TimelineGeometry.x(forSeconds: acc.seconds, pxPerSecond: pxPerSecond)
                let w = max(2, TimelineGeometry.x(forSeconds: d.seconds, pxPerSecond: pxPerSecond))
                let rect = NSRect(x: x, y: y, width: w, height: laneH)
                let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
                TimelineColors.gapFill.setFill(); path.fill()
                TimelineColors.gapBorder.setStroke(); path.lineWidth = 1; path.stroke()
                // 选中的 gap:橙色 2pt 边框(像选中的 clip)
                if gid == selectedGapID {
                    let sel = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
                    TimelineColors.selectBorder.setStroke(); sel.lineWidth = 2; sel.stroke()
                }
                ("间隙" as NSString).draw(at: NSPoint(x: rect.minX + 4, y: rect.minY + 3),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 9),
                                     .foregroundColor: TimelineColors.textMuted])
            }
            acc = acc + el.duration
        }
    }

    /// 画交叉叠化转场标记:在带 crossfadeIn 的主轴片段【左接缝】处,跨缝画一块淡紫半透明区 + "蝴蝶结"叠化符号。
    /// 时间线仍按 Layout 顺铺(不重叠);标记只是提示该接缝有 dissolve,宽度=转场时长。
    func drawTransitions() {
        let laneY = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                              laneHeight: laneH, laneGap: Self.laneGap,
                                              contentHeight: bounds.height)
        for p in placed where p.lane == 0 {
            guard let clip = clipByID(p.clipID), clip.crossfadeIn > .zero else { continue }
            let seamX = clipRect(p).minX
            let rect = TimelineGeometry.transitionRect(seamX: seamX, crossfadeSecs: clip.crossfadeIn.seconds,
                                                       pxPerSecond: pxPerSecond, laneY: laneY, laneHeight: laneH)
            let selected = clip.id == selectedTransitionClipID
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            TimelineColors.transition.withAlphaComponent(selected ? 0.5 : 0.35).setFill(); path.fill()
            (selected ? TimelineColors.selectBorder : TimelineColors.transition.withAlphaComponent(0.9)).setStroke()
            path.lineWidth = selected ? 2 : 1; path.stroke()
            // 蝴蝶结(两个对顶三角)= 叠化符号
            let bow = NSBezierPath()
            let midY = rect.midY, h = min(rect.height * 0.4, 14)
            bow.move(to: NSPoint(x: rect.minX, y: midY - h/2))
            bow.line(to: NSPoint(x: rect.maxX, y: midY + h/2))
            bow.line(to: NSPoint(x: rect.maxX, y: midY - h/2))
            bow.line(to: NSPoint(x: rect.minX, y: midY + h/2))
            bow.close()
            TimelineColors.transition.withAlphaComponent(0.8).setStroke(); bow.lineWidth = 1; bow.stroke()
        }
    }

    /// lane 0 行底色:略深的全宽横条,让主时间线读起来稍暗。
    private func drawMainLaneBand() {
        let y = TimelineGeometry.laneTopY(lane: 0,
                                          rulerHeight: Self.rulerHeight,
                                          laneHeight: laneH,
                                          laneGap: Self.laneGap,
                                          contentHeight: bounds.height)
        TimelineColors.mainLaneBg.setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: laneH).fill()
    }

    /// 拖动时画半透明 ghost:x 吸附后位置,lane 由光标 y 决定,蓝底 0.5 alpha + 虚线框。
    private func drawDragGhost() {
        guard let id = dragClipID, let cur = dragCurrentPoint,
              let dragged = placed.first(where: { $0.clipID == id }) else { return }
        // 位置工具不吸附(鼠标指哪打哪);其它工具用吸附后的位置。
        let snappedT = currentTool == .position
            ? max(0, TimelineGeometry.seconds(forX: cur.x - dragGrabDX, pxPerSecond: pxPerSecond))
            : snappedTargetSeconds(forCursorX: cur.x)
        let lane = TimelineGeometry.lane(forY: cur.y,
                                         rulerHeight: Self.rulerHeight,
                                         laneHeight: laneH,
                                         laneGap: Self.laneGap,
                                         contentHeight: bounds.height)
        let x = TimelineGeometry.x(forSeconds: snappedT, pxPerSecond: pxPerSecond)
        let w = max(2, TimelineGeometry.x(forSeconds: dragged.duration.seconds, pxPerSecond: pxPerSecond))
        let y = TimelineGeometry.laneTopY(lane: lane,
                                          rulerHeight: Self.rulerHeight,
                                          laneHeight: laneH,
                                          laneGap: Self.laneGap,
                                          contentHeight: bounds.height)
        let rect = NSRect(x: x, y: y, width: w, height: laneH)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        TimelineColors.clipBlue.withAlphaComponent(0.5).setFill()
        path.fill()
        TimelineColors.selectBorder.setStroke()
        path.lineWidth = 1.5
        let dash: [CGFloat] = [4, 3]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.stroke()
    }

    private func drawRuler(dirty: NSRect) {
        let h = Self.rulerHeight
        // 钉在视口顶部:用可视区起点 y(竖滚后跟随),保证 ruler 永远在最上层、不被高 lane 的 clip 遮、也不滚走。
        let top = enclosingScrollView?.documentVisibleRect.minY ?? 0
        TimelineColors.chrome.setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: h).fill()

        // 底部分隔线
        TimelineColors.divider.setFill()
        NSRect(x: 0, y: top + h - 1, width: bounds.width, height: 1).fill()

        let interval = TimelineGeometry.tickIntervalSeconds(pxPerSecond: pxPerSecond)
        guard interval > 0, pxPerSecond > 0 else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: TimelineColors.textMuted,
        ]

        // 只画落在 dirty 横向范围内的刻度/标签 —— label.draw 的文字排版是 CPU 成本,
        // 全长 600+ 个标签即使被裁剪也要排版;按 dirty 裁剪后窄条重画只排几个。
        let xLo = dirty.minX - 48   // 左扩一个标签宽,避免边界标签缺半
        let xHi = dirty.maxX
        var t = 0.0
        let maxSeconds = Double(bounds.width / pxPerSecond)
        while t <= maxSeconds {
            let x = TimelineGeometry.x(forSeconds: t, pxPerSecond: pxPerSecond)
            if x >= xLo && x <= xHi {
                TimelineColors.textMuted.setFill()
                NSRect(x: x, y: top + h - 6, width: 1, height: 6).fill()
                let label = Self.timecode(seconds: t) as NSString
                label.draw(at: NSPoint(x: x + 3, y: top + 4), withAttributes: attrs)
            }
            t += interval
        }
    }

    /// 加入滚动视图后:监听滚动,让钉顶 ruler 跟随重绘。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }
    }
    /// 滚动:只失效【视口矩形】而非整块内容(整块=重画全部 200 片段 92ms)。
    /// draw 的 per-clip 裁剪把重画限制在视口内可见片段;ruler 钉在视口顶,随之重画。
    @objc private func scrolled() {
        setNeedsDisplay(enclosingScrollView?.documentVisibleRect ?? bounds)
    }

    private func drawClip(_ p: Placed) {
        let rect = clipRect(p)
        // 标题片段:画成【更矮】的紫色条(顶部对齐),显示文字 —— 像 FCP 的 title,不需要视频那么高。
        if let clip = clipByID(p.clipID), clip.isTitle {
            drawTitleClip(clip, in: rect, selected: isSelected(p.clipID))
            return
        }
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        TimelineColors.clipBlue.setFill()
        path.fill()

        // 裁剪到 clip 区域,画 filmstrip(上)+ 波形(下),按 vaRatio 分。
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        if let clip = clipByID(p.clipID), !clip.isTitle, assetLibrary.first(where: { $0.id == clip.assetID }) == nil {
            // 素材已从素材库删除 → 红色背景 + "素材丢失" 提示
            NSGraphicsContext.current?.restoreGraphicsState()
            NSColor.systemRed.withAlphaComponent(0.3).setFill(); path.fill()
            let miss = NSAttributedString(string: "素材丢失", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ])
            miss.draw(at: CGPoint(x: rect.minX + 6, y: rect.midY - 7))
            // 2pt 红色边框
            let red = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            NSColor.systemRed.setStroke(); red.lineWidth = 2; red.stroke()
            return
        }
        if let clip = clipByID(p.clipID), let asset = assetLibrary.first(where: { $0.id == clip.assetID }) {
            // 只显示本 clip 的源区间 [sourceIn, sourceIn+duration) 对应的那段缩略图/波形(blade 后各段不同)。
            let assetDur = max(0.0001, asset.duration.seconds)
            let f0 = max(0, min(1, clip.sourceIn.seconds / assetDur))
            let f1 = max(f0, min(1, (clip.sourceIn.seconds + clip.duration.seconds) / assetDur))
            let videoH = asset.hasAudio ? rect.height * vaRatio : rect.height
            let filmRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: videoH)
            let waveRect = NSRect(x: rect.minX, y: rect.minY + videoH, width: rect.width, height: rect.height - videoH)
            if asset.kind != .audio { drawFilmstrip(asset, in: filmRect, range: f0...f1) }
            if asset.hasAudio { drawWaveform(asset, in: asset.kind == .audio ? rect : waveRect, range: f0...f1) }
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        // 音量 level 线
        if let clip = clipByID(p.clipID) {
            drawVolumeLine(clip: clip, in: rect)
        }

        // 停用片段:盖一层暗色半透明遮罩(视觉变淡,表示不参与预览/导出)。
        if let clip = clipByID(p.clipID), !clip.enabled {
            NSColor.black.withAlphaComponent(0.55).setFill()
            path.fill()
        }

        // 顶部 1pt 边线
        TimelineColors.clipBlueEdge.setStroke(); path.lineWidth = 1; path.stroke()
        // 选中:2pt 橙色边框(单选 anchor 或框选多选集合)
        if isSelected(p.clipID) {
            let sel = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            TimelineColors.selectBorder.setStroke(); sel.lineWidth = 2; sel.stroke()
        }
        // 标签(顶部,半透明底)
        let label = clipLabel(for: p) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: TimelineColors.textPrimary,
        ]
        let textRect = rect.insetBy(dx: 4, dy: 3)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: textRect).addClip()
        NSColor.black.withAlphaComponent(0.35).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 14).fill()
        label.draw(at: NSPoint(x: textRect.minX, y: textRect.minY), withAttributes: attrs)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// 标题片段:矮条(顶部 ~40% 高度)+ 紫色 + 文字内容。lane>0 连接片段常见。
    static let titleBarHeight: CGFloat = 26
    private func drawTitleClip(_ clip: Clip, in rect: NSRect, selected: Bool) {
        let h = min(Self.titleBarHeight, rect.height)
        // 底部对齐:让矮标题条的【下边缘紧贴下层主轨道】(lane 槽的底=下一层顶),不再悬空。
        let bar = NSRect(x: rect.minX, y: rect.maxY - h, width: rect.width, height: h)
        let path = NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3)
        TimelineColors.transition.withAlphaComponent(0.85).setFill(); path.fill()
        TimelineColors.transition.setStroke(); path.lineWidth = 1; path.stroke()
        if selected {
            let sel = NSBezierPath(roundedRect: bar.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            TimelineColors.selectBorder.setStroke(); sel.lineWidth = 2; sel.stroke()
        }
        // 文字(标题内容)
        let text = (clip.title?.text ?? "标题") as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bar).addClip()
        // 图标 T + 文字
        ("T " as NSString).draw(at: NSPoint(x: bar.minX + 5, y: bar.minY + (h - 12) / 2),
                                withAttributes: [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: NSColor.white])
        text.draw(at: NSPoint(x: bar.minX + 18, y: bar.minY + (h - 12) / 2), withAttributes: attrs)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// 缩略图条:只取源区间 range(0..1)那一段的帧,按缩略图宽度平铺、每格采样不同帧。
    private func drawFilmstrip(_ asset: Asset, in r: NSRect, range: ClosedRange<Double>) {
        guard r.height > 2, r.width > 1 else { return }
        guard let all = TimelineMediaCache.shared.thumbnails(for: asset), !all.isEmpty else { return }
        // 切片宽按素材真实显示宽高比(naturalSize 已含方向),竖屏 → 窄切片排更多帧,不再横向拉伸。
        let ar = asset.naturalSize.height > 0 ? asset.naturalSize.width / asset.naturalSize.height : 16.0 / 9.0
        let thumbW = max(8, r.height * CGFloat(ar))
        let visible = max(1, Int(ceil(r.width / thumbW)))
        let lo = range.lowerBound, span = max(1e-6, range.upperBound - range.lowerBound)
        for i in 0..<visible {
            let frac = lo + span * (Double(i) + 0.5) / Double(visible)   // 映射到源区间内
            let img = all[min(all.count - 1, max(0, Int(frac * Double(all.count))))]
            let slice = NSRect(x: r.minX + CGFloat(i) * thumbW, y: r.minY, width: thumbW + 1, height: r.height)
            NSImage(cgImage: img, size: slice.size).draw(in: slice)
        }
    }

    /// 音频波形:只取源区间 range 对应的桶段,重采样到可见宽度(blade 后各段波形不同)。
    private func drawWaveform(_ asset: Asset, in r: NSRect, range: ClosedRange<Double>) {
        guard r.height > 2, r.width > 1 else { return }
        TimelineColors.elevated.withAlphaComponent(0.5).setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height).fill()
        guard let peaks = TimelineMediaCache.shared.waveform(for: asset), !peaks.isEmpty else { return }
        let mid = r.minY + r.height / 2
        let lo = Int(range.lowerBound * Double(peaks.count))
        let hi = max(lo + 1, Int(range.upperBound * Double(peaks.count)))

        // FCP 式实心填充波形:按设备像素步进采样,每步取该子区间的峰值,
        // 连成上包络(左→右)再下包络(右→左)闭合后 fill(),而非逐列描边(Retina 下会留缝=条形码)。
        let scale = max(1, window?.backingScaleFactor ?? 2)
        let step = 1.0 / scale                 // 每个设备像素一根采样
        let cols = max(1, Int(r.width * scale))
        let up = NSBezierPath()
        up.move(to: NSPoint(x: r.minX, y: mid))
        var topPoints: [NSPoint] = []
        for c in 0...cols {
            let frac = Double(c) / Double(cols)
            // 该屏列覆盖的源桶子区间 [a,b),取区间内最大峰值(包络),避免抽样漏掉瞬时峰。
            let a = lo + Int(frac * Double(hi - lo))
            let b = min(hi, max(a + 1, lo + Int((Double(c + 1) / Double(cols)) * Double(hi - lo))))
            var pk: Float = 0
            var i = min(peaks.count - 1, a)
            let end = min(peaks.count, b)
            while i < end { if peaks[i] > pk { pk = peaks[i] }; i += 1 }
            let h = CGFloat(pk) * (r.height / 2)
            let x = r.minX + CGFloat(c) * step
            up.line(to: NSPoint(x: x, y: mid + h))
            topPoints.append(NSPoint(x: x, y: mid - h))
        }
        // 下包络:从右往左闭合,形成实心区域。
        for p in topPoints.reversed() { up.line(to: p) }
        up.close()
        TimelineColors.waveform.setFill()
        up.fill()
    }

    /// 取某 clip(主轴或连接子项)。
    func clipByID(_ id: ClipID) -> Clip? {
        for el in sequence.spine {
            if case .clip(let c) = el {
                if c.id == id { return c }
                for ch in c.connected where ch.id == id { return ch }
            }
        }
        return nil
    }

    /// 取某 clip(主轴或连接子项)的 assetID。
    private func assetID(of id: ClipID) -> AssetID? {
        for el in sequence.spine {
            if case .clip(let c) = el {
                if c.id == id { return c.assetID }
                for ch in c.connected where ch.id == id { return ch.assetID }
            }
        }
        return nil
    }

    private func drawPlayhead() {
        let x = TimelineGeometry.x(forSeconds: playheadSeconds, pxPerSecond: pxPerSecond)
        TimelineColors.playheadRed.setFill()
        // 竖线 2pt,贯穿标尺+车道
        NSRect(x: x - 1, y: 0, width: 2, height: bounds.height).fill()
        // 顶部三角手柄
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: x - 5, y: 0))
        tri.line(to: NSPoint(x: x + 5, y: 0))
        tri.line(to: NSPoint(x: x, y: 8))
        tri.close()
        tri.fill()
    }

    private func drawEmptyHint() {
        let hint = "把素材从左侧拖到这里" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: TimelineColors.textMuted,
        ]
        let size = hint.size(withAttributes: attrs)
        let pt = NSPoint(x: (bounds.width - size.width) / 2,
                         y: (bounds.height - size.height) / 2)
        hint.draw(at: pt, withAttributes: attrs)
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

    private func clipLabel(for placed: Placed) -> String {
        for element in sequence.spine {
            if case .clip(let c) = element {
                if c.id == placed.clipID {
                    return assetFilename(c.assetID) ?? "clip"
                }
                for conn in c.connected where conn.id == placed.clipID {
                    return assetFilename(conn.assetID) ?? "clip"
                }
            }
        }
        return "clip"
    }

    private func assetFilename(_ id: AssetID) -> String? {
        guard let asset = assetLibrary.first(where: { $0.id == id }) else { return nil }
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
