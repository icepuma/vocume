import AppKit
import Testing

@testable import VocumeCore

/// Renders text at a known position, so the true pixel span of every letter is known exactly.
@MainActor
private struct RenderedText {
    let attributed: NSAttributedString
    let origin = CGPoint(x: 40, y: 30)
    let image: CGImage
    let line: RecognizedScreenshot.Line

    var text: String { attributed.string }

    init(_ text: String, font: NSFont = .systemFont(ofSize: 40), background: NSColor = .white, ink: NSColor = .black) {
        self.init(
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink]), background: background)
    }

    init(_ attributed: NSAttributedString, background: NSColor = .white) {
        self.attributed = attributed
        let textSize = attributed.size()
        let width = Int(textSize.width + origin.x * 2)
        let height = Int(textSize.height + origin.y * 2)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)  // top-left origin, like the screenshots
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        background.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        attributed.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
        image = context.makeImage()!
        line = .init(
            text: attributed.string,
            box: CGRect(
                x: origin.x / Double(width), y: origin.y / Double(height),
                width: textSize.width / Double(width), height: textSize.height / Double(height)))
    }

    var screenshot: RecognizedScreenshot { RecognizedScreenshot(lines: [line], pixels: Pixels(image)!) }

    /// Recognized from a PNG file with real Vision text recognition, like a capture.
    func recognized() throws -> RecognizedScreenshot {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocume-test-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
        return try #require(RecognizedScreenshot(contentsOf: url))
    }

    /// Horizontal pixel range of `text[range]`, measured with the same fonts.
    func span(of range: Range<String.Index>) -> ClosedRange<Double> {
        let characters = NSRange(range, in: text)
        let start =
            origin.x
            + attributed.attributedSubstring(from: NSRange(location: 0, length: characters.location)).size().width
        return start...(start + attributed.attributedSubstring(from: characters).size().width)
    }

    func pixelX(_ fraction: Double) -> Double { fraction * Double(image.width) }
}

@Suite("Text matching")
@MainActor
struct TextMatchingTests {
    @Test func coversEveryLetterExactly() throws {
        let rendered = RenderedText("foo boo on only")
        let marks = rendered.screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, color: "white", match: "o")])
        let expected = rendered.text.indices.filter { rendered.text[$0] == "o" }
        try #require(marks.count == expected.count)
        for (mark, index) in zip(marks, expected) {
            let center = rendered.pixelX(mark.x + (mark.w ?? 0) / 2)
            #expect(rendered.span(of: index..<rendered.text.index(after: index)).contains(center))
            #expect(rendered.pixelX(mark.w ?? 0) < 36, "cover should be letter-sized (40 pt font)")
            #expect(mark.match == nil && mark.kind == .redact && mark.color == "white")
        }
    }

    @Test func wholeWordAndAnyCaseOptions() {
        let screenshot = RenderedText("on only On ON").screenshot
        let plain = screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "on")])
        let word = screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "on", word: true)])
        let anyCase = screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "on", word: true, anyCase: true)])
        #expect(plain.count == 2)  // "on", "only"
        #expect(word.count == 1)  // "on"
        #expect(anyCase.count == 3)  // "on", "On", "ON"
    }

    @Test func worksOnDarkBackgrounds() {
        let rendered = RenderedText("dark mode", background: .black, ink: .white)
        let marks = rendered.screenshot.resolve([Mark(kind: .highlight, x: 0, y: 0, match: "mode")])
        let target = rendered.span(of: rendered.text.range(of: "mode")!)
        #expect(marks.count == 1)
        let start = rendered.pixelX(marks[0].x)
        let end = rendered.pixelX(marks[0].x + (marks[0].w ?? 0))
        #expect(abs(start - target.lowerBound) < 6 && abs(end - target.upperBound) < 6)
    }

    @Test func repeatedMatchesMarkOnce() {
        let match = Mark(kind: .redact, x: 0, y: 0, match: "on")
        #expect(RenderedText("on only").screenshot.resolve([match, match, match]).count == 2)
    }

    @Test func positionedMarksPassThrough() {
        let box = Mark(kind: .box, x: 0.1, y: 0.1, w: 0.2, h: 0.2)
        #expect(RenderedText("x").screenshot.resolve([box]) == [box])
    }

    @Test func missingTextYieldsNoMarks() {
        #expect(RenderedText("hello").screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "zebra")]).isEmpty)
    }

    /// End to end with real Vision text recognition.
    @Test func recognizesTextInAnImageFile() throws {
        let rendered = RenderedText("Vocume reads every word", font: .systemFont(ofSize: 48))
        let screenshot = try rendered.recognized()
        #expect(screenshot.textSummary.contains("Vocume reads every word"))
        let es = rendered.text.filter { $0 == "e" }.count
        #expect(screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, match: "e")]).count == es)
    }

    /// A small label and large text that Vision reads as one line, like a log prefix: each word
    /// must be found in its own font size.
    @Test func mixedFontSizesInOneLine() throws {
        let text = NSMutableAttributedString(
            string: "jev-model-router   ",
            attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.gray])
        text.append(
            NSAttributedString(
                string: "[jev-model-router] main loop → effort low",
                attributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black]))
        let rendered = RenderedText(text)
        let marks = try rendered.recognized().resolve([Mark(kind: .redact, x: 0, y: 0, match: "jev-model-router")])
            .sorted { $0.x < $1.x }
        try #require(marks.count == 2)
        for (mark, target) in zip(marks, rendered.text.ranges(of: "jev-model-router")) {
            let span = rendered.span(of: target)
            #expect(abs(rendered.pixelX(mark.x) - span.lowerBound) < 5)
            #expect(abs(rendered.pixelX(mark.x + (mark.w ?? 0)) - span.upperBound) < 5)
        }
        #expect((marks[0].h ?? 0) < (marks[1].h ?? 0) * 0.8, "the small label gets a small cover")
    }
}
