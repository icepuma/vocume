import AppKit
import Vision

/// One OCR line measured against the pixels: its ink columns plus each word's real pixel span.
///
/// Vision's boxes for parts of a line drift by a letter or two; only the whole-line box is precise.
/// So letters are located by mapping them onto ink runs found in the line's pixels.
struct TextLine {
    let text: String
    /// Normalized, top-left origin.
    let box: CGRect
    private let firstColumn: Int
    private let ink: [Bool]
    private var words: [(chars: Range<String.Index>, columns: Range<Int>)] = []

    init(_ line: RecognizedScreenshot.Line, pixels: Pixels) {
        text = line.text
        box = line.box
        let lineHeight = box.height * Double(pixels.height)
        (firstColumn, ink) = pixels.inkColumns(
            in: box.insetBy(dx: -lineHeight * 0.1 / Double(pixels.width), dy: 0)
        )
        // Glyphs are runs of ink columns; runs closer than a space belong to the same word.
        let wordGap = max(2, Int(lineHeight * 0.15))
        var blobs: [Range<Int>] = []
        for run in Self.runs(in: ink) {
            if let last = blobs.last, run.lowerBound - last.upperBound < wordGap {
                blobs[blobs.count - 1] = last.lowerBound..<run.upperBound
            } else {
                blobs.append(run)
            }
        }
        let chars = text.split(whereSeparator: \.isWhitespace).map { $0.startIndex..<$0.endIndex }
        // If gaps don't line up 1:1 with words (icons, odd spacing), `locate` slices the whole line.
        if chars.count == blobs.count {
            words = zip(chars, blobs).map { ($0, $1.lowerBound + firstColumn..<$1.upperBound + firstColumn) }
        }
    }

    /// Box for `text[range]` (normalized, top-left origin): estimate inside its words' real pixel
    /// span, then snap to actual glyph edges.
    func locate(_ range: Range<String.Index>, pixels: Pixels) -> CGRect {
        let imageWidth = Double(pixels.width)
        var reference = text.startIndex..<text.endIndex
        var (spanStart, spanEnd) = (box.minX * imageWidth, box.maxX * imageWidth)
        if let first = words.first(where: { $0.chars.contains(range.lowerBound) }),
            let last = words.first(where: { $0.chars.contains(text.index(before: range.upperBound)) })
        {
            reference = first.chars.lowerBound..<last.chars.upperBound
            (spanStart, spanEnd) = (Double(first.columns.lowerBound), Double(last.columns.upperBound))
        }
        let columns = Int(spanStart)..<max(Int(spanEnd.rounded(.up)), Int(spanStart))
        func columnsRect(_ a: Double, _ b: Double) -> CGRect {
            CGRect(x: a / imageWidth, y: box.minY, width: max(b - a, 1) / imageWidth, height: box.height)
        }

        // Exact case: one ink run per letter (monospace, most UI text), so letters map to runs.
        let letters = text[reference].indices.filter { !text[$0].isWhitespace }
        let glyphs = Self.runs(in: columns.map(isInk)).map {
            $0.lowerBound + columns.lowerBound..<$0.upperBound + columns.lowerBound
        }
        if glyphs.count == letters.count,
            let i0 = letters.firstIndex(where: { $0 >= range.lowerBound }),
            let i1 = letters.lastIndex(where: { $0 < range.upperBound }),
            i0 <= i1
        {
            return columnsRect(Double(glyphs[i0].lowerBound), Double(glyphs[i1].upperBound))
        }

        // Otherwise (touching letters, quotes…): estimate with system-font widths, then snap to
        // glyph edges near the estimate. Touching letters have no edge between them, hence the tolerance.
        let width = { (s: Substring) in
            NSAttributedString(string: String(s), attributes: [.font: NSFont.systemFont(ofSize: 100)]).size().width
        }
        let total = max(width(text[reference]), 1)
        let estimatedStart =
            spanStart + (spanEnd - spanStart) * width(text[reference.lowerBound..<range.lowerBound]) / total
        let estimatedEnd =
            spanStart + (spanEnd - spanStart) * width(text[reference.lowerBound..<range.upperBound]) / total
        let starts = columns.filter { isInk($0) && !isInk($0 - 1) }.map(Double.init)
        let ends = columns.filter { isInk($0) && !isInk($0 + 1) }.map { Double($0 + 1) }
        let tolerance = max((estimatedEnd - estimatedStart) * 0.5, 2)
        let a = Self.nearest(to: estimatedStart, in: starts, within: tolerance) ?? estimatedStart
        let b = Self.nearest(to: estimatedEnd, in: ends.filter { $0 > a }, within: tolerance) ?? estimatedEnd
        return columnsRect(a, b)
    }

    private func isInk(_ column: Int) -> Bool {
        ink.indices.contains(column - firstColumn) && ink[column - firstColumn]
    }

    /// Ranges of consecutive `true` values.
    private static func runs(in flags: [Bool]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for (i, on) in (flags + [false]).enumerated() {
            if on, start == nil { start = i }
            if !on, let s = start {
                runs.append(s..<i)
                start = nil
            }
        }
        return runs
    }

    private static func nearest(to target: Double, in values: [Double], within tolerance: Double) -> Double? {
        values.min { abs($0 - target) < abs($1 - target) }.flatMap { abs($0 - target) <= tolerance ? $0 : nil }
    }
}

extension VNRecognizedText {
    /// The whole line's box, normalized with a top-left origin (Vision uses bottom-left).
    var lineBox: CGRect? {
        guard let box = (try? boundingBox(for: string.startIndex..<string.endIndex))??.boundingBox else { return nil }
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }
}
