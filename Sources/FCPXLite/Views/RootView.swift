import SwiftUI

struct RootView: View {
    let store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider().overlay(Tokens.Palette.divider)
            HStack(spacing: 0) {
                leftWorkspace
                ChatPanelView()
            }
        }
        .background(Tokens.Palette.chrome)
        .frame(minWidth: 1100, minHeight: 680)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(Tokens.Palette.windowClose).frame(width: 10, height: 10)
            Circle().fill(Tokens.Palette.windowMinimize).frame(width: 10, height: 10)
            Circle().fill(Tokens.Palette.windowZoom).frame(width: 10, height: 10)
            Spacer()
            Text("FCPX-lite").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
            Spacer()
            Button { store.dispatch(.setInspector(!store.ui.showInspector)) } label: { Text("≡|||") }
                .help("检查器开关 ⌘4")
                .buttonStyle(.plain)
                .foregroundStyle(store.ui.showInspector ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
        }
        .padding(.horizontal, 12).frame(height: Tokens.Metric.titlebarHeight)
        .background(Tokens.Palette.titlebar)
    }

    private var leftWorkspace: some View {
        VStack(spacing: 0) {
            PanelPlaceholder(title: "格式工具栏").frame(height: Tokens.Metric.toolbarHeight)
            Divider().overlay(Tokens.Palette.divider)
            HStack(spacing: 0) {
                PanelPlaceholder(title: "边栏").frame(width: 80)
                Divider().overlay(Tokens.Palette.divider)
                PanelPlaceholder(title: "资源管理器").frame(width: Tokens.Metric.browserWidth)
                Divider().overlay(Tokens.Palette.divider)
                PanelPlaceholder(title: "预览 Viewer", background: Tokens.Palette.canvas)
                if store.ui.showInspector {
                    Divider().overlay(Tokens.Palette.divider)
                    PanelPlaceholder(title: "检查器").frame(width: Tokens.Metric.inspectorWidth)
                }
            }
            timelineToolbar
            Divider().overlay(Tokens.Palette.divider)
            HStack(spacing: 0) {
                PanelPlaceholder(title: "磁性时间线", background: Tokens.Palette.canvas)
                if store.ui.showEffects {
                    Divider().overlay(Tokens.Palette.divider)
                    PanelPlaceholder(title: "效果/转场", background: Tokens.Palette.effectsPanel)
                        .frame(width: Tokens.Metric.effectsWidth)
                }
            }
            .frame(height: 200)
        }
    }

    private var timelineToolbar: some View {
        HStack {
            Text("索引 ✛⊟✄").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
            Button { store.dispatch(.setEffects(!store.ui.showEffects)) } label: { Text("▤▤") }
                .help("效果开关 ⌘5")
                .buttonStyle(.plain)
                .foregroundStyle(store.ui.showEffects ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
        }
        .padding(.horizontal, 12).frame(height: Tokens.Metric.timelineToolbarHeight)
        .background(Tokens.Palette.chrome)
    }
}
