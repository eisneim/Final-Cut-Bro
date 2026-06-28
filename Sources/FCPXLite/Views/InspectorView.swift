import SwiftUI

/// Inspector:选中 clip 的常用参数(复合/变换/裁剪),编辑走命令层(可撤销),实时反映到预览。
/// 复刻 FCPX 检查器布局的核心项。无选中时显示空态。
struct InspectorView: View {
    let store: DocumentStore

    var body: some View {
        Group {
            if let clip = store.selectedClip() {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        section("复合", reset: { store.updateSelectedAdjust { $0.opacity = 1 } }) {
                            sliderRow("不透明度", value: bind(\.opacity, scale: 100), range: 0...100, suffix: "%", display: clip.adjust.opacity * 100)
                        }
                        section("变换", reset: { store.updateSelectedAdjust { $0.transform = Transform() } }) {
                            xyRow("位置",
                                  x: bindCG(\.transform.position.x), y: bindCG(\.transform.position.y),
                                  dx: clip.adjust.transform.position.x, dy: clip.adjust.transform.position.y, suffix: "px")
                            sliderRow("旋转", value: bind(\.transform.rotation), range: -180...180, suffix: "°", display: clip.adjust.transform.rotation)
                            sliderRow("缩放(全部)", value: scaleAllBinding(clip), range: 1...400, suffix: "%", display: clip.adjust.transform.scale.width * 100)
                        }
                        section("裁剪", reset: { store.updateSelectedAdjust { $0.crop = Crop() } }) {
                            sliderRow("左", value: bind(\.crop.left), range: 0...1000, suffix: "px", display: clip.adjust.crop.left)
                            sliderRow("右", value: bind(\.crop.right), range: 0...1000, suffix: "px", display: clip.adjust.crop.right)
                            sliderRow("上", value: bind(\.crop.top), range: 0...1000, suffix: "px", display: clip.adjust.crop.top)
                            sliderRow("下", value: bind(\.crop.bottom), range: 0...1000, suffix: "px", display: clip.adjust.crop.bottom)
                        }
                        InspectorEffectsSection(store: store)
                    }
                }
                .background(Tokens.Palette.chrome)
            } else {
                ZStack {
                    Tokens.Palette.chrome
                    Text("不检查任何对象").font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bindings

    /// 把 Adjustments 的某个 Double keyPath 暴露成 Binding(可带显示缩放,如 opacity 0..1 ↔ 0..100)。
    private func bind(_ kp: WritableKeyPath<Adjustments, Double>, scale: Double = 1) -> Binding<Double> {
        Binding(
            get: { (store.selectedClip()?.adjust[keyPath: kp] ?? 0) * scale },
            set: { v in store.updateSelectedAdjust { $0[keyPath: kp] = v / scale } }
        )
    }

    private func scaleAllBinding(_ clip: Clip) -> Binding<Double> {
        Binding(
            get: { (store.selectedClip()?.adjust.transform.scale.width ?? 1) * 100 },
            set: { v in store.updateSelectedAdjust {
                $0.transform.scale = CGSize(width: v / 100, height: v / 100) } }
        )
    }

    /// CGFloat 版 binding(position 用)。
    private func bindCG(_ kp: WritableKeyPath<Adjustments, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(store.selectedClip()?.adjust[keyPath: kp] ?? 0) },
            set: { v in store.updateSelectedAdjust { $0[keyPath: kp] = CGFloat(v) } }
        )
    }

    // MARK: - UI 构件

    private func section<C: View>(_ title: String, reset: (() -> Void)? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                if let reset {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11)).foregroundStyle(Tokens.Palette.textMuted)
                    }
                    .buttonStyle(.plain).help("重置该组参数")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            content()
            Divider().overlay(Tokens.Palette.divider)
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, display: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range)
            EditableNumberField(value: value, range: range, suffix: suffix)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
    }

    private func xyRow(_ label: String, x: Binding<Double>, y: Binding<Double>, dx: Double, dy: Double, suffix: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted).frame(width: 80, alignment: .leading)
            Text("X").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            Slider(value: x, in: -1000...1000).frame(width: 50)
            EditableNumberField(value: x, range: -1000...1000, width: 44)
            Text("Y").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
            Slider(value: y, in: -1000...1000).frame(width: 50)
            EditableNumberField(value: y, range: -1000...1000, width: 44)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
    }
}
