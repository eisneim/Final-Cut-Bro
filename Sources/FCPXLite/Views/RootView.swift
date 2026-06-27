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
            timelineResizeHandle
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
            .frame(height: store.ui.timelineHeight)
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

    private var timelineResizeHandle: some View {
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
                        // 捕获起始高度,基于它累加,避免对“已更新高度”二次累加导致过冲
                        if dragStartHeight == nil { dragStartHeight = store.ui.timelineHeight }
                        let base = dragStartHeight ?? store.ui.timelineHeight
                        // 向上拖(translation.height 为负)增高
                        store.dispatch(.setTimelineHeight(base - drag.translation.height))
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }
}
