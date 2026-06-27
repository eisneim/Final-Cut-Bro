import SwiftUI

struct TimelineToolbar: View {
    let store: DocumentStore

    var body: some View {
        HStack(spacing: 8) {
            // 左:标题 + 动作按钮 + 工具下拉(全部靠左)
            Text("时间线").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
            editButtons
            toolSelector
            Spacer()
            // 右:缩放 + 效果开关
            zoomControls
            effectsToggle
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Tokens.Palette.chrome)
    }

    // MARK: - Edit Buttons (Connect / Insert / Append / Overwrite)

    private var editButtons: some View {
        HStack(spacing: 2) {
            editButton(icon: ConnectIcon(), help: "连接到主情节 (Q)") { store.connectAtPlayhead() }
            editButton(icon: InsertIcon(), help: "插入到播放头处 (W)") { store.insertAtPlayhead() }
            editButton(icon: AppendIcon(), help: "追加到末尾 (E)") { store.appendSelected() }
            editButton(icon: OverwriteIcon(), help: "覆盖 (D)") { store.overwriteAtPlayhead() }
        }
        .disabled(store.document.assetLibrary.isEmpty)
    }

    private func editButton<I: View>(icon: I, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .frame(width: 16, height: 16)
                .foregroundStyle(store.document.assetLibrary.isEmpty
                    ? Tokens.Palette.textMuted
                    : Tokens.Palette.textIcon)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .help(help)
    }

    // MARK: - Tool Selector

    private var toolSelector: some View {
        Menu {
            ForEach(EditTool.allCases, id: \.self) { tool in
                Button {
                    store.dispatch(.setTool(tool))
                } label: {
                    HStack {
                        toolIcon(for: tool).foregroundStyle(Tokens.Palette.textIcon)
                        Text(tool.label)
                        Spacer()
                        Text(tool.shortcut).foregroundStyle(Tokens.Palette.textMuted)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                toolIcon(for: store.ui.currentTool)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Tokens.Palette.textIcon)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Tokens.Palette.textMuted)
            }
            .frame(width: 38, height: 26)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { store.dispatch(.setZoom(store.ui.pxPerSecond / 1.5)) } label: {
                Text("−").font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textIcon)
            }
            .buttonStyle(.plain).frame(width: 22, height: 22).help("缩小 (⌘−)")

            Text("\(Int(store.ui.pxPerSecond)) px/s")
                .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted).frame(width: 52)

            Button { store.dispatch(.setZoom(store.ui.pxPerSecond * 1.5)) } label: {
                Text("+").font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textIcon)
            }
            .buttonStyle(.plain).frame(width: 22, height: 22).help("放大 (⌘+)")
        }
    }

    // MARK: - Effects toggle (最右)

    private var effectsToggle: some View {
        Button { store.dispatch(.setEffects(!store.ui.showEffects)) } label: {
            Text("▤▤").font(Tokens.Typeface.body)
        }
        .help("效果开关 ⌘5")
        .buttonStyle(.plain)
        .foregroundStyle(store.ui.showEffects ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
        .padding(.leading, 6)
    }
}
