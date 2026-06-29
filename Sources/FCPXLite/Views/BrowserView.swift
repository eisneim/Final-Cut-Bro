import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BrowserView: View {
    let store: DocumentStore

    // strip 行高(像素):缩略图 + 波形;与缩放无关(缩放只改宽=时间密度)。
    private let bandH: CGFloat = 56
    private let spacing: CGFloat = 6
    private let minTile: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            browserHeader
            Divider().overlay(Tokens.Palette.divider)
            if store.document.assetLibrary.isEmpty {
                emptyState
            } else {
                stripFlow
            }
        }
        .background(Tokens.Palette.chrome)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Header(片段 N + 外观缩放 -/+ + 导入)

    private var browserHeader: some View {
        HStack(spacing: 8) {
            Text("片段 (\(store.document.assetLibrary.count))")
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textPrimary)
            // FCPX 式片段外观缩放:- 缩小成网格小方块,+ 放大成长胶片条
            HStack(spacing: 2) {
                zoomButton("minus", delta: 0.66, help: "缩小(更像网格)")
                zoomButton("plus", delta: 1.5, help: "放大(长胶片条)")
            }
            Spacer()
            Button("导入") { ImportPanel.present(into: store) }
                .font(Tokens.Typeface.label)
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Palette.selectYellow)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Tokens.Palette.elevated).cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func zoomButton(_ icon: String, delta: Double, help: String) -> some View {
        Button {
            store.dispatch(.setAssetStripZoom(store.ui.assetStripZoom * delta))
        } label: {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
                .foregroundStyle(Tokens.Palette.textCool)
                .frame(width: 20, height: 18)
                .background(Tokens.Palette.elevated).cornerRadius(4)
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("点击「导入」或\n从 Finder 拖入素材")
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Strip 流式布局(贪心换行,窗口不够宽就多行)

    private var stripFlow: some View {
        // 左侧栏宽度已知(browserWidth),不用 GeometryReader(它在 ScrollView 里会塌成 0 高)。
        let avail = max(minTile, CGFloat(store.ui.browserWidth) - 16)
        let assets = store.document.assetLibrary
        let widths = assets.map {
            AssetStripLayout.cellWidth(durationSecs: $0.duration.seconds,
                                       pxPerSecond: store.ui.assetStripZoom,
                                       minTile: minTile, availWidth: avail)
        }
        let rows = AssetStripLayout.flow(itemWidths: widths, availWidth: avail, spacing: spacing)
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { idx in
                        cell(assets[idx], width: widths[idx])
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ asset: Asset, width: CGFloat) -> some View {
        AssetStripCell(asset: asset, width: width, height: bandH,
                       selected: store.ui.selectedAssetIDs.contains(asset.id),
                       vaRatio: CGFloat(store.ui.videoAudioRatio))
            .onTapGesture {
                let mods = NSEvent.modifierFlags
                if mods.contains(.command) { store.dispatch(.toggleAssetSelected(asset.id)) }
                else if mods.contains(.shift) { store.dispatch(.selectAssetRange(asset.id)) }
                else { store.dispatch(.selectAsset(asset.id)) }
            }
            .draggable(asset.id.raw)   // 拖到时间线(与原网格一致)
    }

    // MARK: - Drop

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                Task { @MainActor in
                    do {
                        let asset = try MediaImporter.importAsset(from: url)
                        store.dispatch(.importAsset(asset))
                    } catch {
                        print("[BrowserView] 拖入导入失败: \(error)")
                    }
                }
            }
        }
    }
}

