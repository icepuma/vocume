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
            case .line:
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                shadowed.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            case .ellipse:
                shadowed.stroke(Path(ellipseIn: mark.frame(in: size)), with: .color(color), lineWidth: lineWidth)
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
            case .crop:
                continue  // an instruction, not ink
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
            if mark.id == selected { drawSelection(of: mark, in: context, size: size) }
        }
    }

    /// The dashed accent outline, plus round handles where the mark can be reshaped. The outline
    /// runs through the handles for boxes; an arrow shows only its two end handles.
    private static func drawSelection(of mark: Mark, in context: GraphicsContext, size: CGSize) {
        let dashed = StrokeStyle(lineWidth: 1.5, dash: [5, 4])
        switch mark.kind {
        case .arrow, .line, .crop: break
        case .box, .ellipse, .highlight, .redact:
            context.stroke(Path(mark.frame(in: size)), with: .color(.accentColor), style: dashed)
        case .pen, .text, .step:
            context.stroke(
                Path(roundedRect: mark.bounds(in: size), cornerRadius: 4), with: .color(.accentColor), style: dashed)
        }
        drawHandles(of: mark, in: context, size: size)
    }

    /// The Crop tool's frame: everything outside it dimmed, a white edge and the 8 resize handles.
    /// `crop` is in fractions of the image.
    public static func drawCrop(_ crop: CGRect, in context: GraphicsContext, size: CGSize) {
        let frame = CGRect(
            x: crop.minX * size.width, y: crop.minY * size.height,
            width: crop.width * size.width, height: crop.height * size.height)
        var outside = Path(CGRect(origin: .zero, size: size))
        outside.addRect(frame)
        context.fill(outside, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        var lifted = context
        lifted.addFilter(.shadow(color: .black.opacity(0.4), radius: 2))
        lifted.stroke(Path(frame), with: .color(.white), lineWidth: 1.5)
        let proxy = Mark(kind: .crop, x: crop.minX, y: crop.minY, w: crop.width, h: crop.height)
        drawHandles(of: proxy, in: context, size: size)
    }

    /// Round handles (9pt, white with an accent ring) where the mark can be reshaped.
    private static func drawHandles(of mark: Mark, in context: GraphicsContext, size: CGSize) {
        var lifted = context
        lifted.addFilter(.shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5))
        for handle in mark.handles {
            let center = mark.point(of: handle, in: size)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
            lifted.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(.accentColor), lineWidth: 1.5)
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
