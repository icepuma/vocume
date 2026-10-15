import Foundation
import Vision

/// A screenshot's OCR text plus its pixels, used to place AI marks on exact words and letters.
///
/// Models are good at deciding *what* to mark but poor at pixel positions, so the AI answers with
/// `{"match": "…"}` marks and ``resolve(_:)`` places them precisely.
public struct RecognizedScreenshot: Sendable {
    /// One recognized line: its text and its box (normalized, top-left origin).
    struct Line: Sendable {
        let text: String
        let box: CGRect
    }

    let lines: [Line]
    let pixels: Pixels

    /// Runs on-device text recognition; `nil` if the image can't be read.
    public init?(contentsOf url: URL) {
        guard let pixels = Pixels(contentsOf: url) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction would "fix" code and identifiers, so matches would no longer fit the pixels.
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(url: url).perform([request])
        lines = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first, let box = text.lineBox else { return nil }
            return Line(text: text.string, box: box)
        }
        self.pixels = pixels
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
    /// Marks without `match` pass through unchanged.
    public func resolve(_ marks: [Mark]) -> [Mark] {
        guard marks.contains(where: { $0.match != nil }) else { return marks }
        let measured = lines.map { TextLine($0, pixels: pixels) }
        return marks.flatMap { mark -> [Mark] in
            guard let query = mark.match, !query.isEmpty else { return [mark] }
            var pattern = NSRegularExpression.escapedPattern(for: query)
            if mark.word == true { pattern = "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])" }
            let options: NSRegularExpression.Options = mark.anyCase == true ? .caseInsensitive : []
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
            return measured.flatMap { line in
                regex.matches(in: line.text, range: NSRange(line.text.startIndex..., in: line.text))
                    .compactMap { Range($0.range, in: line.text) }
                    .map { mark.placed(on: line.locate($0, pixels: pixels), pixels: pixels) }
            }
        }
    }
}

extension Mark {
    /// A copy of this AI mark positioned on a text box (normalized, top-left origin).
    /// Padding is computed in pixels so it is even on both axes: tight for covers, roomier for boxes.
    func placed(on box: CGRect, pixels: Pixels) -> Mark {
        var mark = self
        mark.id = UUID()
        mark.match = nil
        let width = Double(pixels.width)
        let height = Double(pixels.height)
        let lineHeight = box.height * height
        let pad = lineHeight * (kind == .box ? 0.3 : 0.06)
        let rect = box.insetBy(dx: -pad / width, dy: -pad / height)
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
        case .box, .highlight, .redact, .pen:
            mark.x = rect.minX
            mark.y = rect.minY
            mark.w = rect.width
            mark.h = rect.height
        }
        return mark
    }
}
