import AppKit
import Testing

@testable import VocumeCore

/// Renders text at a known position, so the true pixel span of every letter is known exactly.
@MainActor
private struct RenderedText {
    let text: String
    let font: NSFont
    let origin = CGPoint(x: 40, y: 30)
    let image: CGImage
    let line: RecognizedScreenshot.Line

    init(_ text: String, font: NSFont = .systemFont(ofSize: 40), background: NSColor = .white, ink: NSColor = .black) {
        self.text = text
        self.font = font
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let textSize = NSAttributedString(string: text, attributes: attributes).size()
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
        NSAttributedString(string: text, attributes: attributes).draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
        image = context.makeImage()!
        line = .init(
            text: text,
            box: CGRect(
                x: origin.x / Double(width), y: origin.y / Double(height),
                width: textSize.width / Double(width), height: textSize.height / Double(height)))
    }

    var screenshot: RecognizedScreenshot { RecognizedScreenshot(lines: [line], pixels: Pixels(image)!) }

    /// Horizontal pixel range of `text[range]`, measured with the same font.
    func span(of range: Range<String.Index>) -> ClosedRange<Double> {
        func width(_ s: Substring) -> Double {
            NSAttributedString(string: String(s), attributes: [.font: font]).size().width
        }
        let start = origin.x + width(text[..<range.lowerBound])
        return start...(start + width(text[range]))
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
            #expect(rendered.pixelX(mark.w ?? 0) < rendered.font.pointSize * 0.9, "cover should be letter-sized")
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocume-test-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try #require(NSBitmapImageRep(cgImage: rendered.image).representation(using: .png, properties: [:]))
            .write(to: url)
        let screenshot = try #require(RecognizedScreenshot(contentsOf: url))
        #expect(screenshot.textSummary.contains("Vocume reads every word"))
        let es = rendered.text.filter { $0 == "e" }.count
        #expect(screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, match: "e")]).count == es)
    }
}
