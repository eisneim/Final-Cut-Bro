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
    private(set) var currentTool: EditTool = .select

    /// dispatch 闭包,避免对 store 的强引用环;由 representable 注入。
    var dispatch: ((EditorAction) -> Void)?

    /// 派生:当前布局
    private var placed: [Placed] { Layout.compute(sequence) }

    /// 派生:最大正向 lane(用于把主轴推到合适基线,给上方连接片段留空间)
    private var maxPositiveLanes: Int {
        max(0, placed.map { $0.lane }.max() ?? 0)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - 状态推入

    struct State {
        let sequence: Sequence
        let assetLibrary: [Asset]
        let pxPerSecond: CGFloat
        let playheadSeconds: Double
        let selectedClipID: ClipID?
        let currentTool: EditTool
    }

    func apply(state: State) {
        sequence = state.sequence
        assetLibrary = state.assetLibrary
        pxPerSecond = state.pxPerSecond
        playheadSeconds = state.playheadSeconds
        selectedClipID = state.selectedClipID
        currentTool = state.currentTool
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        TimelineColors.canvas.setFill()
        bounds.fill()

        drawRuler()

        let ps = placed
        if ps.isEmpty {
            drawEmptyHint()
        } else {
            for p in ps { drawClip(p) }
        }

        drawPlayhead()
    }

    private func drawRuler() {
        let h = Self.rulerHeight
        TimelineColors.chrome.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: h).fill()

        // 底部分隔线
        TimelineColors.divider.setFill()
        NSRect(x: 0, y: h - 1, width: bounds.width, height: 1).fill()

        let interval = TimelineGeometry.tickIntervalSeconds(pxPerSecond: pxPerSecond)
        guard interval > 0, pxPerSecond > 0 else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: TimelineColors.textMuted,
        ]

        var t = 0.0
        let maxSeconds = Double(bounds.width / pxPerSecond)
        while t <= maxSeconds {
            let x = TimelineGeometry.x(forSeconds: t, pxPerSecond: pxPerSecond)
            // 刻度线
            TimelineColors.textMuted.setFill()
            NSRect(x: x, y: h - 6, width: 1, height: 6).fill()
            // 标签
            let label = Self.timecode(seconds: t) as NSString
            label.draw(at: NSPoint(x: x + 3, y: 4), withAttributes: attrs)
            t += interval
        }
    }

    private func drawClip(_ p: Placed) {
        let rect = clipRect(p)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        TimelineColors.clipBlue.setFill()
        path.fill()

        // 顶部 1pt 边线
        TimelineColors.clipBlueEdge.setStroke()
        path.lineWidth = 1
        path.stroke()

        // 选中:2pt 橙色边框
        if p.clipID == selectedClipID {
            let sel = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            TimelineColors.selectBorder.setStroke()
            sel.lineWidth = 2
            sel.stroke()
        }

        // 标签
        let label = clipLabel(for: p) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: TimelineColors.textPrimary,
        ]
        let textRect = rect.insetBy(dx: 4, dy: 3)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: textRect).addClip()
        label.draw(at: NSPoint(x: textRect.minX, y: textRect.minY), withAttributes: attrs)
        NSGraphicsContext.current?.restoreGraphicsState()
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
                                          laneHeight: Self.laneHeight,
                                          laneGap: Self.laneGap,
                                          maxPositiveLanes: maxPositiveLanes)
        return NSRect(x: x, y: y, width: w, height: Self.laneHeight)
    }

    /// 命中测试:返回点中的 Placed(优先靠上的 lane / 先绘制的)。
    private func hitTestClip(at point: NSPoint) -> Placed? {
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

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
        let inRuler = pt.y < Self.rulerHeight

        if !inRuler, let p = hitTestClip(at: pt) {
            if currentTool == .blade, let spineIdx = TimelineGeometry.spineIndex(ofClipID: p.clipID, in: sequence) {
                // 切割:localTime = 点击秒 - 该 clip 起点秒
                let localT = max(0, t - p.absStart.seconds)
                dispatch?(.blade(at: spineIdx, localTime: Time.seconds(localT)))
            } else {
                dispatch?(.selectClip(p.clipID))
            }
            return
        }

        // 空白区或标尺 → 移动播放头
        dispatch?(.setPlayhead(Time.seconds(t)))
    }

    override func mouseDragged(with event: NSEvent) {
        // 拖动即擦洗播放头(片段拖动移动是 Pass 2)
        let pt = convert(event.locationInWindow, from: nil)
        let t = TimelineGeometry.seconds(forX: pt.x, pxPerSecond: pxPerSecond)
        dispatch?(.setPlayhead(Time.seconds(t)))
    }

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
