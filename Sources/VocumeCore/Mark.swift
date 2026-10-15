import CoreGraphics
import Foundation

/// One annotation on a screenshot.
///
/// Positions are fractions (0–1) of the image size, so marks stay put when the view resizes and
/// export at any resolution. The JSON shape is also what the AI is asked to return.
public struct Mark: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// `crop` is never drawn: it is how the AI asks for a crop, and the frame the Crop tool edits.
        case arrow, line, box, ellipse, highlight, redact, pen, text, step, crop
    }

    public var id = UUID()
    public var kind: Kind
    /// Start point (arrows), top-left corner (boxes) or anchor (text, steps).
    public var x: Double
    public var y: Double
    /// Extent from `x`/`y`: an arrow runs to `(x + w, y + h)`.
    public var w: Double?
    public var h: Double?
    public var label: String?
    /// A ``Palette`` colour name; unknown names fall back to red.
    public var color: String?
    /// Size multiplier: 0.6 small, 1 medium, 1.6 large.
    public var size: Double?
    /// Freehand pen points, in the same fractional coordinates.
    public var points: [CGPoint]?
    /// AI only: text to find with OCR. ``RecognizedScreenshot/resolve(_:)`` replaces the mark with
    /// one positioned mark per occurrence.
    public var match: String?
    /// Match whole words only.
    public var word: Bool?
    /// Match ignoring case.
    public var anyCase: Bool?
    /// AI only: longer text around the occurrence meant, so one occurrence of a repeated `match`
    /// can get its own mark or label.
    public var context: String?

    public init(
        kind: Kind,
        x: Double,
        y: Double,
        w: Double? = nil,
        h: Double? = nil,
        label: String? = nil,
        color: String? = nil,
        size: Double? = nil,
        points: [CGPoint]? = nil,
        match: String? = nil,
        word: Bool? = nil,
        anyCase: Bool? = nil,
        context: String? = nil
    ) {
        self.kind = kind
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.label = label
        self.color = color
        self.size = size
        self.points = points
        self.match = match
        self.word = word
        self.anyCase = anyCase
        self.context = context
    }

    enum CodingKeys: String, CodingKey {
        case kind = "type"
        case x, y, w, h, label, color, size, points, match, word, anyCase, context
    }

    /// Lenient decoding for AI replies: marks that use `match` have no position, and an unknown
    /// `type` becomes a box rather than failing the whole reply.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(rawValue: try c.decode(String.self, forKey: .kind)) ?? .box
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        w = try c.decodeIfPresent(Double.self, forKey: .w)
        h = try c.decodeIfPresent(Double.self, forKey: .h)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        size = try c.decodeIfPresent(Double.self, forKey: .size)
        points = try c.decodeIfPresent([CGPoint].self, forKey: .points)
        match = try c.decodeIfPresent(String.self, forKey: .match)
        word = try c.decodeIfPresent(Bool.self, forKey: .word)
        anyCase = try c.decodeIfPresent(Bool.self, forKey: .anyCase)
        context = try c.decodeIfPresent(String.self, forKey: .context)
    }

    /// Whether the mark is an empty text note (one the user started but never typed into).
    public var isEmptyText: Bool { kind == .text && (label ?? "").isEmpty }
}
