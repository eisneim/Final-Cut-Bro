import SwiftUI

// MARK: - Edit Action Icons (toolbar left group)

/// 连接 Connect: two stacked stroked rects, top ~60% width centered, small gap between
struct ConnectIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // bottom rect (main track)
            let bottomRect = CGRect(x: w * 0.1, y: h * 0.58, width: w * 0.8, height: h * 0.28)
            let bottomPath = Path(bottomRect)
            ctx.stroke(bottomPath, with: .foreground, lineWidth: 1.5)

            // top rect (connected clip, ~60% width, centered)
            let topW = w * 0.5
            let topX = (w - topW) / 2
            let topRect = CGRect(x: topX, y: h * 0.15, width: topW, height: h * 0.28)
            let topPath = Path(topRect)
            ctx.stroke(topPath, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 插入 Insert: stroked rect + down-arrow entering top center, tip at vertical midpoint
struct InsertIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // rect (lower half)
            let rect = CGRect(x: w * 0.1, y: h * 0.45, width: w * 0.8, height: h * 0.42)
            ctx.stroke(Path(rect), with: .foreground, lineWidth: 1.5)

            // arrow shaft from top down to mid-rect
            let cx = w / 2
            var shaft = Path()
            shaft.move(to: CGPoint(x: cx, y: h * 0.05))
            shaft.addLine(to: CGPoint(x: cx, y: h * 0.66))
            ctx.stroke(shaft, with: .foreground, lineWidth: 1.5)

            // arrowhead pointing down
            var head = Path()
            head.move(to: CGPoint(x: cx - w * 0.12, y: h * 0.54))
            head.addLine(to: CGPoint(x: cx, y: h * 0.66))
            head.addLine(to: CGPoint(x: cx + w * 0.12, y: h * 0.54))
            ctx.stroke(head, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 追加 Append: stroked rect + down-arrow, tip lands on bottom edge
struct AppendIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // rect
            let rect = CGRect(x: w * 0.1, y: h * 0.38, width: w * 0.8, height: h * 0.48)
            ctx.stroke(Path(rect), with: .foreground, lineWidth: 1.5)

            // shaft from top down to bottom edge of rect
            let cx = w / 2
            let bottom = h * 0.86
            var shaft = Path()
            shaft.move(to: CGPoint(x: cx, y: h * 0.05))
            shaft.addLine(to: CGPoint(x: cx, y: bottom))
            ctx.stroke(shaft, with: .foreground, lineWidth: 1.5)

            // arrowhead pointing down at bottom edge
            var head = Path()
            head.move(to: CGPoint(x: cx - w * 0.12, y: bottom - h * 0.12))
            head.addLine(to: CGPoint(x: cx, y: bottom))
            head.addLine(to: CGPoint(x: cx + w * 0.12, y: bottom - h * 0.12))
            ctx.stroke(head, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 覆盖 Overwrite: FILLED rect + down-arrow entering top (fill distinguishes from insert/append)
struct OverwriteIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // filled rect
            let rect = CGRect(x: w * 0.1, y: h * 0.45, width: w * 0.8, height: h * 0.42)
            ctx.fill(Path(rect), with: .foreground)

            // arrow from top, tip enters at ~1/3 into rect
            let cx = w / 2
            let tipY = h * 0.62
            var shaft = Path()
            shaft.move(to: CGPoint(x: cx, y: h * 0.05))
            shaft.addLine(to: CGPoint(x: cx, y: tipY))
            ctx.stroke(shaft, with: .foreground, lineWidth: 1.5)

            // arrowhead
            var head = Path()
            head.move(to: CGPoint(x: cx - w * 0.12, y: tipY - h * 0.12))
            head.addLine(to: CGPoint(x: cx, y: tipY))
            head.addLine(to: CGPoint(x: cx + w * 0.12, y: tipY - h * 0.12))
            ctx.stroke(head, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Tool Icons

/// 选择 Select: classic arrow cursor (hollow triangle, tip top-left, short tail bottom-right)
struct SelectIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var arrow = Path()
            arrow.move(to: CGPoint(x: w * 0.15, y: h * 0.1))
            arrow.addLine(to: CGPoint(x: w * 0.15, y: h * 0.78))
            arrow.addLine(to: CGPoint(x: w * 0.37, y: h * 0.6))
            arrow.addLine(to: CGPoint(x: w * 0.55, y: h * 0.88))
            arrow.addLine(to: CGPoint(x: w * 0.68, y: h * 0.82))
            arrow.addLine(to: CGPoint(x: w * 0.5, y: h * 0.54))
            arrow.addLine(to: CGPoint(x: w * 0.72, y: h * 0.54))
            arrow.closeSubpath()
            ctx.stroke(arrow, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 修剪 Trim: ◀‖‖▶ — left/right triangles facing inward, two center bars
struct TrimIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let midY = h / 2
            let barTop = midY - h * 0.28
            let barBot = midY + h * 0.28

            // left triangle ◀
            var left = Path()
            left.move(to: CGPoint(x: w * 0.28, y: midY))
            left.addLine(to: CGPoint(x: w * 0.44, y: barTop))
            left.addLine(to: CGPoint(x: w * 0.44, y: barBot))
            left.closeSubpath()
            ctx.fill(left, with: .foreground)

            // right triangle ▶
            var right = Path()
            right.move(to: CGPoint(x: w * 0.72, y: midY))
            right.addLine(to: CGPoint(x: w * 0.56, y: barTop))
            right.addLine(to: CGPoint(x: w * 0.56, y: barBot))
            right.closeSubpath()
            ctx.fill(right, with: .foreground)

            // two center bars ‖‖
            var b1 = Path()
            b1.move(to: CGPoint(x: w * 0.46, y: barTop))
            b1.addLine(to: CGPoint(x: w * 0.46, y: barBot))
            ctx.stroke(b1, with: .foreground, lineWidth: 1.5)

            var b2 = Path()
            b2.move(to: CGPoint(x: w * 0.54, y: barTop))
            b2.addLine(to: CGPoint(x: w * 0.54, y: barBot))
            ctx.stroke(b2, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 位置 Position: filled right-pointing pennant (left vert edge + right tip)
struct PositionIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var pennant = Path()
            pennant.move(to: CGPoint(x: w * 0.2, y: h * 0.2))
            pennant.addLine(to: CGPoint(x: w * 0.2, y: h * 0.8))
            pennant.addLine(to: CGPoint(x: w * 0.82, y: h * 0.5))
            pennant.closeSubpath()
            ctx.fill(pennant, with: .foreground)
        }
        .frame(width: 16, height: 16)
    }
}

/// 范围选择 Range: rounded box with dashed right edge + solid right arrow
struct RangeIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let boxLeft: CGFloat = w * 0.08
            let boxRight: CGFloat = w * 0.62
            let boxTop: CGFloat = h * 0.25
            let boxBot: CGFloat = h * 0.75

            // left/top/bottom solid sides
            var solid = Path()
            solid.move(to: CGPoint(x: boxRight, y: boxTop))
            solid.addLine(to: CGPoint(x: boxLeft + 4, y: boxTop))
            solid.addArc(center: CGPoint(x: boxLeft + 4, y: boxTop + 4),
                         radius: 4, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)
            solid.addLine(to: CGPoint(x: boxLeft, y: boxBot - 4))
            solid.addArc(center: CGPoint(x: boxLeft + 4, y: boxBot - 4),
                         radius: 4, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            solid.addLine(to: CGPoint(x: boxRight, y: boxBot))
            ctx.stroke(solid, with: .foreground, style: StrokeStyle(lineWidth: 1.5))

            // dashed right side
            var dashed = Path()
            dashed.move(to: CGPoint(x: boxRight, y: boxTop))
            dashed.addLine(to: CGPoint(x: boxRight, y: boxBot))
            ctx.stroke(dashed, with: .foreground, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))

            // arrow pointing right
            let arrowMidY = h / 2
            var shaft = Path()
            shaft.move(to: CGPoint(x: boxRight + w * 0.04, y: arrowMidY))
            shaft.addLine(to: CGPoint(x: w * 0.88, y: arrowMidY))
            ctx.stroke(shaft, with: .foreground, lineWidth: 1.5)

            var head = Path()
            head.move(to: CGPoint(x: w * 0.76, y: arrowMidY - h * 0.12))
            head.addLine(to: CGPoint(x: w * 0.88, y: arrowMidY))
            head.addLine(to: CGPoint(x: w * 0.76, y: arrowMidY + h * 0.12))
            ctx.stroke(head, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 切割 Blade: razor blade parallelogram with angled cutting edge (not scissors)
struct BladeIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // parallelogram blade body
            var blade = Path()
            blade.move(to: CGPoint(x: w * 0.25, y: h * 0.2))
            blade.addLine(to: CGPoint(x: w * 0.78, y: h * 0.2))
            blade.addLine(to: CGPoint(x: w * 0.75, y: h * 0.8))
            blade.addLine(to: CGPoint(x: w * 0.22, y: h * 0.8))
            blade.closeSubpath()
            ctx.stroke(blade, with: .foreground, lineWidth: 1.5)

            // cutting edge (diagonal line across blade)
            var edge = Path()
            edge.move(to: CGPoint(x: w * 0.3, y: h * 0.28))
            edge.addLine(to: CGPoint(x: w * 0.72, y: h * 0.62))
            ctx.stroke(edge, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 缩放 Zoom: magnifier circle + 4~5 o'clock direction handle
struct ZoomIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // circle
            let circleRect = CGRect(x: w * 0.1, y: h * 0.08, width: w * 0.6, height: h * 0.6)
            ctx.stroke(Path(ellipseIn: circleRect), with: .foreground, lineWidth: 1.5)

            // handle at ~4 o'clock angle (45° toward bottom-right)
            var handle = Path()
            handle.move(to: CGPoint(x: w * 0.6, y: h * 0.57))
            handle.addLine(to: CGPoint(x: w * 0.88, y: h * 0.88))
            ctx.stroke(handle, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 16, height: 16)
    }
}

/// 手 Hand: open palm — four fingers + left upper thumb + rounded palm base
struct HandIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // thumb (upper-left, angled)
            var thumb = Path()
            thumb.move(to: CGPoint(x: w * 0.18, y: h * 0.55))
            thumb.addQuadCurve(to: CGPoint(x: w * 0.25, y: h * 0.35),
                               control: CGPoint(x: w * 0.1, y: h * 0.4))
            ctx.stroke(thumb, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // four fingers (evenly spaced vertical lines with rounded tops)
            let fingers: [(CGFloat, CGFloat, CGFloat)] = [
                (w * 0.32, h * 0.12, h * 0.5),
                (w * 0.44, h * 0.08, h * 0.5),
                (w * 0.56, h * 0.1,  h * 0.5),
                (w * 0.68, h * 0.15, h * 0.5),
            ]
            for (x, top, bot) in fingers {
                var f = Path()
                f.move(to: CGPoint(x: x, y: top))
                f.addLine(to: CGPoint(x: x, y: bot))
                ctx.stroke(f, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            // palm base (arc connecting bottom of fingers)
            var palm = Path()
            palm.move(to: CGPoint(x: w * 0.2, y: h * 0.6))
            palm.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.6),
                              control: CGPoint(x: w * 0.5, y: h * 0.82))
            ctx.stroke(palm, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Helper

/// Returns the appropriate tool icon view for the given EditTool.
@ViewBuilder
func toolIcon(for tool: EditTool) -> some View {
    switch tool {
    case .select:   SelectIcon()
    case .trim:     TrimIcon()
    case .position: PositionIcon()
    case .range:    RangeIcon()
    case .blade:    BladeIcon()
    case .zoom:     ZoomIcon()
    case .hand:     HandIcon()
    }
}
