import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BrowserView: View {
    let store: DocumentStore

    // Grid layout: 2 columns
    let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            browserHeader
            Divider().overlay(Tokens.Palette.divider)
            if store.document.assetLibrary.isEmpty {
                emptyState
            } else {
                assetGrid
            }
        }
        .background(Tokens.Palette.chrome)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Header

    private var browserHeader: some View {
        HStack(spacing: 8) {
            Text("片段 (\(store.document.assetLibrary.count))")
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textPrimary)
            Spacer()
            Button("导入") {
                ImportPanel.present(into: store)
            }
            .font(Tokens.Typeface.label)
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Palette.selectYellow)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Tokens.Palette.elevated)
            .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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

    // MARK: - Asset Grid

    private var assetGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.document.assetLibrary) { asset in
                    AssetCardView(asset: asset)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    store.ui.selectedAssetID == asset.id
                                        ? Tokens.Palette.selectYellow
                                        : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .onTapGesture {
                            store.dispatch(.selectAsset(asset.id))
                        }
                }
            }
            .padding(8)
        }
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

// MARK: - Asset Card

struct AssetCardView: View {
    let asset: Asset

    var body: some View {
        VStack(spacing: 4) {
            thumbnailView
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(asset.url.lastPathComponent)
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 100)

            Text(durationString(asset.duration))
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textMuted)
        }
        .padding(4)
        .background(Tokens.Palette.elevated)
        .cornerRadius(6)
        // Drag this card's AssetID onto the timeline
        .draggable(asset.id.raw)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if asset.kind == .audio {
            ZStack {
                Tokens.Palette.elevated
                VStack(spacing: 2) {
                    Text("♪")
                        .font(.system(size: 22))
                        .foregroundStyle(Tokens.Palette.waveform)
                    Text("音频")
                        .font(Tokens.Typeface.label)
                        .foregroundStyle(Tokens.Palette.textMuted)
                }
            }
        } else {
            ThumbnailView(asset: asset)
        }
    }

    private func durationString(_ t: Time) -> String {
        let total = Int(t.seconds)
        let mm = total / 60
        let ss = total % 60
        return String(format: "%d:%02d", mm, ss)
    }
}

// MARK: - Thumbnail (loads async)

struct ThumbnailView: View {
    let asset: Asset
    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Tokens.Palette.elevated
            }
        }
        .task(id: asset.id.raw) {
            let img = await Task.detached(priority: .utility) {
                MediaImporter.thumbnail(for: asset)
            }.value
            self.image = img
        }
    }
}
