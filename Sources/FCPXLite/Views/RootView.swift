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
        // 拖文件到窗口【任意处】即导入(不止素材池)。targeted 高亮可后续加。
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            store.importDroppedProviders(providers); return true
        }
        .sheet(isPresented: Binding(get: { store.ui.showExport }, set: { store.dispatch(.setShowExport($0)) })) {
            ExportPanel(store: store)
        }
        .sheet(isPresented: Binding(get: { store.ui.showProjectModal }, set: { store.dispatch(.setShowProjectModal($0)) })) {
            ProjectCreationModal(store: store)
        }
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
                        // 左侧栏:项目 + 素材池在同一个 ScrollView 里整体滚动(项目可有很多个)。
                        ScrollView {
                            VStack(spacing: 0) {
                                ProjectBar(store: store)
                                Divider().overlay(Tokens.Palette.divider)
                                BrowserView(store: store)
                            }
                        }
                        .frame(width: store.ui.browserWidth)
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
                    // 无项目 → 时间轴门控:灰色"先创建项目"。有项目 → 真时间轴。
                    Group {
                        if store.document.hasProject {
                            HStack(spacing: 0) {
                                TimelineView(store: store)
                                if store.ui.showEffects {
                                    Divider().overlay(Tokens.Palette.divider)
                                    EffectsPanel(store: store)
                                }
                            }
                        } else {
                            noProjectGate
                        }
                    }
                    .frame(height: timelineH)
                }
            }
        }
    }

    /// 无项目时的时间轴占位:灰底 + 创建项目按钮(没有刻度尺)。
    private var noProjectGate: some View {
        ZStack {
            Tokens.Palette.canvas
            Button { store.dispatch(.setShowProjectModal(true)) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                    Text("先创建一个项目")
                }
                .font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textMuted)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Tokens.Palette.elevated).cornerRadius(8)
            }
            .buttonStyle(.plain)
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
            Spacer().frame(width: 18)   // 导出按钮与检查器开关之间留空隙
            Button { store.dispatch(.setShowExport(true)) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("导出").font(Tokens.Typeface.label)
                }
                .foregroundStyle(Tokens.Palette.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Tokens.Palette.clipBlue).cornerRadius(6)
            }
            .buttonStyle(.plain).help("导出(⌘E)")
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
                // global 坐标系:手柄随时间轴高度变化而移动,local 坐标会反馈半速+残影。
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
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
