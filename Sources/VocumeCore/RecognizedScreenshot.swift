import Foundation
import ImageIO
import OSLog
import Synchronization
import Vision

private let ocrLog = Logger(subsystem: "dev.icepuma.vocume", category: "ocr")

/// A screenshot's OCR text plus its pixels, used to place AI marks on exact words and letters.
///
/// Models are good at deciding *what* to mark but poor at pixel positions, so the AI answers with
/// `{"match": "…"}` marks and ``resolve(_:)`` places them precisely.
public struct RecognizedScreenshot: Sendable {
    /// One recognized line: its text and its box (normalized, top-left origin).
    struct Line: Sendable {
        let text: String
        let box: CGRect
        /// Vision's box per whitespace-separated word, same space as `box`. A few pixels loose, but
        /// unlike the line box they follow words set in a different font size.
        var wordBoxes: [CGRect] = []
        /// Vision's confidence: 1 for a clean reading, 0.3 for garbled text such as tiny grey print.
        var confidence: Float = 1
    }

    let lines: [Line]
    let pixels: Pixels

    /// Runs on-device text recognition; `nil` if the image can't be read.
    public init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.init(image: image)
    }

    /// Several recognition passes, merged by what they read (measured on macOS 27 screenshots):
    /// - 1× and 2×: at 2× Vision reads small and mixed-size text far better, but on Retina captures it
    ///   sometimes garbles what 1× reads cleanly ("Sign up" upside down), so neither pass may hide
    ///   the other's reading.
    /// - a margin in the background colour around every pass, without which text cut at the top or
    ///   bottom edge isn't read at all;
    /// - overlapping tiles for images too large to double: Vision shrinks big images until small
    ///   text disappears (a 5000 px strip read nothing at all);
    /// - 2× tiles, each turned dark-on-light when its background is dark: only this pass reads small
    ///   text in coloured chips, such as a diff's green "+6" and red "−6" in dark mode (on Retina
    ///   captures it found every number the others missed, and lost none on light screenshots).
    public init?(image: CGImage) {
        guard let pixels = Pixels(image) else { return nil }
        let border = pixels.borderColor
        // Each read is (pass, tile, scale, inverted); they are independent, so they run in parallel.
        typealias Read = (pass: Int, tile: CGRect?, scale: Double, invert: Bool)
        var reads: [Read] = [(0, nil, 1, false)]
        if image.width * image.height > 8_000_000 {
            reads += Self.tiles(of: image, size: 2048).map { (1, $0, 1, false) }
        } else {
            reads.append((1, nil, 2, false))
        }
        reads += Self.tiles(of: image, size: 1024).map { (2, $0, 2, pixels.isDark($0)) }
        let all = reads
        let results = Mutex([[Line]](repeating: [], count: reads.count))
        DispatchQueue.concurrentPerform(iterations: all.count) { index in
            let read = all[index]
            let lines = Self.recognize(image, scale: read.scale, tile: read.tile, border: border, invert: read.invert)
            results.withLock { $0[index] = lines }
        }
        let read = results.withLock { $0 }
        let passes = (0..<3).map { pass in reads.indices.filter { reads[$0].pass == pass }.flatMap { read[$0] } }
        lines = Self.merged(passes)
        self.pixels = pixels
    }

    /// Reads a tiny image once, off the main actor: the first recognition after an app update takes
    /// up to half a minute while Vision prepares its models.
    public static func warmUp() {
        guard
            let context = CGContext(
                data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let image = context.makeImage()
        else { return }
        _ = recognize(image, scale: 1, border: (255, 255, 255))
    }

    /// One pass over the image (or one tile of it, in pixels) scaled by `scale`, inside a margin of
    /// the border colour, colours inverted if `invert`; boxes are mapped back to the whole image
    /// (normalized, top-left origin).
    private static func recognize(
        _ image: CGImage, scale: Double, tile: CGRect? = nil, border: (red: Int, green: Int, blue: Int),
        invert: Bool = false
    ) -> [Line] {
        let area = tile ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let scaled = CGSize(width: area.width * scale, height: area.height * scale)
        let margin = max(16, max(scaled.width, scaled.height) * 0.04).rounded()
        let size = CGSize(width: (scaled.width + 2 * margin).rounded(), height: (scaled.height + 2 * margin).rounded())
        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.setFillColor(
            CGColor(
                red: Double(border.red) / 255, green: Double(border.green) / 255, blue: Double(border.blue) / 255,
                alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.saveGState()
        context.clip(to: CGRect(x: margin, y: margin, width: scaled.width, height: scaled.height))
        context.interpolationQuality = .high
        let (width, height) = (Double(image.width), Double(image.height))
        // CoreGraphics draws from the bottom left; place the tile's top-left corner at the margin.
        context.draw(
            image,
            in: CGRect(
                x: margin - area.minX * scale, y: margin - (height - area.maxY) * scale, width: width * scale,
                height: height * scale))
        context.restoreGState()
        if invert {
            context.setBlendMode(.difference)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let padded = context.makeImage() else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction would "fix" code and identifiers, so matches would no longer fit the pixels.
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: padded).perform([request])
        } catch {
            ocrLog.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
        }
        // A box in the padded pass image, in the whole image's normalized coordinates.
        func mapped(_ box: CGRect) -> CGRect {
            let x = (box.minX * size.width - margin) / scale + area.minX
            let y = (box.minY * size.height - margin) / scale + area.minY
            return CGRect(
                x: x / width, y: y / height, width: box.width * size.width / scale / width,
                height: box.height * size.height / scale / height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first,
                let box = text.box(for: text.string.startIndex..<text.string.endIndex).map(mapped), !box.isNull
            else { return nil }
            let words = text.string.split(whereSeparator: \.isWhitespace).compactMap { word -> CGRect? in
                guard let box = text.box(for: word.startIndex..<word.endIndex).map(mapped), !box.isNull else {
                    return nil
                }
                return box
            }
            return Line(text: text.string, box: box, wordBoxes: words, confidence: text.confidence)
        }
    }

    /// Overlapping tiles (in pixels) of `size` covering the image; the overlap holds a whole word
    /// that one tile cuts.
    private static func tiles(of image: CGImage, size: Double) -> [CGRect] {
        let overlap = 256.0
        let (width, height) = (Double(image.width), Double(image.height))
        let xs = stride(from: 0.0, to: max(width - overlap, 1), by: size - overlap)
        let ys = stride(from: 0.0, to: max(height - overlap, 1), by: size - overlap)
        return ys.flatMap { y in
            xs.map { x in CGRect(x: x, y: y, width: min(size, width - x), height: min(size, height - y)) }
        }
    }

    /// The passes' lines, each region once: a line is dropped when an overlapping line already
    /// reads the same text (or more of it), or reads it with far more confidence. Readings that
    /// disagree with equal confidence are both kept, so a garbled pass can't hide a good one; marks
    /// landing twice on one spot are merged in ``resolve(_:)``. A low-confidence line with no
    /// confident rival stays: it is sometimes the only reading of a number.
    static func merged(_ passes: [[Line]]) -> [Line] {
        func key(_ text: String) -> String {
            String(Fold.digits(text).lowercased().filter { !$0.isWhitespace }.map { $0 == "o" ? "0" : $0 })
        }
        func overlap(_ a: CGRect, _ b: CGRect) -> Double {
            let shared = a.intersection(b)
            guard !shared.isNull else { return 0 }
            return shared.width * shared.height / max(min(a.width * a.height, b.width * b.height), 1e-9)
        }
        var kept: [(line: Line, key: String)] = []
        // Confident readings first (in pass order among equals), so a garbled rival meets them.
        let ordered = passes.joined().enumerated().sorted {
            ($1.element.confidence, $0.offset) < ($0.element.confidence, $1.offset)
        }
        for line in ordered.map(\.element) {
            let text = key(line.text)
            guard !text.isEmpty,
                !kept.contains(where: {
                    $0.line.confidence - line.confidence >= 0.5 && overlap($0.line.box, line.box) > 0.5
                })
            else { continue }
            if let index = kept.firstIndex(where: {
                overlap($0.line.box, line.box) > 0.5 && ($0.key.contains(text) || text.contains($0.key))
            }) {
                if text.count > kept[index].key.count { kept[index] = (line, text) }
            } else {
                kept.append((line, text))
            }
        }
        return kept.map(\.line)
    }

    init(lines: [Line], pixels: Pixels) {
        self.lines = lines
        self.pixels = pixels
    }

    /// The recognized lines as `x,y,w,h  text` (normalized, top-left origin), for the AI prompt.
    public var textSummary: String {
        lines.prefix(300).map { line in
            let b = line.box
            return String(format: "%.3f,%.3f,%.3f,%.3f  ", b.minX, b.minY, b.width, b.height) + line.text
        }.joined(separator: "\n")
    }

    /// Replaces every mark that has a `match` with one positioned mark per occurrence of that text.
    /// Marks without `match` pass through unchanged. Models often repeat a match once per occurrence
    /// they see; each already covers every occurrence, so identical results are kept once.
    public func resolve(_ marks: [Mark]) -> [Mark] {
        guard marks.contains(where: { $0.match != nil || $0.pattern != nil || $0.detect != nil }) else {
            return marks
        }
        let measured = lines.map { TextLine($0, pixels: pixels) }
        return marks.flatMap { mark -> [Mark] in
            let anyCase = mark.anyCase == true
            var hits: [(line: Int, range: Range<String.Index>)]
            if let kind = mark.detect.flatMap({
                TextKind(rawValue: $0.lowercased().trimmingCharacters(in: .whitespaces))
            }) {
                // A class of text ("every number", "all red text"): a fixed detector finds each one.
                hits = measured.enumerated().flatMap { index, line in
                    guard let color = kind.color else {
                        return kind.ranges(in: line.text).map { (line: index, range: $0) }
                    }
                    return line.wordRects(pixels: pixels).filter { pixels.inkColor(in: $0.rect) == color }.map {
                        (line: index, range: $0.chars)
                    }
                }
            } else if let pattern = mark.pattern, !pattern.isEmpty {
                // A class of text ("every number"): the app finds each one, so none depends on the
                // model listing it. An invalid expression places nothing.
                guard let regex = try? NSRegularExpression(pattern: pattern, options: anyCase ? .caseInsensitive : [])
                else { return [] }
                hits = measured.enumerated().flatMap { index, line in
                    regex.matches(in: line.text, range: NSRange(line.text.startIndex..., in: line.text))
                        .compactMap { Range($0.range, in: line.text) }
                        .filter { !$0.isEmpty }
                        .map { (line: index, range: $0) }
                }
            } else if let query = mark.match, !query.isEmpty {
                hits = Self.find(
                    query, wholeWords: mark.word == true, anyCase: anyCase, in: measured,
                    firstPieceOnly: ![.box, .ellipse, .highlight, .redact, .line, .crop].contains(mark.kind))
            } else {
                return [mark]
            }
            // A cover over a found class takes the whole token: "v0.5.3", never "v0.■". Overlapping
            // hits (two detectors finding one phone number) become one.
            if mark.detect != nil || mark.pattern != nil {
                if mark.kind == .redact {
                    hits = hits.map { (line: $0.line, range: Self.token(around: $0.range, in: measured[$0.line].text)) }
                }
                hits = Self.merged(hits)
            }
            // A context narrows a repeated match to the occurrence inside it (ignored if it's nowhere).
            if let context = mark.context, !context.isEmpty {
                let around = Self.find(context, wholeWords: false, anyCase: anyCase, in: measured)
                if !around.isEmpty {
                    hits = hits.filter { hit in
                        around.contains {
                            $0.line == hit.line && $0.range.lowerBound <= hit.range.lowerBound
                                && hit.range.upperBound <= $0.range.upperBound
                        }
                    }
                }
            }
            return hits.map {
                mark.placed(
                    on: measured[$0.line].locate($0.range, pixels: pixels, covering: mark.kind == .redact),
                    pixels: pixels)
            }
        }.reduce(into: []) { kept, mark in
            if !kept.contains(where: { $0.isDuplicate(of: mark) }) { kept.append(mark) }
        }
    }
}

extension RecognizedScreenshot {
    /// Redactions after checking: the marks with any covers the re-check added, how many it added,
    /// and how many it still found in its last round (covered, but not checked again).
    public struct Checked: Sendable {
        public let marks: [Mark]
        public let repaired: Int
        public let unconfirmed: Int
    }

    /// Checks redactions the way redaction workflows do: paints the covers into the image, reads it
    /// again and runs the class requests (detectors, patterns) on what is still visible. Whatever
    /// turns up is covered too, for up to three rounds; OCR and cover placement can each miss a
    /// little, and a miss here is a leak. Matches aren't run again: their text is covered by then,
    /// so a match would fall back to look-alikes ("11" finding the "ll" in "still"). Requests narrowed
    /// by a `context` aren't either: the context is covered too, and without it they'd cover every
    /// occurrence on screen. A cover cut short is still widened to the whole word.
    public func checkingRedactions(_ marks: [Mark], requested: [Mark]) -> Checked {
        let requests = requested.filter {
            $0.kind == .redact && ($0.detect != nil || $0.pattern != nil) && ($0.context ?? "").isEmpty
        }
        guard !requests.isEmpty else { return Checked(marks: marks, repaired: 0, unconfirmed: 0) }
        let measured = lines.map { TextLine($0, pixels: pixels) }
        var all = marks
        var (repaired, lastFound) = (0, 0)
        for _ in 0..<3 {
            let widened = completingWords(all, measured: measured)
            all = widened.marks
            repaired += widened.count
            let covers = all.filter { $0.kind == .redact }.map { $0.frame(in: CGSize(width: 1, height: 1)) }
            guard let image = pixels.image(covering: covers), let reread = RecognizedScreenshot(image: image) else {
                break
            }
            let found = reread.resolve(requests).filter { new in !all.contains { $0.isDuplicate(of: new) } }
            lastFound = found.count
            guard !found.isEmpty else { break }
            all += found
            repaired += found.count
        }
        return Checked(marks: all, repaired: repaired, unconfirmed: lastFound)
    }

    /// Covers that cut through a word, widened to the whole word: half a word showing is a leak,
    /// whatever OCR makes of the visible half ("v0.■" reads as "vO.", no digit left to detect).
    private func completingWords(_ marks: [Mark], measured: [TextLine]) -> (marks: [Mark], count: Int) {
        var count = 0
        let unit = CGSize(width: 1, height: 1)
        let completed = marks.map { mark -> Mark in
            guard mark.kind == .redact else { return mark }
            var cover = mark.frame(in: unit)
            for line in measured where line.box.intersection(cover).height > line.box.height * 0.3 {
                for word in line.text.split(whereSeparator: \.isWhitespace) {
                    let rect = line.locate(word.startIndex..<word.endIndex, pixels: pixels, covering: true)
                    let shared = rect.intersection(cover)
                    if !shared.isNull, shared.width > 0, shared.width < rect.width * 0.95 { cover = cover.union(rect) }
                }
            }
            guard cover != mark.frame(in: unit) else { return mark }
            count += 1
            var widened = mark
            (widened.x, widened.y, widened.w, widened.h) = (cover.minX, cover.minY, cover.width, cover.height)
            return widened
        }
        return (completed, count)
    }

    /// OCR's look-alike characters: Vision reads "v0.4.0" as "vO.4.0", "l" as "1", a small "6" as the
    /// Cyrillic "б", a minus as a dash, and typographic quotes as straight ones (measured on macOS 27).
    private static let lookalikes: [Set<Character>] = [
        ["0", "O", "o", "О", "о", "ø", "Ø"], ["1", "l", "I", "|", "ł"], ["5", "S"], ["8", "B"], ["6", "б", "Б"],
        ["3", "З", "з"], ["-", "−", "–", "—"], ["'", "’", "‘"], ["\"", "“", "”"],
    ]

    /// The whitespace-delimited token(s) around `range`.
    fileprivate static func token(around range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var (lower, upper) = (range.lowerBound, range.upperBound)
        while lower > text.startIndex, !text[text.index(before: lower)].isWhitespace {
            lower = text.index(before: lower)
        }
        while upper < text.endIndex, !text[upper].isWhitespace { upper = text.index(after: upper) }
        return lower..<upper
    }

    /// Hits on the same line that overlap or touch, merged into one.
    fileprivate static func merged(_ hits: [(line: Int, range: Range<String.Index>)]) -> [(
        line: Int, range: Range<String.Index>
    )] {
        hits.sorted { ($0.line, $0.range.lowerBound) < ($1.line, $1.range.lowerBound) }.reduce(into: []) {
            merged, hit in
            if let last = merged.last, last.line == hit.line, hit.range.lowerBound <= last.range.upperBound {
                merged[merged.count - 1].range =
                    last.range.lowerBound..<max(last.range.upperBound, hit.range.upperBound)
            } else {
                merged.append(hit)
            }
        }
    }

    /// Every occurrence of `text` in the lines, tolerating OCR's slips: look-alike characters count
    /// as equal, and spacing may differ (inline code reads as "install. sh", or loses its spaces), so
    /// a stray space may sit between any two characters and the text's own spaces are optional. OCR
    /// slips on some copies of a text and not others, and the AI may copy either spelling. Text with
    /// fewer than 3 other characters ("0", "lol") would match too much that way, so it matches
    /// exactly and falls back to the tolerant search only when there is no exact match at all.
    ///
    /// Text that wraps onto the next line is found too, as one piece per line; `firstPieceOnly`
    /// keeps just the first (an arrow or a step should point once).
    fileprivate static func find(
        _ text: String, wholeWords: Bool, anyCase: Bool, in lines: [TextLine], firstPieceOnly: Bool = false
    ) -> [(line: Int, range: Range<String.Index>)] {
        let text = text.trimmingCharacters(in: .whitespaces)
        let distinctive =
            text.filter { character in
                !character.isWhitespace && !lookalikes.contains { $0.contains(character) }
            }.count >= 3
        for tolerant in distinctive ? [true] : [false, true] {
            guard let regex = regex(for: text, tolerant: tolerant, wholeWords: wholeWords, anyCase: anyCase) else {
                return []
            }
            let hits = lines.enumerated().flatMap { index, line in
                regex.matches(in: line.text, range: NSRange(line.text.startIndex..., in: line.text))
                    .compactMap { Range($0.range, in: line.text) }
                    .filter { !tolerant || Self.sharesALetter(line.text[$0], with: text) }
                    .map { (line: index, range: $0) }
            }
            if !hits.isEmpty { return hits }
        }
        guard let regex = regex(for: text, tolerant: true, wholeWords: wholeWords, anyCase: anyCase) else { return [] }
        return wrapped(regex, in: lines, firstPieceOnly: firstPieceOnly)
    }

    /// Whether a look-alike match keeps at least one of the text's own characters: "-б" for "-6"
    /// does, but "ll" (in "still") for "11" is a different word, not a misread.
    private static func sharesALetter(_ found: Substring, with text: String) -> Bool {
        found.contains { !$0.isWhitespace && text.contains($0) }
    }

    private static func regex(for text: String, tolerant: Bool, wholeWords: Bool, anyCase: Bool) -> NSRegularExpression?
    {
        var pattern =
            tolerant
            ? text.map { character in
                if character.isWhitespace { return "\\s*" }
                return lookalikes.first { $0.contains(character) }.map {
                    "(?:"
                        + $0.sorted().map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
                        + ")"
                } ?? NSRegularExpression.escapedPattern(for: String(character))
            }.joined(separator: "\\s?")
            : NSRegularExpression.escapedPattern(for: text)
        if wholeWords { pattern = "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])" }
        return try? NSRegularExpression(pattern: pattern, options: anyCase ? .caseInsensitive : [])
    }

    /// Matches running from the end of a line into the line just below it (wrapped sentences, an
    /// email or URL broken across lines), as one piece per line.
    private static func wrapped(
        _ regex: NSRegularExpression, in lines: [TextLine], firstPieceOnly: Bool
    ) -> [(line: Int, range: Range<String.Index>)] {
        lines.indices.flatMap { upper -> [(line: Int, range: Range<String.Index>)] in
            let top = lines[upper]
            // The next line down: starts below this one's middle, within a line's height, overlapping it sideways.
            let below = lines.indices.filter { index in
                let box = lines[index].box
                return box.minY > top.box.midY && box.minY - top.box.maxY < top.box.height
                    && box.minX < top.box.maxX && box.maxX > top.box.minX
            }.min { lines[$0].box.minY < lines[$1].box.minY }
            guard let lower = below else { return [] }
            let joined = top.text + " " + lines[lower].text
            let joint = top.text.count  // the joining space
            return regex.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)).flatMap {
                match -> [(line: Int, range: Range<String.Index>)] in
                guard let range = Range(match.range, in: joined) else { return [] }
                let (start, end) = (
                    joined.distance(from: joined.startIndex, to: range.lowerBound),
                    joined.distance(from: joined.startIndex, to: range.upperBound)
                )
                guard start < joint, end > joint + 1 else { return [] }  // within one line: found already
                let top = lines[upper].text, bottom = lines[lower].text
                let first = (line: upper, range: top.index(top.startIndex, offsetBy: start)..<top.endIndex)
                let second = (
                    line: lower, range: bottom.startIndex..<bottom.index(bottom.startIndex, offsetBy: end - joint - 1)
                )
                return firstPieceOnly ? [first] : [first, second]
            }
        }
    }
}

