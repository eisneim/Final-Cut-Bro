import SwiftUI
import AppKit

struct RootView: View {
    let store: DocumentStore
    @State private var dragStartHeight: Double?

    var body: some View {
        HStack(spacing: 0) {
            leftWorkspace
            WidthDragHandle(width: store.ui.chatWidth, sign: -1) {
                store.dispatch(.setPanelWidth(.chat, $0))
            }
            ChatPanelView(store: store).frame(width: store.ui.chatWidth)
        }
        .background(Tokens.Palette.chrome)
        .frame(minWidth: 1100, minHeight: 680)
    }

    private var leftWorkspace: some View {
        VStack(spacing: 0) {
            formatToolbar
            Divider().overlay(Tokens.Palette.divider)
            // 预览区 + 时间轴按比例分配可用高度,窗口缩放时两者联动(时间轴优先靠默认比例)。
            GeometryReader { geo in
                let avail = geo.size.height
                let timelineH = max(140, min(avail - 140, avail * store.ui.timelineFraction))
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        PanelPlaceholder(title: "边栏").frame(width: store.ui.sidebarWidth)
                        WidthDragHandle(width: store.ui.sidebarWidth, sign: 1) {
                            store.dispatch(.setPanelWidth(.sidebar, $0))
                        }
                        BrowserView(store: store).frame(width: store.ui.browserWidth)
                        WidthDragHandle(width: store.ui.browserWidth, sign: 1) {
                            store.dispatch(.setPanelWidth(.browser, $0))
                        }
                        ViewerView(store: store)
                        if store.ui.showInspector {
                            WidthDragHandle(width: store.ui.inspectorWidth, sign: -1) {
                                store.dispatch(.setPanelWidth(.inspector, $0))
                            }
                            InspectorView(store: store).frame(width: store.ui.inspectorWidth)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    timelineResizeHandle(availableHeight: avail)
                    TimelineToolbar(store: store)
                    Divider().overlay(Tokens.Palette.divider)
                    HStack(spacing: 0) {
                        TimelineView(store: store)
                        if store.ui.showEffects {
                            Divider().overlay(Tokens.Palette.divider)
                            PanelPlaceholder(title: "效果/转场", background: Tokens.Palette.effectsPanel)
                                .frame(width: Tokens.Metric.effectsWidth)
                        }
                    }
                    .frame(height: timelineH)
                }
            }
        }
    }

    // MARK: - Format Toolbar

    private var formatToolbar: some View {
        HStack(spacing: 12) {
            Text("所有片段 ⌄").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
            Text("1080p HD 25p,立体声").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
            Button { store.dispatch(.setInspector(!store.ui.showInspector)) } label: { Text("≡|||") }
                .help("检查器开关 ⌘4")
                .buttonStyle(.plain)
                .foregroundStyle(store.ui.showInspector ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
        }
        .padding(.horizontal, 12).frame(height: Tokens.Metric.toolbarHeight)
        .background(Tokens.Palette.chrome)
    }

    // MARK: - Resize Handle

    private func timelineResizeHandle(availableHeight: Double) -> some View {
        Rectangle()
            .fill(Tokens.Palette.divider)
            .frame(height: 4)
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        // 起始比例 → 起始高度 → 拖动累加 → 新比例。向上拖增高(translation.height<0)。
                        if dragStartHeight == nil { dragStartHeight = store.ui.timelineFraction * availableHeight }
                        let base = dragStartHeight ?? (store.ui.timelineFraction * availableHeight)
                        let newH = base - drag.translation.height
                        store.dispatch(.setTimelineFraction(availableHeight > 0 ? newH / availableHeight : 0.5))
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }
}
