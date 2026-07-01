import SwiftUI

/// 顶栏按钮的矢量图标(手绘 Path,monoline 风格,~20pt)。
/// 三个面板切换 + 导出。颜色由外部按 激活/未激活 传入。

/// 素材库(左侧面板)切换 —— sidebar-left:外框 + 左栏填充。
struct LibraryToggleIcon: View {
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(x: 2, y: 3, width: size.width - 4, height: size.height - 6)
            let outer = Path(roundedRect: r, cornerRadius: 3)
            let dx = r.minX + r.width * 0.36
            // 左栏淡填充
            ctx.fill(Path(CGRect(x: r.minX + 1, y: r.minY + 1, width: dx - r.minX - 1, height: r.height - 2)),
                     with: .color(color.opacity(0.35)))
            ctx.stroke(outer, with: .color(color), lineWidth: 1.5)
            var div = Path(); div.move(to: CGPoint(x: dx, y: r.minY)); div.addLine(to: CGPoint(x: dx, y: r.maxY))
            ctx.stroke(div, with: .color(color), lineWidth: 1.5)
        }
        .frame(width: 20, height: 20)
    }
}

/// 检查器切换 —— sliders.horizontal.3:三条横线各带一个旋钮。
struct InspectorToggleIcon: View {
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let xs = size.width, pad: CGFloat = 3
            let ys: [CGFloat] = [size.height * 0.28, size.height * 0.5, size.height * 0.72]
            let knobX: [CGFloat] = [xs * 0.66, xs * 0.36, xs * 0.72]
            for (i, y) in ys.enumerated() {
                var line = Path()
                line.move(to: CGPoint(x: pad, y: y)); line.addLine(to: CGPoint(x: xs - pad, y: y))
                ctx.stroke(line, with: .color(color), lineWidth: 1.5)
                let kx = knobX[i]
                ctx.fill(Path(ellipseIn: CGRect(x: kx - 2.4, y: y - 2.4, width: 4.8, height: 4.8)), with: .color(color))
                ctx.stroke(Path(ellipseIn: CGRect(x: kx - 2.4, y: y - 2.4, width: 4.8, height: 4.8)),
                           with: .color(color), lineWidth: 1)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// Agent 面板切换 —— 对话气泡 + 三个点。
struct AgentToggleIcon: View {
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bubble = CGRect(x: 2, y: 2.5, width: w - 4, height: h * 0.62)
            ctx.stroke(Path(roundedRect: bubble, cornerRadius: 4), with: .color(color), lineWidth: 1.5)
            // 左下小尾巴
            var tail = Path()
            tail.move(to: CGPoint(x: bubble.minX + 4, y: bubble.maxY - 1))
            tail.addLine(to: CGPoint(x: bubble.minX + 4, y: bubble.maxY + 4))
            tail.addLine(to: CGPoint(x: bubble.minX + 9, y: bubble.maxY - 1))
            ctx.fill(tail, with: .color(color))
            // 三个点
            let cy = bubble.midY
            for fx in [0.3, 0.5, 0.7] {
                let cx = bubble.minX + bubble.width * fx
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.3, y: cy - 1.3, width: 2.6, height: 2.6)), with: .color(color))
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// 导出 —— 方框(开口向上)+ 向上箭头(share)。
struct ExportToolbarIcon: View {
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // 箱体:U 形(顶部开口)
            var box = Path()
            box.move(to: CGPoint(x: w * 0.26, y: h * 0.5))
            box.addLine(to: CGPoint(x: w * 0.26, y: h * 0.84))
            box.addLine(to: CGPoint(x: w * 0.74, y: h * 0.84))
            box.addLine(to: CGPoint(x: w * 0.74, y: h * 0.5))
            ctx.stroke(box, with: .color(color), lineWidth: 1.5)
            // 竖箭杆
            var stem = Path()
            stem.move(to: CGPoint(x: w * 0.5, y: h * 0.18)); stem.addLine(to: CGPoint(x: w * 0.5, y: h * 0.62))
            ctx.stroke(stem, with: .color(color), lineWidth: 1.5)
            // 箭头
            var head = Path()
            head.move(to: CGPoint(x: w * 0.36, y: h * 0.32))
            head.addLine(to: CGPoint(x: w * 0.5, y: h * 0.18))
            head.addLine(to: CGPoint(x: w * 0.64, y: h * 0.32))
            ctx.stroke(head, with: .color(color), lineWidth: 1.5)
        }
        .frame(width: 20, height: 20)
    }
}
