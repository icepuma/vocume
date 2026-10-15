import SwiftUI

/// Draws marks into a SwiftUI `GraphicsContext`; used for both the editor canvas and PNG export.
public enum MarkRenderer {
    /// - Parameters:
    ///   - selected: a mark to outline as selected.
    ///   - editing: a mark whose label is being edited in a text field, so its pill is skipped.
    public static func draw(
        _ marks: [Mark],
        in context: GraphicsContext,
        size: CGSize,
        selected: UUID? = nil,
        editing: UUID? = nil
    ) {
        let baseUnit = Mark.unit(for: size)
        var step = 0
        for mark in marks {
            let color = Palette.color(named: mark.color)
            let unit = baseUnit * (mark.size ?? 1)
            let lineWidth = 6 * unit
            let (start, end) = mark.endpoints(in: size)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 3 * baseUnit, y: baseUnit))

            switch mark.kind {
            case .arrow:
                drawArrow(from: start, to: end, lineWidth: lineWidth, color: color, in: shadowed)
            case .highlight:
                var multiply = context
                multiply.blendMode = .multiply
                multiply.fill(
                    Path(roundedRect: mark.frame(in: size), cornerRadius: 2 * baseUnit),
                    with: .color(color.opacity(0.45))
                )
            case .redact:
                context.fill(Path(roundedRect: mark.frame(in: size), cornerRadius: 3 * baseUnit), with: .color(color))
            case .pen:
                var path = Path()
                path.addLines(mark.penPoints(in: size))
                shadowed.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            case .step:
                step += 1
                let circle = mark.stepCircle(in: size)
                shadowed.fill(Path(ellipseIn: circle), with: .color(color))
                context.stroke(
                    Path(ellipseIn: circle.insetBy(dx: unit, dy: unit)),
                    with: .color(.white.opacity(0.9)),
                    lineWidth: 2 * unit
                )
                context.draw(
                    Text("\(step)")
                        .font(.system(size: 15 * unit, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink(on: mark.color)),
                    at: start
                )
            case .text:
                break  // the label pill below is the whole mark
            case .box:
                shadowed.stroke(
                    Path(roundedRect: mark.frame(in: size), cornerRadius: 4 * baseUnit),
                    with: .color(color),
                    lineWidth: lineWidth
                )
            }

            if let label = mark.label, !label.isEmpty, mark.id != editing {
                let pill = mark.labelRect(in: size)
                shadowed.fill(Path(roundedRect: pill, cornerRadius: pill.height * 0.3), with: .color(color))
                context.draw(
                    Text(label)
                        .font(.system(size: mark.fontSize(in: size), weight: .semibold))
                        .foregroundStyle(Palette.ink(on: mark.color)),
                    at: CGPoint(x: pill.midX, y: pill.midY)
                )
            }
            if mark.id == selected {
                context.stroke(
                    Path(roundedRect: mark.bounds(in: size), cornerRadius: 4),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
            }
        }
    }

    private static func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat,
        color: Color,
        in context: GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = lineWidth * 3.6
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: CGPoint(x: end.x - cos(angle) * head * 0.8, y: end.y - sin(angle) * head * 0.8))
        context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        var tip = Path()
        tip.move(to: end)
        tip.addLine(to: CGPoint(x: end.x - cos(angle - 0.45) * head, y: end.y - sin(angle - 0.45) * head))
        tip.addLine(to: CGPoint(x: end.x - cos(angle + 0.45) * head, y: end.y - sin(angle + 0.45) * head))
        tip.closeSubpath()
        context.fill(tip, with: .color(color))
    }
}
