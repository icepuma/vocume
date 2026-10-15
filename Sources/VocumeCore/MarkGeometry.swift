import AppKit
import SwiftUI

// Geometry shared by drawing, hit-testing, label editing and export. Every size scales with the
// image (see `unit(for:)`), so an exported PNG looks exactly like the editor.
extension Mark {
    /// One size unit for an image of this size: a thousandth of its longer side.
    public static func unit(for size: CGSize) -> CGFloat { max(size.width, size.height) / 1000 }

    public func fontSize(in size: CGSize) -> CGFloat { 16 * Self.unit(for: size) * (self.size ?? 1) }

    /// Start (`x`, `y`) and end (`x + w`, `y + h`) in view coordinates.
    public func endpoints(in size: CGSize) -> (start: CGPoint, end: CGPoint) {
        (
            CGPoint(x: x * size.width, y: y * size.height),
            CGPoint(x: (x + (w ?? 0)) * size.width, y: (y + (h ?? 0)) * size.height)
        )
    }

    /// The rectangle between the endpoints, whichever way it was dragged.
    public func frame(in size: CGSize) -> CGRect {
        let (a, b) = endpoints(in: size)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    public func penPoints(in size: CGSize) -> [CGPoint] {
        (points ?? []).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    /// Where the label pill sits. An empty label is sized as "Text", the editing placeholder.
    public func labelRect(in size: CGSize) -> CGRect {
        let font = fontSize(in: size)
        let unit = Self.unit(for: size) * (self.size ?? 1)
        let start = endpoints(in: size).start
        let text = (label ?? "").isEmpty ? "Text" : label ?? ""
        let measured = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: font, weight: .semibold)]
        ).size()
        let pill = CGSize(width: measured.width + font, height: measured.height + font * 0.6)
        let (point, anchor): (CGPoint, UnitPoint) =
            switch kind {
            case .text: (start, .topLeading)
            case .arrow, .line: (start, .center)  // label sits on the tail; the arrow points at the thing
            case .step: (CGPoint(x: start.x + 18 * unit, y: start.y), .leading)
            case .pen: (start, .bottomLeading)
            case .box, .ellipse, .highlight, .redact, .crop:
                (CGPoint(x: frame(in: size).minX, y: frame(in: size).minY - 6 * unit), .bottomLeading)
            }
        // Kept inside the image, so a label near an edge isn't cut off in the export.
        return CGRect(
            origin: CGPoint(
                x: max(min(point.x - pill.width * anchor.x, size.width - pill.width), 0),
                y: max(min(point.y - pill.height * anchor.y, size.height - pill.height), 0)),
            size: pill
        )
    }

    /// Where the mark can be reshaped by dragging, as points in its own `x`/`y`/`w`/`h` span
    /// (0 = the `x`/`y` side, 1 = the `x + w`/`y + h` side, 0.5 = the middle): an arrow's two ends,
    /// a line's or arrow's two ends, and the corners and edges of boxes, ellipses, highlights and
    /// redactions. Pen, text and steps have none.
    public var handles: [UnitPoint] {
        switch kind {
        case .arrow, .line: [.topLeading, .bottomTrailing]
        case .box, .ellipse, .highlight, .redact, .crop:
            [.topLeading, .top, .topTrailing, .trailing, .bottomTrailing, .bottom, .bottomLeading, .leading]
        case .pen, .text, .step: []
        }
    }

    /// A handle's position in view coordinates.
    public func point(of handle: UnitPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (x + (w ?? 0) * handle.x) * size.width, y: (y + (h ?? 0) * handle.y) * size.height)
    }

    /// Moves `handle` to `point` (fractions of the image) and keeps the opposite side in place.
    /// A box dragged past its opposite edge flips; ``normalize()`` tidies that up afterwards.
    public mutating func move(_ handle: UnitPoint, to point: CGPoint) {
        let (width, height) = (w ?? 0, h ?? 0)
        if handle.x == 0 {
            w = x + width - point.x
            x = point.x
        } else if handle.x == 1 {
            w = point.x - x
        }
        if handle.y == 0 {
            h = y + height - point.y
            y = point.y
        } else if handle.y == 1 {
            h = point.y - y
        }
    }

    /// Shift while drawing: boxes, ellipses, highlights and redactions become square, arrows and
    /// lines snap to 45° steps, keeping the start point. `aspect` is the image's width / height, so
    /// "square" and "45°" hold in pixels.
    public mutating func constrain(aspect: Double) {
        let (dx, dy) = ((w ?? 0) * aspect, h ?? 0)  // in units of the image height
        switch kind {
        case .box, .ellipse, .highlight, .redact, .crop:
            let side = max(abs(dx), abs(dy))
            (w, h) = ((dx < 0 ? -side : side) / aspect, dy < 0 ? -side : side)
        case .arrow, .line:
            let step = Double.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            (w, h) = (cos(angle) * length / aspect, sin(angle) * length)
        case .pen, .text, .step:
            break
        }
    }

    /// Shift while dragging `handle` (after ``move(_:to:)``): a corner keeps the proportions of
    /// `original`; an arrow's or line's end snaps to 45° around the other end. Edges are unaffected.
    public mutating func constrain(_ handle: UnitPoint, from original: Mark, aspect: Double) {
        let unit = CGSize(width: 1, height: 1)
        switch kind {
        case .arrow, .line:
            let end = point(of: .bottomTrailing, in: unit)
            constrain(aspect: aspect)
            if handle == .topLeading {  // dragging the start: the end stays put
                (x, y) = (end.x - (w ?? 0), end.y - (h ?? 0))
            }
        case .box, .ellipse, .highlight, .redact, .crop:
            guard handle.x != 0.5, handle.y != 0.5 else { return }
            let anchor = original.point(of: UnitPoint(x: 1 - handle.x, y: 1 - handle.y), in: unit)
            let was = original.point(of: handle, in: unit)
            let now = point(of: handle, in: unit)
            let (wasX, wasY) = (was.x - anchor.x, was.y - anchor.y)
            guard wasX != 0, wasY != 0 else { return }
            let (nowX, nowY) = (now.x - anchor.x, now.y - anchor.y)
            let scale = max(abs(nowX / wasX), abs(nowY / wasY))
            let corner = CGPoint(
                x: anchor.x + (nowX < 0 ? -1 : 1) * abs(wasX) * scale,
                y: anchor.y + (nowY < 0 ? -1 : 1) * abs(wasY) * scale)
            move(handle, to: corner)
        case .pen, .text, .step:
            break
        }
    }

    /// Gives boxes, ellipses, highlights and redactions a positive width and height, whichever way
    /// they were drawn or resized. Arrows and lines keep their direction.
    public mutating func normalize() {
        guard [.box, .ellipse, .highlight, .redact, .crop].contains(kind), let width = w, let height = h else {
            return
        }
        x = min(x, x + width)
        y = min(y, y + height)
        (w, h) = (abs(width), abs(height))
    }

    /// The area the AI's crop items ask for (fractions of the image): all of them together, kept
    /// inside the image. `nil` without crop items, or if they enclose nothing.
    public static func cropArea(of marks: [Mark]) -> CGRect? {
        let crops = marks.filter { $0.kind == .crop }.map { $0.frame(in: CGSize(width: 1, height: 1)) }
        guard let first = crops.first else { return nil }
        let area = crops.dropFirst().reduce(first) { $0.union($1) }.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1))
        return area.isNull || area.width < 0.01 || area.height < 0.01 ? nil : area
    }

    /// The step marker's circle.
    func stepCircle(in size: CGSize) -> CGRect {
        let unit = Self.unit(for: size) * (self.size ?? 1)
        let center = endpoints(in: size).start
        return CGRect(x: center.x - 14 * unit, y: center.y - 14 * unit, width: 28 * unit, height: 28 * unit)
    }

    /// The clickable area, including the label, in view coordinates.
    public func bounds(in size: CGSize) -> CGRect {
        if kind == .text { return labelRect(in: size).insetBy(dx: -4, dy: -4) }
        let unit = Self.unit(for: size) * (self.size ?? 1)
        let start = endpoints(in: size).start
        var rect =
            switch kind {
            case .step: stepCircle(in: size)
            case .pen:
                penPoints(in: size).reduce(CGRect(origin: start, size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }
            default: frame(in: size)
            }
        rect = rect.insetBy(dx: -6 * unit, dy: -6 * unit)
        if let label, !label.isEmpty { rect = rect.union(labelRect(in: size)) }
        return rect
    }
}
