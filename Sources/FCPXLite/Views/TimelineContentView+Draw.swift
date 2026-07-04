import AppKit

/// TimelineContentView 的绘制层:draw(_:) 及所有 draw* 方法(从主文件拆出,行数合规)。
extension TimelineContentView {
    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        TimelineColors.canvas.setFill()
        dirtyRect.fill()   // 只填脏区(其余绘制已被 AppKit 裁到 dirtyRect)

        drawMainLaneBand()
        drawGaps(dirty: dirtyRect)

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
        drawTransitions(dirty: dirtyRect)

        drawClipsOrHint()
        if currentTool == .position, dragClipID != nil { drawDragGhost() }   // 位置工具拖拽:画 ghost 跟随
        drawRuler(dirty: dirtyRect)      // 刻度尺最后画 → 永远在 clip 之上(拖高的 clip 不会盖住刻度)
        drawPlayhead()   // 播放头红线再压在刻度尺之上
        if timelineSkimming, let sx = skimmerX { drawSkimmer(at: sx) }   // skimmer 白线(高于播放头)
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
    func drawGaps(dirty: NSRect) {
        let y = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                          laneHeight: laneH, laneGap: Self.laneGap,
                                          contentHeight: bounds.height)
        var acc = Time.zero
        for el in sequence.spine {
            if case .gap(let gid, let d) = el {
                let x = TimelineGeometry.x(forSeconds: acc.seconds, pxPerSecond: pxPerSecond)
                let w = max(2, TimelineGeometry.x(forSeconds: d.seconds, pxPerSecond: pxPerSecond))
                let rect = NSRect(x: x, y: y, width: w, height: laneH)
                if rect.intersects(dirty) {   // 只画与脏区相交的 gap
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
            }
            acc = acc + el.duration
        }
    }

    /// 画交叉叠化转场标记:在带 crossfadeIn 的主轴片段【左接缝】处,跨缝画一块淡紫半透明区 + "蝴蝶结"叠化符号。
    /// 时间线仍按 Layout 顺铺(不重叠);标记只是提示该接缝有 dissolve,宽度=转场时长。
    func drawTransitions(dirty: NSRect) {
        let laneY = TimelineGeometry.laneTopY(lane: 0, rulerHeight: Self.rulerHeight,
                                              laneHeight: laneH, laneGap: Self.laneGap,
                                              contentHeight: bounds.height)
        for p in placed where p.lane == 0 {
            guard let clip = clipByID(p.clipID), clip.crossfadeIn > .zero else { continue }
            let seamX = clipRect(p).minX
            let rect = TimelineGeometry.transitionRect(seamX: seamX, crossfadeSecs: clip.crossfadeIn.seconds,
                                                       pxPerSecond: pxPerSecond, laneY: laneY, laneHeight: laneH)
            guard rect.intersects(dirty) else { continue }   // 只画与脏区相交的转场标记
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
        if let clip = clipByID(p.clipID), !clip.isTitle, assetMap[clip.assetID] == nil {
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
        if let clip = clipByID(p.clipID), let asset = assetMap[clip.assetID] {
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

    /// 取某 clip(主轴或连接子项)。O(1),走 clipMap 缓存。
    func clipByID(_ id: ClipID) -> Clip? { clipMap[id] }

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

    /// skimmer 竖线:白色 1px + 顶部小三角,压在播放头之上(FCP skimmer 是浅色,区别于红色播放头)。
    private func drawSkimmer(at x: CGFloat) {
        NSColor(calibratedWhite: 0.92, alpha: 0.95).setFill()
        NSRect(x: x - 0.5, y: 0, width: 1, height: bounds.height).fill()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: x - 4, y: 0))
        tri.line(to: NSPoint(x: x + 4, y: 0))
        tri.line(to: NSPoint(x: x, y: 7))
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
}
