import SwiftUI

/// 标题的画面内(on-screen)控制:选中标题时,在 viewer 里显示一个可拖动的文字框。
/// 拖动 → 改 title.position(屏幕坐标 → 渲染坐标换算);双击 → 内联编辑文字。
struct TitleOverlay: View {
    let store: DocumentStore
    @State private var dragBase: CGPoint?      // 拖拽起点的 position(渲染坐标)
    @State private var editing = false
    @FocusState private var focused: Bool

    private var titleClip: Clip? {
        guard let c = store.selectedClip(), c.title != nil else { return nil }
        return c
    }

    var body: some View {
        GeometryReader { geo in
            if let clip = titleClip, let spec = clip.title {
                let rw = CGFloat(store.document.formatWidth)
                let rh = CGFloat(store.document.formatHeight)
                let scale = min(geo.size.width / rw, geo.size.height / rh)
                let dispW = rw * scale, dispH = rh * scale
                let ox = (geo.size.width - dispW) / 2, oy = (geo.size.height - dispH) / 2
                // 标题中心(渲染坐标 y 向下)→ 屏幕坐标
                let sx = ox + (rw / 2 + spec.position.x) * scale
                let sy = oy + (rh / 2 + spec.position.y) * scale

                box(spec, scale: scale)
                    .position(x: sx, y: sy)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { g in
                                if dragBase == nil { dragBase = spec.position }
                                let b = dragBase ?? spec.position
                                store.updateSelectedTitle {
                                    $0.position = CGPoint(x: b.x + g.translation.width / scale,
                                                          y: b.y + g.translation.height / scale)
                                }
                            }
                            .onEnded { _ in dragBase = nil }
                    )
                    .onTapGesture(count: 2) { editing = true; focused = true }
            }
        }
        .allowsHitTesting(titleClip != nil)
    }

    @ViewBuilder
    private func box(_ spec: TitleSpec, scale: CGFloat) -> some View {
        if editing {
            TextField("", text: Binding(
                get: { store.selectedClip()?.title?.text ?? "" },
                set: { v in store.updateSelectedTitle { $0.text = v } }), axis: .vertical)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: max(10, spec.fontSize * scale), weight: spec.bold ? .bold : .regular))
                .foregroundStyle(Color(NSColor(hex: spec.colorHex)))
                .focused($focused)
                .padding(6)
                .background(Color.black.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(TimelineColors.selectBorder), lineWidth: 1.5))
                .onSubmit { editing = false }
                .onChange(of: focused) { _, f in if !f { editing = false } }
                .frame(maxWidth: 480)
        } else {
            // 拖拽手柄:显示文字 + 黄色虚框,提示可拖。
            Text(spec.text.isEmpty ? " " : spec.text)
                .font(.system(size: max(10, spec.fontSize * scale), weight: spec.bold ? .bold : .regular))
                .foregroundStyle(Color(NSColor(hex: spec.colorHex)).opacity(0.001))   // 文字本身由合成器画,这里透明只占位
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(TimelineColors.selectBorder), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .contentShape(Rectangle())
        }
    }
}
