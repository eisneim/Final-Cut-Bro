import SwiftUI

/// 项目区:顶部 toolbar(左"项目"文字 + 右"+"创建)+ 下方项目卡片(带预览缩略图的方块,纵向换行)。
/// 仿 FCP:项目以缩略方块呈现,当前项目高亮。无自带滚动 —— 由左侧栏统一 ScrollView 整体滚动。
struct ProjectBar: View {
    let store: DocumentStore

    // 卡片纵向换行网格(随宽度自适应列数);不内置滚动,跟随外层一起滚。
    private let columns = [GridItem(.adaptive(minimum: 94), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbarHeader
            // 卡片(纵向换行,可有很多个项目)
            if store.document.projects.isEmpty {
                Text("还没有项目,点 + 创建")
                    .font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
                    .padding(.horizontal, 8).padding(.bottom, 6)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(store.document.projects) { p in projectCard(p) }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
        .background(Tokens.Palette.elevated.opacity(0.4))
    }

    /// toolbar:左文字,右创建。
    var toolbarHeader: some View {
        HStack {
            Text("项目").font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textCool)
            Spacer()
            Button { store.dispatch(.setShowProjectModal(true)) } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tokens.Palette.textCool)
                    .frame(width: 24, height: 22)
                    .background(Tokens.Palette.elevated).cornerRadius(5)
            }
            .buttonStyle(.plain).help("创建项目")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func projectCard(_ p: Project) -> some View {
        let current = store.document.currentProjectID == p.id
        return Button {
            store.dispatch(.selectProject(p.id))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                // 预览方块:首个片段首帧缩略图,无则占位图标
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Tokens.Palette.canvas)
                    if let cg = previewThumb(p) {
                        Image(decorative: cg, scale: 1)
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 84, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "film").font(.system(size: 18))
                            .foregroundStyle(Tokens.Palette.textMuted)
                    }
                }
                .frame(width: 84, height: 48)
                Text(p.name).font(.system(size: 10)).lineLimit(1)
                    .foregroundStyle(current ? Tokens.Palette.onAccent : Tokens.Palette.textCool)
                Text("\(p.formatWidth)×\(p.formatHeight)")
                    .font(.system(size: 8)).foregroundStyle(Tokens.Palette.textMuted)
            }
            .frame(width: 84)
            .padding(5)
            .background(current ? Tokens.Palette.clipBlue : Tokens.Palette.chatPanel)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(current ? Tokens.Palette.selectYellow : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// 项目首个主轴片段的首帧缩略图(异步缓存;未就绪返回 nil → 占位)。
    private func previewThumb(_ p: Project) -> CGImage? {
        for el in p.sequence.spine {
            if case .clip(let c) = el,
               let asset = store.document.assetLibrary.first(where: { $0.id == c.assetID }),
               asset.kind != .audio {
                return TimelineMediaCache.shared.thumbnails(for: asset)?.first
            }
        }
        return nil
    }
}
