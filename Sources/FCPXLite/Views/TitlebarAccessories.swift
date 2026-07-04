import SwiftUI
import AppKit

/// 标题栏(NSToolbar .unified 那条高 bar)里的按钮:面板切换组 + 导出。
/// 由 AppDelegate 的 NSToolbarDelegate 各包成 NSToolbarItem(自定义 view)放到右侧。

/// 三个面板切换按钮(素材库/检查器/Agent)。激活=蓝底亮图标,未激活=暗图标。
struct TitlebarToggleGroup: View {
    let store: DocumentStore
    var body: some View {
        HStack(spacing: 0) {
            btn(active: store.ui.showBrowser, help: t("素材库(左)")) {
                store.dispatch(.setShowBrowser(!store.ui.showBrowser))
            } icon: { LibraryToggleIcon(color: $0) }
            divider
            btn(active: store.ui.showInspector, help: t("检查器(右)⌘4")) {
                store.dispatch(.setInspector(!store.ui.showInspector))
            } icon: { InspectorToggleIcon(color: $0) }
            divider
            btn(active: store.ui.showChat, help: t("Agent 面板(右)")) {
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
        .buttonStyle(.plain).help(t("导出(⌘E)"))
    }
}

/// 语言切换器(顶栏右侧)。启用语言 ≤2 → toggle(显示当前短码,点击切下一个);>2 → 下拉菜单。
struct LanguageSwitcher: View {
    let i18n = Localization.shared
    var body: some View {
        Group {
            if i18n.enabledLanguages.count > 2 {
                Menu {
                    ForEach(i18n.enabledLanguages) { lang in
                        Button { i18n.language = lang } label: {
                            if lang == i18n.language { Label(lang.nativeName, systemImage: "checkmark") }
                            else { Text(lang.nativeName) }
                        }
                    }
                } label: {
                    Text(i18n.language.shortCode)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Palette.textIcon)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .frame(height: 28).padding(.horizontal, 4)
                .background(Tokens.Palette.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.Palette.divider, lineWidth: 1))
                .help(t("界面语言"))
            } else {
                Button { i18n.toggle() } label: {
                    Text(i18n.language.shortCode)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.Palette.textIcon)
                        .frame(width: 34, height: 28)
                        .background(Tokens.Palette.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Tokens.Palette.divider, lineWidth: 1))
                }
                .buttonStyle(.plain).help(t("界面语言"))
            }
        }
    }
}
