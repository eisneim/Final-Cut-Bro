import SwiftUI

/// 双击进入编辑的数值字段:平时显示数字,双击变 TextField 精确输入,回车/失焦提交(夹到 range)。
/// Inspector 各参数行复用 —— 拖 slider 粗调,双击数字精调。
/// 约定:调用方让 value 与显示同尺度(如 opacity 用 0–100、scale 用百分比),range 即 value 空间。
struct EditableNumberField: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var suffix: String = ""
    var decimals: Int = 0
    var width: CGFloat = 54

    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, f in if !f { commit() } }
            } else {
                Text("\(value.wrappedValue, specifier: "%.\(decimals)f")\(suffix.isEmpty ? "" : " " + suffix)")
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { startEdit() }
            }
        }
        .font(Tokens.Typeface.label)
        .foregroundStyle(Tokens.Palette.textPrimary)
        .frame(width: width, alignment: .trailing)
    }

    private func startEdit() {
        text = String(format: "%.\(decimals)f", value.wrappedValue)
        editing = true
        focused = true
    }

    private func commit() {
        if let v = Double(text.trimmingCharacters(in: .whitespaces)) {
            value.wrappedValue = min(range.upperBound, max(range.lowerBound, v))
        }
        editing = false
    }
}
