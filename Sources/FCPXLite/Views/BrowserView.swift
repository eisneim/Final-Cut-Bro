import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BrowserView: View {
    let store: DocumentStore

    // strip 行高(像素):缩略图 + 波形;与缩放无关(缩放只改宽=时间密度)。
    private let bandH: CGFloat = 56
    private let spacing: CGFloat = 12   // 素材之间(含换行块之间)留大间距,同素材跨行紧贴=成组更明显
    private let pad: CGFloat = 6        // 素材池内边距
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
            store.importDroppedProviders(providers); return true
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
        let avail = max(minTile, CGFloat(store.ui.browserWidth) - pad * 2)
        let assets = store.document.assetLibrary
        let zoom = store.ui.assetStripZoom
        let widths = assets.map {
            AssetStripLayout.cellWidth(durationSecs: $0.duration.seconds, pxPerSecond: zoom,
                                       minTile: minTile, availWidth: avail)
        }
        let rowCounts = assets.map {
            AssetStripLayout.rowCount(durationSecs: $0.duration.seconds, pxPerSecond: zoom, availWidth: avail)
        }
        let rows = AssetStripLayout.flow(itemWidths: widths, availWidth: avail, spacing: spacing)
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row, id: \.self) { idx in
                        cell(assets[idx], width: widths[idx], rows: rowCounts[idx])
                    }
                }
                .fixedSize(horizontal: true, vertical: false)   // 防止 SwiftUI 把单元格拉伸撑满行宽(吃掉 padding)
            }
        }
        .padding(pad)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ asset: Asset, width: CGFloat, rows: Int) -> some View {
        AssetStripCell(asset: asset, width: width, bandH: bandH, rows: rows,
                       selected: store.ui.selectedAssetIDs.contains(asset.id),
                       vaRatio: CGFloat(store.ui.videoAudioRatio),
                       onSkim: { secs in
                           if let s = secs { store.setSkim(asset.id, seconds: s) }
                           else { store.setSkim(nil, seconds: 0) }
                       })
            .contextMenu {
                let sel = store.ui.selectedAssetIDs
                if sel.count > 1 && sel.contains(asset.id) {
                    Button("删除 \(sel.count) 个素材", role: .destructive) {
                        store.removeAssets(sel)
                    }
                } else {
                    Button("删除素材", role: .destructive) {
                        store.dispatch(.removeAsset(asset.id))
                    }
                }
            }
            .onTapGesture {
                let mods = NSEvent.modifierFlags
                if mods.contains(.command) { store.dispatch(.toggleAssetSelected(asset.id)) }
                else if mods.contains(.shift) { store.dispatch(.selectAssetRange(asset.id)) }
                else { store.dispatch(.selectAsset(asset.id)) }
            }
            .draggable(asset.id.raw)   // 拖到时间线(与原网格一致)
    }
}