extension Mark {
    /// The same mark on (nearly) the same spot: found twice, by repeated matches or by two OCR
    /// readings of one line.
    func isDuplicate(of other: Mark) -> Bool {
        guard kind == other.kind, color == other.color, label == other.label, size == other.size else { return false }
        let unit = CGSize(width: 1, height: 1)
        let (a, b) = (frame(in: unit), other.frame(in: unit))
        // Points (steps, notes) and flat lines: two OCR readings of one line place them a few pixels apart.
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else {
            return abs(x - other.x) < 0.005 && abs(y - other.y) < 0.005 && abs(a.width - b.width) < 0.01
        }
        let shared = a.intersection(b)
        guard !shared.isNull else { return false }
        return shared.width * shared.height / (a.union(b).width * a.union(b).height) > 0.6
    }

    /// A copy of this AI mark positioned on a text box (normalized, top-left origin).
    /// Padding is computed in pixels so it is even on both axes: tight for covers, roomier for boxes.
    func placed(on box: CGRect, pixels: Pixels) -> Mark {
        var mark = self
        mark.id = UUID()
        mark.match = nil
        mark.pattern = nil
        mark.detect = nil
        let width = Double(pixels.width)
        let height = Double(pixels.height)
        let lineHeight = box.height * height
        // Covers hug the text, boxes leave room, a crop keeps some of what surrounds it.
        let pad = lineHeight * (kind == .crop ? 2 : kind == .box || kind == .ellipse ? 0.3 : 0.06)
        var rect = box.insetBy(dx: -pad / width, dy: -pad / height)
        if kind == .ellipse {  // an ellipse through the box's corners encloses it: √2 × each axis
            rect = rect.insetBy(dx: -rect.width * 0.207, dy: -rect.height * 0.207)
        }
        switch kind {
        case .arrow:  // points at the text from up-left
            mark.x = rect.minX - 2.5 * lineHeight / width
            mark.y = rect.midY - 1.5 * lineHeight / height
            mark.w = 2.3 * lineHeight / width
            mark.h = 1.5 * lineHeight / height
        case .step:
            mark.x = rect.minX - 0.8 * lineHeight / width
            mark.y = rect.midY
        case .text:
            mark.x = rect.minX
            mark.y = rect.maxY + pad / height
        case .line:  // underlines the text
            mark.x = rect.minX
            mark.y = rect.maxY
            mark.w = rect.width
            mark.h = 0
        case .box, .ellipse, .highlight, .redact, .pen, .crop:
            mark.x = rect.minX
            mark.y = rect.minY
            mark.w = rect.width
            mark.h = rect.height
        }
        return mark
    }
}
