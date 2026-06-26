import SwiftUI

struct TimelineToolbar: View {
    let store: DocumentStore

    var body: some View {
        HStack(spacing: 0) {
            editButtons
            Spacer()
            toolSelector
            Spacer()
            zoomControls
        }
        .padding(.horizontal, 8)
        .frame(height: Tokens.Metric.timelineToolbarHeight)
        .background(Tokens.Palette.chrome)
    }

    // MARK: - Edit Buttons (Connect / Insert / Append / Overwrite)

    private var editButtons: some View {
        HStack(spacing: 2) {
            editButton(icon: ConnectIcon(), help: "连接到主情节 (Q)") {
                connectAction()
            }
            editButton(icon: InsertIcon(), help: "插入到播放头处 (W)") {
                insertAction()
            }
            editButton(icon: AppendIcon(), help: "追加到末尾 (E)") {
                appendAction()
            }
            editButton(icon: OverwriteIcon(), help: "覆盖 (D)") {
                // TODO Pass2: true overwrite semantics
                insertAction()
            }
        }
        .disabled(store.document.assetLibrary.isEmpty)
    }

    private func editButton<I: View>(icon: I, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .foregroundStyle(store.document.assetLibrary.isEmpty
                    ? Tokens.Palette.textMuted
                    : Tokens.Palette.textIcon)
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .help(help)
    }

    // MARK: - Edit Actions

    private func clipFromSelection() -> Clip? {
        // Use explicitly selected asset, else fall back to first in library
        let assetID: AssetID?
        if let sel = store.ui.selectedAssetID {
            assetID = sel
        } else {
            assetID = store.document.assetLibrary.first?.id
        }
        guard let id = assetID,
              let asset = store.document.assetLibrary.first(where: { $0.id == id }) else {
            return nil
        }
        return Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration)
    }

    private func appendAction() {
        guard let clip = clipFromSelection() else { return }
        store.dispatch(.insertClip(clip, at: store.document.sequence.spine.count))
    }

    private func insertAction() {
        guard let clip = clipFromSelection() else { return }
        let index = spineIndexAtPlayhead()
        store.dispatch(.insertClip(clip, at: index))
    }

    private func connectAction() {
        guard let clip = clipFromSelection() else { return }
        let hostIndex = spineIndexAtPlayhead()
        guard hostIndex < store.document.sequence.spine.count else {
            // No host clip exists — fall back to append
            store.dispatch(.insertClip(clip, at: store.document.sequence.spine.count))
            return
        }
        store.dispatch(.connect(clip, host: hostIndex, lane: 1, offset: .zero))
    }

    /// Returns the spine index of the clip that contains the playhead position.
    private func spineIndexAtPlayhead() -> Int {
        let playhead = store.ui.playhead
        var elapsed = Time.zero
        for (i, element) in store.document.sequence.spine.enumerated() {
            if case .clip(let c) = element {
                let end = elapsed + c.duration
                if playhead < end { return i }
                elapsed = end
            }
        }
        return store.document.sequence.spine.count
    }

    // MARK: - Tool Selector

    private var toolSelector: some View {
        Menu {
            ForEach(EditTool.allCases, id: \.self) { tool in
                Button {
                    store.dispatch(.setTool(tool))
                } label: {
                    HStack {
                        toolIcon(for: tool)
                            .foregroundStyle(Tokens.Palette.textIcon)
                        Text(tool.label)
                        Spacer()
                        Text(tool.shortcut)
                            .foregroundStyle(Tokens.Palette.textMuted)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                toolIcon(for: store.ui.currentTool)
                    .foregroundStyle(Tokens.Palette.textIcon)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Tokens.Palette.textMuted)
            }
            .frame(width: 40, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Zoom Controls

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                store.dispatch(.setZoom(store.ui.pxPerSecond / 1.5))
            } label: {
                Text("−")
                    .font(Tokens.Typeface.label)
                    .foregroundStyle(Tokens.Palette.textIcon)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .help("缩小时间线 (⌥−)")

            Text("\(Int(store.ui.pxPerSecond)) px/s")
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textMuted)
                .frame(width: 52)

            Button {
                store.dispatch(.setZoom(store.ui.pxPerSecond * 1.5))
            } label: {
                Text("+")
                    .font(Tokens.Typeface.label)
                    .foregroundStyle(Tokens.Palette.textIcon)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
            .help("放大时间线 (⌥+)")

            // Effects panel toggle (moved from old timelineToolbar)
            Button { store.dispatch(.setEffects(!store.ui.showEffects)) } label: {
                Text("▤▤")
                    .font(Tokens.Typeface.label)
            }
            .help("效果开关 ⌘5")
            .buttonStyle(.plain)
            .foregroundStyle(store.ui.showEffects ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
            .padding(.leading, 8)
        }
    }
}
