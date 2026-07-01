import SwiftUI
import AppKit

/// NSViewRepresentable:NSScrollView(原生横向/纵向滚动)+ 自定义 TimelineContentView 画布。
/// 状态作为存储属性传入 → SwiftUI diff → 调 updateNSView 把状态推入画布并重画。
struct TimelineCanvas: NSViewRepresentable {
    let store: DocumentStore

    // 这些都作为存储属性,SwiftUI 会对它们 diff;变化即触发 updateNSView。
    let pxPerSecond: CGFloat
    let playheadSeconds: Double
    let selectedClipID: ClipID?
    let selectedClipIDs: Set<ClipID>
    let selectedGapID: GapID?
    let tool: EditTool
    let sequence: Sequence            // Equatable,内容变化即触发更新
    let assetLibrary: [Asset]
    let snappingEnabled: Bool
    let clipHeight: CGFloat
    let vaRatio: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = TimelineColors.canvas
        scrollView.horizontalScrollElasticity = .allowed

        let content = TimelineContentView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        content.dispatch = { [weak store] action in
            store?.dispatch(action)
        }
        content.dragEdit = { [weak store] firstTick, transform in
            store?.dragEdit(firstTick: firstTick, transform)
        }
        scrollView.documentView = content
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        PerfProbe.shared.measure("TimelineCanvas.updateNSView") {
            updateImpl(scrollView, context: context)
        }
    }

    private func updateImpl(_ scrollView: NSScrollView, context: Context) {
        guard let content = scrollView.documentView as? TimelineContentView else { return }

        content.apply(state: TimelineContentView.State(
            sequence: sequence,
            assetLibrary: assetLibrary,
            pxPerSecond: pxPerSecond,
            playheadSeconds: playheadSeconds,
            selectedClipID: selectedClipID,
            selectedClipIDs: selectedClipIDs,
            selectedGapID: selectedGapID,
            selectedTransitionClipID: store.ui.selectedTransitionClipID,
            currentTool: tool,
            snappingEnabled: snappingEnabled,
            clipHeight: clipHeight,
            vaRatio: vaRatio
        ))

        // 内容宽度 = max(可视宽, 总时长*px + 200);高度足够 ~7 条车道。
        let visibleWidth = scrollView.contentView.bounds.width
        let totalSeconds = Layout.compute(sequence)
            .map { ($0.absStart + $0.duration).seconds }
            .max() ?? 0
        let neededWidth = CGFloat(totalSeconds) * pxPerSecond + 200
        let width = max(visibleWidth, neededWidth)

        // 高度 = max(可视, 容纳所有 lane 所需);超过可视即可竖向滚动。lane 0 在内容里居中。
        let maxAbsLane = Layout.compute(sequence).map { abs($0.lane) }.max() ?? 0
        let needed = TimelineContentView.rulerHeight
            + CGFloat(2 * maxAbsLane + 1) * (clipHeight + TimelineContentView.laneGap)
            + clipHeight   // 上下各留一条余量
        let visibleHeight = scrollView.contentView.bounds.height
        let frameHeight = max(visibleHeight, needed)

        content.frame = NSRect(x: 0, y: 0, width: width, height: frameHeight)
        content.needsDisplay = true
    }
}

/// SwiftUI 入口。READ store 上被观察的字段(@Observable 据此跟踪并重渲染),
/// 把它们作为存储属性传给 TimelineCanvas,从而驱动 updateNSView。
/// 名称/签名保持 `TimelineView(store:)`,RootView 无需改动。
struct TimelineView: View {
    let store: DocumentStore

    var body: some View {
        TimelineCanvas(
            store: store,
            pxPerSecond: CGFloat(store.ui.pxPerSecond),
            playheadSeconds: store.ui.playhead.seconds,
            selectedClipID: store.ui.selectedClipID,
            selectedClipIDs: store.ui.selectedClipIDs,
            selectedGapID: store.ui.selectedGapID,
            tool: store.ui.currentTool,
            sequence: store.document.sequence,
            assetLibrary: store.document.assetLibrary,
            snappingEnabled: store.ui.snappingEnabled,
            clipHeight: CGFloat(store.ui.clipHeight),
            vaRatio: CGFloat(store.ui.videoAudioRatio)
        )
        .background(Tokens.Palette.canvas)
    }
}
