import SwiftUI
import AppKit

/// 标题栏(红黄绿交通灯那条)【右侧】配件:面板切换组 + 导出,挨在一起放在右上角。
/// 通过 NSTitlebarAccessoryViewController(.trailing)挂上去。

/// 右侧一整组:切换组 + 导出(切换组在左、导出在最右)。带上下留白让标题栏更高。
struct TitlebarTrailingControls: View {
    let store: DocumentStore
    var body: some View {
        HStack(spacing: 10) {
            TitlebarToggleGroup(store: store)
            TitlebarExportButton(store: store)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)          // 上下留白 → 标题栏更高、按钮不贴边
    }
}

/// 三个面板切换按钮(素材库/检查器/Agent)。激活=蓝底亮图标,未激活=暗图标。
struct TitlebarToggleGroup: View {
    let store: DocumentStore
    var body: some View {
        HStack(spacing: 0) {
            btn(active: store.ui.showBrowser, help: "素材库(左)") {
                store.dispatch(.setShowBrowser(!store.ui.showBrowser))
            } icon: { LibraryToggleIcon(color: $0) }
            divider
            btn(active: store.ui.showInspector, help: "检查器(右)⌘4") {
                store.dispatch(.setInspector(!store.ui.showInspector))
            } icon: { InspectorToggleIcon(color: $0) }
            divider
            btn(active: store.ui.showChat, help: "Agent 面板(右)") {
                store.dispatch(.setShowChat(!store.ui.showChat))
            } icon: { AgentToggleIcon(color: $0) }
        }
        .background(Tokens.Palette.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.Palette.divider, lineWidth: 1))
    }
    private var divider: some View { Rectangle().fill(Tokens.Palette.divider).frame(width: 1, height: 26) }
    private func btn<I: View>(active: Bool, help: String, action: @escaping () -> Void,
                              @ViewBuilder icon: (Color) -> I) -> some View {
        Button(action: action) {
            icon(active ? Tokens.Palette.textPrimary : Tokens.Palette.textMuted)
                .frame(width: 40, height: 28)
                .background(active ? Tokens.Palette.clipBlue : Color.clear)
        }
        .buttonStyle(.plain).help(help)
    }
}

/// 导出按钮。
struct TitlebarExportButton: View {
    let store: DocumentStore
    var body: some View {
        Button { store.dispatch(.setShowExport(true)) } label: {
            ExportToolbarIcon(color: Tokens.Palette.textIcon)
                .frame(width: 34, height: 28)
                .background(Tokens.Palette.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.Palette.divider, lineWidth: 1))
        }
        .buttonStyle(.plain).help("导出(⌘E)")
    }
}
