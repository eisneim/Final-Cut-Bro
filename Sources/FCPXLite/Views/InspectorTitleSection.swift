import SwiftUI

/// 标题片段的检查器:文字内容、字号、颜色、粗体、对齐、画面位置。改动走 setTitle(可撤销)。
struct InspectorTitleSection: View {
    let store: DocumentStore

    private var spec: TitleSpec? { store.selectedClip()?.title }

    var body: some View {
        if let s = spec {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "textformat").font(.system(size: 11))
                    Text("标题").font(Tokens.Typeface.body)
                    Spacer()
                }
                .foregroundStyle(Tokens.Palette.textPrimary)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)

                // 文字内容(多行)
                TextEditor(text: Binding(
                    get: { store.selectedClip()?.title?.text ?? "" },
                    set: { v in store.updateSelectedTitle { $0.text = v } }))
                    .font(.system(size: 13))
                    .frame(height: 54)
                    .padding(.horizontal, 6)
                    .background(Tokens.Palette.elevated).cornerRadius(5)
                    .padding(.horizontal, 10)

                row("字号") {
                    Slider(value: Binding(get: { s.fontSize },
                                          set: { v in store.updateSelectedTitle { $0.fontSize = v } }),
                           in: 16...300)
                    Text("\(Int(s.fontSize))").font(Tokens.Typeface.label)
                        .foregroundStyle(Tokens.Palette.textMuted).frame(width: 34)
                }
                row("颜色") {
                    ColorPicker("", selection: Binding(
                        get: { Color(NSColor(hex: s.colorHex)) },
                        set: { c in store.updateSelectedTitle { $0.colorHex = hex(of: c) } }))
                        .labelsHidden()
                    Toggle("粗体", isOn: Binding(get: { s.bold },
                                               set: { v in store.updateSelectedTitle { $0.bold = v } }))
                        .toggleStyle(.checkbox).font(Tokens.Typeface.label)
                    Spacer()
                }
                row("对齐") {
                    Picker("", selection: Binding(get: { s.align },
                                                  set: { v in store.updateSelectedTitle { $0.align = v } })) {
                        Text("左").tag(0); Text("中").tag(1); Text("右").tag(2)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
                    Spacer()
                }
                row("位置") {
                    stepper("X", s.position.x) { dx in store.updateSelectedTitle { $0.position.x += dx } }
                    stepper("Y", s.position.y) { dy in store.updateSelectedTitle { $0.position.y += dy } }
                    Spacer()
                }
                Divider().overlay(Tokens.Palette.divider).padding(.top, 4)
            }
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                .frame(width: 40, alignment: .leading)
            content()
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
    }

    private func stepper(_ axis: String, _ val: CGFloat, _ bump: @escaping (CGFloat) -> Void) -> some View {
        HStack(spacing: 2) {
            Text(axis).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            Button("−") { bump(-20) }.buttonStyle(.plain).frame(width: 18)
            Text("\(Int(val))").font(.system(size: 10)).foregroundStyle(Tokens.Palette.textPrimary).frame(width: 34)
            Button("+") { bump(20) }.buttonStyle(.plain).frame(width: 18)
        }
    }

    private func hex(of c: Color) -> String {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(ns.redComponent*255), Int(ns.greenComponent*255), Int(ns.blueComponent*255))
    }
}
