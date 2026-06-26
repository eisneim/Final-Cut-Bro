import SwiftUI

struct TimelineView: View {
    let store: DocumentStore
    let pxPerSecond: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            timelineHeader
            Divider().overlay(Tokens.Palette.divider)
            timelineCanvas
        }
        .background(Tokens.Palette.canvas)
    }

    // MARK: - Header (thin control bar)

    private var timelineHeader: some View {
        HStack(spacing: 8) {
            Text("主时间线")
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
            // Reliable delete button — fallback since SwiftUI onDeleteCommand is unreliable on macOS 14
            if store.ui.selectedClipID != nil {
                Button("✕ 删除选中") {
                    deleteSelected()
                }
                .font(Tokens.Typeface.label)
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Palette.selectYellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Tokens.Palette.elevated)
                .cornerRadius(4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Tokens.Palette.chrome)
        .frame(height: 24)
    }

    // MARK: - Canvas

    private var timelineCanvas: some View {
        GeometryReader { geo in
            let placed = Layout.compute(store.document.sequence)
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    Tokens.Palette.canvas

                    if placed.isEmpty {
                        emptyHint
                    }

                    ForEach(placed, id: \.clipID.raw) { p in
                        clipRect(p, containerHeight: geo.size.height)
                    }
                }
                .frame(width: max(geo.size.width, totalWidth(placed) + 200),
                       height: geo.size.height)
            }
        }
        .dropDestination(for: String.self) { items, location in
            handleDrop(assetIDRaws: items, at: location)
            return true
        }
        // macOS 14 keyboard delete via focused key handler — as a best-effort supplement to the button above
        .onDeleteCommand {
            deleteSelected()
        }
    }

    // MARK: - Clip Rect

    private let rowHeight: CGFloat = 40
    private let laneSpacing: CGFloat = 4
    private let mainLaneOffsetFromTop: CGFloat = 50   // leave room above for lane +1

    private func clipRect(_ p: Placed, containerHeight: CGFloat) -> some View {
        let x = CGFloat(p.absStart.seconds) * pxPerSecond
        let w = max(4, CGFloat(p.duration.seconds) * pxPerSecond)
        let yOffset = mainLaneOffsetFromTop - CGFloat(p.lane) * (rowHeight + laneSpacing)
        let isSelected = p.clipID == store.ui.selectedClipID

        let label = clipLabel(for: p)

        return RoundedRectangle(cornerRadius: 4)
            .fill(Tokens.Palette.clipBlue)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        isSelected ? Tokens.Palette.selectClipBorder : Tokens.Palette.clipBlueEdge,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .leading) {
                Text(label)
                    .font(Tokens.Typeface.label)
                    .foregroundStyle(Tokens.Palette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .frame(width: w, height: rowHeight)
            .offset(x: x, y: yOffset)
            .onTapGesture {
                store.dispatch(.selectClip(p.clipID))
            }
    }

    // MARK: - Empty State

    private var emptyHint: some View {
        HStack {
            Spacer()
            Text("把素材从左侧拖到这里")
                .font(Tokens.Typeface.body)
                .foregroundStyle(Tokens.Palette.textMuted)
            Spacer()
        }
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func totalWidth(_ placed: [Placed]) -> CGFloat {
        guard let last = placed.max(by: { ($0.absStart + $0.duration).seconds < ($1.absStart + $1.duration).seconds }) else {
            return 0
        }
        return CGFloat((last.absStart + last.duration).seconds) * pxPerSecond
    }

    private func clipLabel(for placed: Placed) -> String {
        // Look up asset via clip's assetID → get filename
        let assets = store.document.assetLibrary
        // Find the clip in the spine to get assetID
        for element in store.document.sequence.spine {
            if case .clip(let c) = element, c.id == placed.clipID {
                if let asset = assets.first(where: { $0.id == c.assetID }) {
                    return asset.url.deletingPathExtension().lastPathComponent
                }
                return "clip"
            }
            // Also check connected clips
            if case .clip(let c) = element {
                for conn in c.connected where conn.id == placed.clipID {
                    if let asset = assets.first(where: { $0.id == conn.assetID }) {
                        return asset.url.deletingPathExtension().lastPathComponent
                    }
                    return "clip"
                }
            }
        }
        return "clip"
    }

    private func deleteSelected() {
        guard let clipID = store.ui.selectedClipID else { return }
        if let idx = TimelineGeometry.spineIndex(ofClipID: clipID, in: store.document.sequence) {
            store.dispatch(.rippleDelete(at: idx))
            store.dispatch(.selectClip(nil))
        }
    }

    // MARK: - Drop Handler

    private func handleDrop(assetIDRaws: [String], at location: CGPoint) {
        for raw in assetIDRaws {
            let assetID = AssetID(raw: raw)
            guard let asset = store.document.assetLibrary.first(where: { $0.id == assetID }) else {
                print("[TimelineView] 未找到 assetID: \(raw)")
                continue
            }
            let clip = Clip(assetID: asset.id, sourceIn: .zero, duration: asset.duration)
            let index = TimelineGeometry.insertionIndex(
                forX: location.x,
                sequence: store.document.sequence,
                pxPerSecond: pxPerSecond
            )
            store.dispatch(.insertClip(clip, at: index))
        }
    }
}
