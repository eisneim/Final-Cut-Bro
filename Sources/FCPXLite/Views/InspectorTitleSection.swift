import SwiftUI
import AppKit

/// 标题片段检查器:文字内容(可改错别字)、字体、字号、颜色、粗体、对齐、描边、阴影、画面位置。
/// 改动走 updateSelectedTitle(可撤销,多选时批量),实时反映到预览/导出。
struct InspectorTitleSection: View {
    let store: DocumentStore

    private var spec: TitleSpec? { store.selectedClip()?.title }
    private static let sysFont = t("系统默认")
    private static let fontFamilies: [String] = [sysFont] + NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        if let s = spec {
            VStack(alignment: .leading, spacing: 6) {
                header

                // 文字内容(多行,可直接改错别字)
                Text(t("文字(可直接改错别字)")).font(.system(size: 10))
                    .foregroundStyle(Tokens.Palette.textMuted).padding(.horizontal, 10)
                TextEditor(text: Binding(
                    get: { store.selectedClip()?.title?.text ?? "" },
                    set: { v in store.updateSelectedTitle { $0.text = v } }))
                    .font(.system(size: 13))
                    .frame(height: 60)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Tokens.Palette.elevated).cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Tokens.Palette.divider, lineWidth: 1))
                    .padding(.horizontal, 10)

                row(t("字体")) {
                    Picker("", selection: Binding(
                        get: { s.fontName ?? Self.sysFont },
                        set: { v in store.updateSelectedTitle { $0.fontName = (v == Self.sysFont ? nil : v) } })) {
                        ForEach(Self.fontFamilies, id: \.self) { Text($0).font(.system(size: 11)).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                row(t("字号")) {
                    Slider(value: titleD(\.fontSize), in: 16...300)
                    Text("\(Int(s.fontSize))").font(Tokens.Typeface.label)
                        .foregroundStyle(Tokens.Palette.textMuted).frame(width: 34)
                }
                row(t("颜色")) {
                    ColorPicker("", selection: colorBind(\.colorHex)).labelsHidden()
                    Toggle(t("粗体"), isOn: Binding(get: { s.bold },
                                               set: { v in store.updateSelectedTitle { $0.bold = v } }))
                        .toggleStyle(.checkbox).font(Tokens.Typeface.label)
                    Spacer()
                }
                row(t("对齐")) {
                    Picker("", selection: Binding(get: { s.align },
                                                  set: { v in store.updateSelectedTitle { $0.align = v } })) {
                        Text(t("左")).tag(0); Text(t("中")).tag(1); Text(t("右")).tag(2)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
                    Spacer()
                }

                // 描边(border)
                row(t("描边")) {
                    Slider(value: titleD(\.strokeWidth), in: 0...12)
                    Text("\(Int(s.strokeWidth))").font(Tokens.Typeface.label)
                        .foregroundStyle(Tokens.Palette.textMuted).frame(width: 22)
                    ColorPicker("", selection: colorBind(\.strokeColorHex)).labelsHidden()
                }

                // 阴影(shadow)
                row(t("阴影")) {
                    Toggle(t("启用"), isOn: Binding(get: { s.shadowEnabled },
                                               set: { v in store.updateSelectedTitle { $0.shadowEnabled = v } }))
                        .toggleStyle(.checkbox).font(Tokens.Typeface.label)
                    Spacer()
                }
                if s.shadowEnabled {
                    row(t("模糊")) {
                        Slider(value: titleD(\.shadowRadius), in: 0...30)
                        ColorPicker("", selection: colorBind(\.shadowColorHex)).labelsHidden()
                    }
                    row(t("偏移")) {
                        stepper("X", s.shadowDX) { dx in store.updateSelectedTitle { $0.shadowDX += dx } }
                        stepper("Y", s.shadowDY) { dy in store.updateSelectedTitle { $0.shadowDY += dy } }
                        Spacer()
                    }
                }

                row(t("位置")) {
                    stepper("X", s.position.x) { dx in store.updateSelectedTitle { $0.position.x += dx } }
                    stepper("Y", s.position.y) { dy in store.updateSelectedTitle { $0.position.y += dy } }
                    Spacer()
                }
                Divider().overlay(Tokens.Palette.divider).padding(.top, 4)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "textformat").font(.system(size: 11))
            Text(t("标题")).font(Tokens.Typeface.body)
            Spacer()
        }
        .foregroundStyle(Tokens.Palette.textPrimary)
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }

    // MARK: - Bindings

    /// TitleSpec 的 Double 字段绑定(走 updateSelectedTitle,可撤销)。
    private func titleD(_ kp: WritableKeyPath<TitleSpec, Double>) -> Binding<Double> {
        Binding(get: { store.selectedClip()?.title?[keyPath: kp] ?? 0 },
                set: { v in store.updateSelectedTitle { $0[keyPath: kp] = v } })
    }
    /// TitleSpec 的 #RRGGBB 颜色字段 ↔ SwiftUI Color。
    private func colorBind(_ kp: WritableKeyPath<TitleSpec, String>) -> Binding<Color> {
        Binding(get: { Color(NSColor(hex: store.selectedClip()?.title?[keyPath: kp] ?? "#FFFFFF")) },
                set: { c in store.updateSelectedTitle { $0[keyPath: kp] = hex(of: c) } })
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
    private func stepper(_ axis: String, _ val: Double, _ bump: @escaping (Double) -> Void) -> some View {
        stepper(axis, CGFloat(val)) { bump(Double($0)) }
    }

    private func hex(of c: Color) -> String {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(ns.redComponent*255), Int(ns.greenComponent*255), Int(ns.blueComponent*255))
    }
}
