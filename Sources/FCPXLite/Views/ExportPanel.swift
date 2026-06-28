// Sources/FCPXLite/Views/ExportPanel.swift
import SwiftUI
import AppKit

/// 导出对话框(双 Tab):导出视频(分辨率/编码/质量/音频) / 导出工程(FCPXML)。
struct ExportPanel: View {
    let store: DocumentStore
    @State private var tab: Int = 0
    @State private var settings = ExportSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("导出").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Button { store.dispatch(.setShowExport(false)) } label: {
                    Image(systemName: "xmark").foregroundStyle(Tokens.Palette.textMuted)
                }.buttonStyle(.plain)
            }

            // Tab selector
            Picker("", selection: $tab) {
                Text("导出视频").tag(0)
                Text("导出工程").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 {
                videoExportTab
            } else {
                projectExportTab
            }
        }
        .padding(18).frame(width: 380).background(Tokens.Palette.chrome)
    }

    // MARK: - Tab 0: Video Export

    @ViewBuilder private var videoExportTab: some View {
        if let p = store.ui.exportProgress {
            VStack(alignment: .leading, spacing: 6) {
                Text("导出中… \(Int(p * 100))%")
                    .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                ProgressView(value: p)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Resolution
                HStack {
                    Text("分辨率").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.resolution) {
                        ForEach(ExportResolution.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }

                // Codec
                HStack {
                    Text("编码").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.codec) {
                        ForEach(ExportCodec.allCases, id: \.self) { c in
                            Text(c.label).tag(c)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }

                // Quality (disabled for ProRes)
                HStack {
                    Text("质量").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Picker("", selection: $settings.quality) {
                        ForEach(ExportQuality.allCases, id: \.self) { q in
                            Text(q.label).tag(q)
                        }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                    .disabled(settings.codec == .prores)
                    .opacity(settings.codec == .prores ? 0.4 : 1.0)
                }

                // Audio toggle
                HStack {
                    Text("包含音频").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Toggle("", isOn: $settings.includeAudio).labelsHidden()
                    Spacer()
                }

                // Export button
                Button("导出…") { exportVideo() }
                    .buttonStyle(.plain).padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Tokens.Palette.clipBlue).cornerRadius(6)
                    .foregroundStyle(Tokens.Palette.onAccent)
                    .font(Tokens.Typeface.body)

                // Error
                if let err = store.ui.exportError {
                    Text(err).font(.system(size: 11))
                        .foregroundStyle(Tokens.Palette.windowClose)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Tab 1: Project Export

    @ViewBuilder private var projectExportTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("导出 FCPXML 工程文件,可在 Final Cut Pro 中继续编辑。")
                .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("导出 FCPXML 工程…") { exportFCPXML() }
                .buttonStyle(.plain).padding(8)
                .frame(maxWidth: .infinity)
                .background(Tokens.Palette.elevated).cornerRadius(6)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .font(Tokens.Typeface.body)
            if let err = store.ui.exportError {
                Text(err).font(.system(size: 11))
                    .foregroundStyle(Tokens.Palette.windowClose)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func exportVideo() {
        let ext = settings.codec == .prores ? "mov" : "mp4"
        let base = store.document.currentProject?.name ?? "导出"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(base).\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            store.exportMovie(to: url, settings: settings)
        }
    }

    private func exportFCPXML() {
        let base = store.document.currentProject?.name ?? "导出"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(base).fcpxml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportFCPXML(to: url)
            store.ui.exportError = nil
            store.dispatch(.setShowExport(false))
        } catch {
            store.ui.exportError = "导出失败:\(error)"   // fail-fast: 暴露而非静默
        }
    }
}
