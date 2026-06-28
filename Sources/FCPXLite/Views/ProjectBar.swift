import SwiftUI

/// 项目栏:素材池最上方,横排所有项目(当前项目高亮)+ 末尾"+"创建。仿 FCP 顶部项目切换。
struct ProjectBar: View {
    let store: DocumentStore

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.document.projects) { p in
                        projectChip(p)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { store.dispatch(.setShowProjectModal(true)) } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tokens.Palette.textCool)
                    .frame(width: 24, height: 22)
                    .background(Tokens.Palette.elevated).cornerRadius(5)
            }
            .buttonStyle(.plain).help("创建项目")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Tokens.Palette.elevated.opacity(0.5))
    }

    private func projectChip(_ p: Project) -> some View {
        let current = store.document.currentProjectID == p.id
        return Button {
            store.dispatch(.selectProject(p.id))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "film").font(.system(size: 9))
                Text(p.name).font(Tokens.Typeface.label).lineLimit(1)
                Text("\(p.formatWidth)×\(p.formatHeight)").font(.system(size: 8)).opacity(0.6)
            }
            .foregroundStyle(current ? Tokens.Palette.onAccent : Tokens.Palette.textCool)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(current ? Tokens.Palette.clipBlue : Tokens.Palette.chatPanel)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}
