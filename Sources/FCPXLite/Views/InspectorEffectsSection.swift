import SwiftUI

/// Inspector 特效区:列出选中 clip 的 effects,可加(选 kind)/删/启停/调参。走命令层(可撤销)。
struct InspectorEffectsSection: View {
    let store: DocumentStore

    var body: some View {
        let effects = store.selectedClip()?.effects ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("特效").font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Menu {
                    ForEach(EffectKind.allCases, id: \.self) { k in
                        Button(label(k)) { store.updateSelectedEffects { $0.append(Effect.make(k)) } }
                    }
                } label: { Image(systemName: "plus.circle").foregroundStyle(Tokens.Palette.textMuted) }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            ForEach(Array(effects.enumerated()), id: \.element.id) { idx, e in
                effectRow(idx, e)
            }
            Divider().overlay(Tokens.Palette.divider)
        }
    }

    private func label(_ k: EffectKind) -> String {
        switch k { case .color: return "调色"; case .blur: return "高斯模糊"; case .fade: return "淡入淡出" }
    }

    @ViewBuilder private func effectRow(_ idx: Int, _ e: Effect) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { e.enabled },
                    set: { v in store.updateSelectedEffects { if $0.indices.contains(idx) { $0[idx].enabled = v } } }
                )).labelsHidden().toggleStyle(.checkbox)
                Text(label(e.kind)).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Button { store.updateSelectedEffects { if $0.indices.contains(idx) { $0.remove(at: idx) } } }
                    label: { Image(systemName: "trash").foregroundStyle(Tokens.Palette.windowClose) }
                    .buttonStyle(.plain)
            }
            ForEach(paramKeys(e.kind), id: \.self) { key in
                paramSlider(idx, e, key)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
    }

    private func paramKeys(_ k: EffectKind) -> [String] {
        switch k {
        case .color: return ["brightness", "contrast", "saturation"]
        case .blur:  return ["radius"]
        case .fade:  return ["inSeconds", "outSeconds"]
        }
    }

    private func paramRange(_ key: String) -> ClosedRange<Double> {
        switch key {
        case "brightness": return -1...1
        case "contrast", "saturation": return 0...2
        case "radius": return 0...50
        default: return 0...10   // fade 秒数
        }
    }

    private func paramSlider(_ idx: Int, _ e: Effect, _ key: String) -> some View {
        HStack(spacing: 8) {
            Text(key).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted).frame(width: 76, alignment: .leading)
            Slider(value: Binding(
                get: { e.params[key] ?? 0 },
                set: { v in store.updateSelectedEffects { if $0.indices.contains(idx) { $0[idx].params[key] = v } } }
            ), in: paramRange(key))
            Text(String(format: "%.2f", e.params[key] ?? 0)).font(.system(size: 10))
                .foregroundStyle(Tokens.Palette.textPrimary).frame(width: 40, alignment: .trailing)
        }
    }
}
