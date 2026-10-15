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
            case .arrow: (start, .center)  // label sits on the tail; the arrow points at the thing
            case .step: (CGPoint(x: start.x + 18 * unit, y: start.y), .leading)
            case .pen: (start, .bottomLeading)
            case .box, .highlight, .redact:
                (CGPoint(x: frame(in: size).minX, y: frame(in: size).minY - 6 * unit), .bottomLeading)
            }
        return CGRect(
            origin: CGPoint(x: point.x - pill.width * anchor.x, y: point.y - pill.height * anchor.y),
            size: pill
        )
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
