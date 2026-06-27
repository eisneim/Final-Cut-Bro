import SwiftUI
import AppKit

/// 面板间可拖拽分隔线:hover 显示左右调整光标,拖拽改相邻面板宽度。
/// sign = +1 表示"向右拖增大该面板"(面板在分隔线左侧);-1 表示"向左拖增大"(面板在右侧)。
struct WidthDragHandle: View {
    let width: Double
    let sign: Double
    let set: (Double) -> Void

    @State private var base: Double?

    var body: some View {
        Rectangle()
            .fill(Tokens.Palette.divider)
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { g in
                                if base == nil { base = width }
                                set((base ?? width) + sign * Double(g.translation.width))
                            }
                            .onEnded { _ in base = nil }
                    )
            )
    }
}
