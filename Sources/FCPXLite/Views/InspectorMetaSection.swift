import SwiftUI

/// Inspector 的【项目信息】与【素材信息】只读展示 —— 跟随最后选择的对象(FCP 行为)。
/// 项目:分辨率/方向/帧率/片段数;素材:类型/分辨率/帧率/时长/音频。

/// 一行「标签 : 值」。
private func metaRow(_ label: String, _ value: String) -> some View {
    HStack(spacing: 8) {
        Text(label).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            .frame(width: 72, alignment: .leading)
        Text(value).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
            .textSelection(.enabled)
        Spacer(minLength: 0)
    }
    .padding(.horizontal, 10).padding(.vertical, 3)
}

private func metaHeader(_ title: String) -> some View {
    Text(title).font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textPrimary)
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
}

/// 时长格式:分:秒.厘秒(短片段也看得清)。
private func fmtDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let m = Int(seconds) / 60, s = seconds - Double(m * 60)
    return m > 0 ? String(format: "%d:%05.2f", m, s) : String(format: "%.2fs", s)
}

/// 宽高比方向判定。
private func orientationLabel(w: Int, h: Int) -> String {
    if w == 0 || h == 0 { return "—" }
    if w > h { return "横屏 (Landscape)" }
    if h > w { return "竖屏 (Portrait)" }
    return "方形 (Square)"
}

/// 项目信息面板。
struct InspectorProjectMeta: View {
    let store: DocumentStore
    var body: some View {
        let doc = store.document
        let w = doc.formatWidth, h = doc.formatHeight
        let clipCount = doc.sequence.spine.reduce(0) { acc, el in
            if case .clip = el { return acc + 1 }; return acc
        }
        let total = Layout.compute(doc.sequence).map { ($0.absStart + $0.duration).seconds }.max() ?? 0
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                metaHeader("项目")
                Divider().overlay(Tokens.Palette.divider)
                metaRow("名称", doc.currentProject?.name ?? "—")
                metaRow("分辨率", "\(w) × \(h)")
                metaRow("方向", orientationLabel(w: w, h: h))
                metaRow("帧率", "\(Int(doc.frameRate.rounded())) fps")
                metaRow("片段数", "\(clipCount)")
                metaRow("时长", fmtDuration(total))
            }
        }
        .background(Tokens.Palette.chrome)
    }
}

/// 素材信息面板。
struct InspectorAssetMeta: View {
    let store: DocumentStore
    let asset: Asset
    var body: some View {
        let kindLabel: String = {
            switch asset.kind {
            case .video: return "视频"
            case .audio: return "音频"
            case .image: return "图片"
            }
        }()
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                metaHeader("素材")
                Divider().overlay(Tokens.Palette.divider)
                metaRow("文件", asset.url.lastPathComponent)
                metaRow("类型", kindLabel)
                if asset.kind != .audio {
                    let w = Int(asset.naturalSize.width.rounded())
                    let h = Int(asset.naturalSize.height.rounded())
                    metaRow("分辨率", "\(w) × \(h)")
                    metaRow("方向", orientationLabel(w: w, h: h))
                }
                if asset.kind == .video, let fr = asset.frameRate, fr > 0 {
                    metaRow("帧率", String(format: "%.2f fps", fr))
                }
                if asset.kind != .image {
                    metaRow("时长", fmtDuration(asset.duration.seconds))
                }
                if asset.kind == .video {
                    metaRow("音频", asset.hasAudio ? "有" : "无")
                }
            }
        }
        .background(Tokens.Palette.chrome)
    }
}
