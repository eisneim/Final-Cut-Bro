// Sources/FCPXLite/Views/ExportPanel.swift
import SwiftUI
import AppKit

/// 导出对话框:选格式(成片 mp4/m4a 或 fcpxml 工程)→ 选路径 → 导出(成片显示进度)。
struct ExportPanel: View {
    let store: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("导出").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Button { store.dispatch(.setShowExport(false)) } label: {
                    Image(systemName: "xmark").foregroundStyle(Tokens.Palette.textMuted)
                }.buttonStyle(.plain)
            }
            if let p = store.ui.exportProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("导出中… \(Int(p * 100))%").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                    ProgressView(value: p)
                }
            } else {
                Text("选择导出格式:").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                Button("导出成片(mp4 / m4a)…") { exportMovie() }
                    .buttonStyle(.plain).padding(8).background(Tokens.Palette.clipBlue).cornerRadius(6)
                    .foregroundStyle(Tokens.Palette.onAccent)
                Button("导出 FCPXML 工程…") { exportFCPXML() }
                    .buttonStyle(.plain).padding(8).background(Tokens.Palette.elevated).cornerRadius(6)
                    .foregroundStyle(Tokens.Palette.textPrimary)
            }
        }
        .padding(18).frame(width: 360).background(Tokens.Palette.chrome)
    }

    private func exportMovie() {
        let hasVideo = store.document.assetLibrary.contains { $0.kind != .audio }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = hasVideo ? "导出.mp4" : "导出.m4a"
        if panel.runModal() == .OK, let url = panel.url { store.exportMovie(to: url) }
    }

    private func exportFCPXML() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "导出.fcpxml"
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportFCPXML(to: url)
            store.dispatch(.setShowExport(false))
        }
    }
}
