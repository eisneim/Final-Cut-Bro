import SwiftUI
import AppKit

struct RootView: View {
    let store: DocumentStore
    @State private var dragStartHeight: Double?

    var body: some View {
        HStack(spacing: 0) {
            leftWorkspace
            if store.ui.showChat {
                WidthDragHandle(width: store.ui.chatWidth, sign: -1) {
                    store.dispatch(.setPanelWidth(.chat, $0))
                }
                ChatPanelView(store: store).frame(width: store.ui.chatWidth)
            }
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
        .sheet(isPresented: Binding(get: { store.ui.showSettings }, set: { store.dispatch(.setShowSettings($0)) })) {
            SettingsView(store: store)
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
                        if store.ui.showBrowser {
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
                                    WidthDragHandle(width: store.ui.effectsWidth, sign: -1) {
                                        store.dispatch(.setPanelWidth(.effects, $0))
                                    }
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
            // 左侧:面板切换组(素材库 / 检查器 / Agent),FCP 式分段容器
            panelToggleGroup
            Spacer()
            Text("1080p HD 25p,立体声").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
            // 右上角:导出
            Button { store.dispatch(.setShowExport(true)) } label: {
                ExportToolbarIcon(color: Tokens.Palette.textIcon)
                    .frame(width: 30, height: 30)
                    .background(Tokens.Palette.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.Palette.divider, lineWidth: 1))
            }
            .buttonStyle(.plain).help("导出(⌘E)")
        }
        .padding(.horizontal, 12).frame(height: Tokens.Metric.topBarHeight)
        .background(Tokens.Palette.chrome)
    }

    /// 三个面板切换按钮的分段容器(素材库 / 检查器 / Agent)。激活=蓝底亮图标,未激活=暗图标。
    private var panelToggleGroup: some View {
        HStack(spacing: 0) {
            toggleButton(active: store.ui.showBrowser, help: "素材库(左)") {
                store.dispatch(.setShowBrowser(!store.ui.showBrowser))
            } icon: { LibraryToggleIcon(color: $0) }
            groupDivider
            toggleButton(active: store.ui.showInspector, help: "检查器(右)⌘4") {
                store.dispatch(.setInspector(!store.ui.showInspector))
            } icon: { InspectorToggleIcon(color: $0) }
            groupDivider
            toggleButton(active: store.ui.showChat, help: "Agent 面板(右)") {
                store.dispatch(.setShowChat(!store.ui.showChat))
            } icon: { AgentToggleIcon(color: $0) }
        }
        .background(Tokens.Palette.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.Palette.divider, lineWidth: 1))
    }

    private var groupDivider: some View {
        Rectangle().fill(Tokens.Palette.divider).frame(width: 1, height: 30)
    }

    /// 单个切换按钮:激活时蓝底 + 亮图标,未激活透明 + 暗图标。
    private func toggleButton<I: View>(active: Bool, help: String, action: @escaping () -> Void,
                                       @ViewBuilder icon: (Color) -> I) -> some View {
        Button(action: action) {
            icon(active ? Tokens.Palette.textPrimary : Tokens.Palette.textMuted)
                .frame(width: 40, height: 30)
                .background(active ? Tokens.Palette.clipBlue : Color.clear)
        }
        .buttonStyle(.plain).help(help)
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
