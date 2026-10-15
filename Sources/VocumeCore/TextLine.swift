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
    /// Pixel columns per word, plus pixel rows for a word set smaller than the rest of the line.
    private var words: [(chars: Range<String.Index>, columns: Range<Int>, rows: Range<Int>?)] = []

    init(_ line: RecognizedScreenshot.Line, pixels: Pixels) {
        text = line.text
        box = line.box
        let lineHeight = box.height * Double(pixels.height)
        (firstColumn, ink) = pixels.inkColumns(
            in: box.insetBy(dx: -lineHeight * 0.1 / Double(pixels.width), dy: 0)
        )
        // Glyphs are runs of ink columns; runs closer than a space belong to the same word (blob).
        let wordGap = max(2, Int(lineHeight * 0.15))
        var blobs: [[Range<Int>]] = []
        for run in Self.runs(in: ink).map({ $0.lowerBound + firstColumn..<$0.upperBound + firstColumn }) {
            if let last = blobs.last?.last, run.lowerBound - last.upperBound < wordGap {
                blobs[blobs.count - 1].append(run)
            } else {
                blobs.append([run])
            }
        }
        let chars = text.split(whereSeparator: \.isWhitespace).map { $0.startIndex..<$0.endIndex }
        let columns: [Range<Int>]
        if line.wordBoxes.count == chars.count {
            let width = Double(pixels.width)
            columns = Self.anchor(blobs, to: line.wordBoxes.map { $0.minX * width...$0.maxX * width })
        } else if chars.count == blobs.count {
            columns = blobs.map { $0[0].lowerBound..<$0[$0.count - 1].upperBound }
        } else {
            return  // gaps don't line up with words (icons, odd spacing): `locate` slices the whole line
        }
        words = zip(chars, columns).map { chars, columns in
            (chars, columns, Self.smallerRows(text[chars], columns: columns, in: box, pixels: pixels))
        }
    }

    /// Box for `text[range]` (normalized, top-left origin): estimate inside its words' real pixel
    /// span, then snap to actual glyph edges.
    func locate(_ range: Range<String.Index>, pixels: Pixels) -> CGRect {
        let imageWidth = Double(pixels.width)
        var reference = text.startIndex..<text.endIndex
        var (spanStart, spanEnd) = (box.minX * imageWidth, box.maxX * imageWidth)
        var (top, height) = (box.minY, box.height)
        if let first = words.first(where: { $0.chars.contains(range.lowerBound) }),
            let last = words.first(where: { $0.chars.contains(text.index(before: range.upperBound)) })
        {
            reference = first.chars.lowerBound..<last.chars.upperBound
            (spanStart, spanEnd) = (Double(first.columns.lowerBound), Double(last.columns.upperBound))
            if let a = first.rows, let b = last.rows {
                let rows = min(a.lowerBound, b.lowerBound)..<max(a.upperBound, b.upperBound)
                (top, height) = (
                    Double(rows.lowerBound) / Double(pixels.height), Double(rows.count) / Double(pixels.height)
                )
            }
        }
        let columns = Int(spanStart)..<max(Int(spanEnd.rounded(.up)), Int(spanStart))
        func columnsRect(_ a: Double, _ b: Double) -> CGRect {
            CGRect(x: a / imageWidth, y: top, width: max(b - a, 1) / imageWidth, height: height)
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

        // Otherwise (touching letters, quotes…): estimate with system-font widths, then snap to a glyph
        // edge within half a letter. An estimate inside ink falls between touching letters, which have
        // no edge between them, so there only an edge right next to it counts.
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
        let letter = (spanEnd - spanStart) / Double(max(letters.count, 1))
        func snap(_ estimate: Double, to edges: [Double]) -> Double {
            let inInk = isInk(Int(estimate) - 1) && isInk(Int(estimate))
            return Self.nearest(to: estimate, in: edges, within: max(letter * (inInk ? 0.2 : 0.5), 2)) ?? estimate
        }
        let a = snap(estimatedStart, to: starts)
        return columnsRect(a, snap(estimatedEnd, to: ends.filter { $0 > a }))
    }

    /// Each word's columns: the blobs lying mostly inside Vision's box for the word. A blob shared by
    /// several words (spaces too narrow to see) is split by glyph; a word with no ink keeps Vision's box.
    private static func anchor(_ blobs: [[Range<Int>]], to boxes: [ClosedRange<Double>]) -> [Range<Int>] {
        func overlap(_ run: Range<Int>, _ box: ClosedRange<Double>) -> Double {
            max(0, min(Double(run.upperBound), box.upperBound) - max(Double(run.lowerBound), box.lowerBound))
        }
        var found = Array(repeating: [Range<Int>](), count: boxes.count)
        for blob in blobs {
            let span = blob[0].lowerBound..<blob[blob.count - 1].upperBound
            if let word = boxes.indices.first(where: { overlap(span, boxes[$0]) * 2 > Double(span.count) }) {
                found[word].append(span)
            } else {
                for glyph in blob {
                    let word = boxes.indices.max { overlap(glyph, boxes[$0]) < overlap(glyph, boxes[$1]) }
                    if let word, overlap(glyph, boxes[word]) > 0 { found[word].append(glyph) }
                }
            }
        }
        return zip(found, boxes).map { runs, box in
            guard let first = runs.first, let last = runs.last else {
                return Int(box.lowerBound)..<Int(box.upperBound.rounded(.up))
            }
            return first.lowerBound..<last.upperBound
        }
    }

    /// The word's own ink rows when it is set in a smaller font than the line's tallest text, so marks
    /// fit it instead of the whole line; `nil` otherwise. Only words with a tall letter (capital, digit,
    /// ascender) tell their size: "on" is short in any font.
    private static func smallerRows(_ word: Substring, columns: Range<Int>, in box: CGRect, pixels: Pixels) -> Range<
        Int
    >? {
        guard word.contains(where: { $0.isUppercase || $0.isNumber || "bdfhkl".contains($0) }) else { return nil }
        func inkRows(_ rect: CGRect) -> Range<Int>? {
            let (firstRow, ink) = pixels.inkRows(in: rect)
            guard let top = ink.firstIndex(of: true), let bottom = ink.lastIndex(of: true) else { return nil }
            return firstRow + top..<firstRow + bottom + 1
        }
        let width = Double(pixels.width)
        guard let line = inkRows(box),
            let rows = inkRows(
                CGRect(
                    x: Double(columns.lowerBound) / width, y: box.minY,
                    width: Double(columns.count) / width, height: box.height))
        else { return nil }
        let smaller = rows.lowerBound - line.lowerBound > line.count * 15 / 100 && rows.count < line.count * 8 / 10
        return smaller ? rows : nil
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
    /// Box of `string[range]`, normalized with a top-left origin (Vision uses bottom-left).
    func box(for range: Range<String.Index>) -> CGRect? {
        guard let box = (try? boundingBox(for: range))??.boundingBox else { return nil }
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }
}
