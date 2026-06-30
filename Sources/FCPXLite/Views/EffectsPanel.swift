import SwiftUI

/// 效果/转场库面板(⌘5)。点击某项 → 应用到当前选中片段。
/// - 效果:color(调色)/ blur(模糊)/ fade(音频淡入淡出),追加到 clip.effects。
/// - 转场:crossfade(交叉叠化),设到选中【主轴片段】的 crossfadeIn(与前一片段叠化)。
/// 拖放到时间线较复杂,先做"选中片段 → 点击应用",Agent 已有对应 catalog 动作。
struct EffectsPanel: View {
    let store: DocumentStore
    @State private var toast: String?

    private struct Item: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let apply: (DocumentStore) -> String   // 返回反馈文案
    }

    private var effectItems: [Item] {
        [
            Item(title: "调色", subtitle: "亮度/对比度/饱和度", icon: "dial.medium") { s in
                s.addEffectToSelected(.color); return "已加调色到所选片段"
            },
            Item(title: "高斯模糊", subtitle: "radius 可调", icon: "drop.fill") { s in
                s.addEffectToSelected(.blur); return "已加模糊到所选片段"
            },
            Item(title: "音频淡入淡出", subtitle: "inSeconds/outSeconds", icon: "speaker.wave.2.fill") { s in
                s.addEffectToSelected(.fade); return "已加音频淡入淡出"
            },
        ]
    }
    private var transitionItems: [Item] {
        [
            Item(title: "交叉叠化", subtitle: "1s,与前一片段 dissolve", icon: "square.on.square.dashed") { s in
                s.addCrossfadeToSelected(seconds: 1.0) ? "已加 1s 叠化转场" : "需先选中非首个主轴片段"
            },
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Tokens.Palette.divider)
            if store.selectedClip() == nil {
                hint("先在时间线选中一个片段,再点这里的效果/转场应用上去。")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("效果", effectItems)
                    section("转场", transitionItems)
                }
                .padding(10)
            }
            if let toast {
                Text(toast).font(.system(size: 10)).foregroundStyle(Tokens.Palette.onAccent)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.Palette.clipBlue.opacity(0.85))
            }
        }
        .frame(width: CGFloat(store.ui.effectsWidth))
        .background(Tokens.Palette.effectsPanel)
    }

    private var header: some View {
        HStack {
            Image(systemName: "wand.and.stars").font(.system(size: 12))
            Text("效果 / 转场").font(Tokens.Typeface.body)
            Spacer()
        }
        .foregroundStyle(Tokens.Palette.textPrimary)
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func section(_ title: String, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textCool)
            ForEach(items) { item in card(item) }
        }
    }

    private func card(_ item: Item) -> some View {
        Button {
            let msg = item.apply(store)
            toast = msg
            // 简易自动消隐
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if toast == msg { toast = nil }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon).font(.system(size: 14))
                    .foregroundStyle(Tokens.Palette.selectYellow).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 11)).foregroundStyle(Tokens.Palette.textPrimary)
                    Text(item.subtitle).font(.system(size: 9)).foregroundStyle(Tokens.Palette.textMuted)
                }
                Spacer()
                Image(systemName: "plus.circle").font(.system(size: 12)).foregroundStyle(Tokens.Palette.textMuted)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(Tokens.Palette.elevated).cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("应用到当前选中片段")
    }
}
