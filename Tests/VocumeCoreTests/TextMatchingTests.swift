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

/// Whether Vision reads text on this machine. GitHub's macOS 27 runner returns nothing (its virtual
/// machine can't run the recognizer), so the end-to-end OCR tests skip there; they run on real Macs.
@MainActor private func visionReadsText() -> Bool {
    (try? RenderedText("Vision check", font: .systemFont(ofSize: 48)).recognized())?.lines.isEmpty == false
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

    @Test func linesUnderlineAndEllipsesEncloseText() throws {
        let rendered = RenderedText("underline me")
        let box = try #require(rendered.screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "me")]).first)
        let line = try #require(rendered.screenshot.resolve([Mark(kind: .line, x: 0, y: 0, match: "me")]).first)
        let ellipse = try #require(rendered.screenshot.resolve([Mark(kind: .ellipse, x: 0, y: 0, match: "me")]).first)
        #expect(line.h == 0 && line.y > box.y, "a flat line under the text")
        #expect(ellipse.x < box.x && (ellipse.w ?? 0) > (box.w ?? 0), "wider than the box, so it clears the corners")
    }

    /// Vision reads the digit in "v0.4.0" as a letter O; the match still lands on it.
    @Test func toleratesOCRLookalikes() throws {
        let rendered = RenderedText("release v0.4.0 now")
        let misread = RecognizedScreenshot(
            lines: [.init(text: "release vO.4.0 now", box: rendered.line.box)], pixels: Pixels(rendered.image)!)
        let mark = try #require(misread.resolve([Mark(kind: .box, x: 0, y: 0, match: "v0.4.0")]).first)
        let target = rendered.span(of: rendered.text.range(of: "v0.4.0")!)
        let center = rendered.pixelX(mark.x + (mark.w ?? 0) / 2)
        #expect(target.contains(center))
    }

    /// OCR read one copy right and one wrong; either spelling finds both.
    @Test func lookalikesMatchEveryCopy() {
        let rendered = RenderedText("v0.4.0 and v0.4.0")
        let mixed = RecognizedScreenshot(
            lines: [.init(text: "vO.4.0 and v0.4.0", box: rendered.line.box)], pixels: Pixels(rendered.image)!)
        #expect(mixed.resolve([Mark(kind: .box, x: 0, y: 0, match: "vO.4.0")]).count == 2)
        #expect(mixed.resolve([Mark(kind: .box, x: 0, y: 0, match: "v0.4.0")]).count == 2)
    }

    /// Inline code reads with a stray space ("install. sh") or loses its spaces; it is still found.
    @Test func toleratesOCRSpacing() throws {
        let rendered = RenderedText("run install.sh now")
        let spaced = RecognizedScreenshot(
            lines: [.init(text: "run install. sh now", box: rendered.line.box)], pixels: Pixels(rendered.image)!)
        let mark = try #require(spaced.resolve([Mark(kind: .redact, x: 0, y: 0, match: "install.sh")]).first)
        let target = rendered.span(of: rendered.text.range(of: "install.sh")!)
        #expect(target.contains(rendered.pixelX(mark.x + (mark.w ?? 0) / 2)))

        let squeezed = RecognizedScreenshot(
            lines: [.init(text: "archive:false here", box: RenderedText("archive: false here").line.box)],
            pixels: Pixels(RenderedText("archive: false here").image)!)
        #expect(squeezed.resolve([Mark(kind: .redact, x: 0, y: 0, match: "archive: false")]).count == 1)
    }

    /// OCR reads inline code as "(install. sh)": brackets made from the chip's edges, with no ink.
    /// A redaction must still cover every letter.
    @Test func inventedBracketsDontShiftTheMark() throws {
        let rendered = RenderedText("use install.sh now")
        let width = Double(rendered.image.width)
        func box(_ text: String) -> CGRect {
            let span = rendered.span(of: rendered.text.range(of: text)!)
            return CGRect(
                x: span.lowerBound / width, y: rendered.line.box.minY,
                width: (span.upperBound - span.lowerBound) / width,
                height: rendered.line.box.height)
        }
        let line = RecognizedScreenshot.Line(
            text: "use (install. sh) now", box: rendered.line.box,
            wordBoxes: [box("use"), box("install."), box("sh"), box("now")])
        let screenshot = RecognizedScreenshot(lines: [line], pixels: Pixels(rendered.image)!)
        let mark = try #require(screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, match: "install.sh")]).first)
        let target = rendered.span(of: rendered.text.range(of: "install.sh")!)
        #expect(rendered.pixelX(mark.x) <= target.lowerBound + 1, "covers the first letter")
        #expect(rendered.pixelX(mark.x + (mark.w ?? 0)) >= target.upperBound - 1, "covers the last letter")
    }

    /// "Redact all numbers": the AI sends one pattern and the app finds every number itself.
    @Test func patternMarksEveryMatch() throws {
        let rendered = RenderedText("Xcode 27.0 ships Swift 6.4 in 2026")
        let reply = try AnnotationPrompt.parseMarks(from: #"[{"type":"redact","pattern":"\\d+(?:[.,]\\d+)*"}]"#)
        let marks = rendered.screenshot.resolve(reply)
        try #require(marks.count == 3)
        for (mark, number) in zip(marks.sorted { $0.x < $1.x }, ["27.0", "6.4", "2026"]) {
            let span = rendered.span(of: rendered.text.range(of: number)!)
            #expect(span.contains(rendered.pixelX(mark.x + (mark.w ?? 0) / 2)), "covers \(number)")
            #expect(mark.pattern == nil && mark.kind == .redact)
        }
        #expect(rendered.screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, pattern: "(")]).isEmpty, "invalid")
    }

    /// "Redact all numbers" through a detector: each token is covered whole, so "v0.5.3" can't leave
    /// "v0." showing.
    @Test func detectorRedactsWholeTokens() throws {
        let rendered = RenderedText("release v0.5.3 and 27.0 today")
        let marks = rendered.screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, detect: "numbers")])
            .sorted { $0.x < $1.x }
        try #require(marks.count == 2)
        let version = rendered.span(of: rendered.text.range(of: "v0.5.3")!)
        #expect(rendered.pixelX(marks[0].x) <= version.lowerBound + 1, "covers the v")
        #expect(rendered.pixelX(marks[0].x + (marks[0].w ?? 0)) >= version.upperBound - 1)
        #expect(marks.allSatisfy { $0.detect == nil })
    }

    /// "Redact all red text": the ink colour of each word decides, not the AI.
    @Test func colorDetectorFindsRedWords() throws {
        let text = NSMutableAttributedString(
            string: "keep this ", attributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        text.append(
            NSAttributedString(
                string: "secret",
                attributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.systemRed]))
        text.append(
            NSAttributedString(
                string: " visible", attributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        )
        let rendered = RenderedText(text)
        let marks = rendered.screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, detect: "red text")])
        try #require(marks.count == 1)
        let red = rendered.span(of: rendered.text.range(of: "secret")!)
        #expect(red.contains(rendered.pixelX(marks[0].x + (marks[0].w ?? 0) / 2)))
    }

    /// Vision reads a small "−6" as "-б" and curly quotes vary; a match still finds them.
    @Test func toleratesCyrillicAndDashLookalikes() {
        let rendered = RenderedText("diff +45 −6 lines, don’t")
        let misread = RecognizedScreenshot(
            lines: [.init(text: "diff +45 -б lines, don't", box: rendered.line.box)], pixels: Pixels(rendered.image)!)
        #expect(misread.resolve([Mark(kind: .redact, x: 0, y: 0, match: "−6 lines")]).count == 1)
        #expect(misread.resolve([Mark(kind: .redact, x: 0, y: 0, match: "don’t")]).count == 1)
    }

    /// A cover that missed part of a number: the re-check reads the redacted image, finds the
    /// visible rest ("v0.") and covers it too.
    @Test(.enabled("needs on-device text recognition") { await visionReadsText() })
    func checkCoversWhatAFirstPassMissed() throws {
        let rendered = RenderedText("release v0.5.3 now", font: .systemFont(ofSize: 48))
        let screenshot = try rendered.recognized()
        let width = Double(rendered.image.width)
        let partial = rendered.span(of: rendered.text.range(of: "5.3")!)
        let missed = Mark(
            kind: .redact, x: partial.lowerBound / width, y: rendered.line.box.minY,
            w: (partial.upperBound - partial.lowerBound) / width, h: rendered.line.box.height)
        let checked = screenshot.checkingRedactions(
            [missed], requested: [Mark(kind: .redact, x: 0, y: 0, detect: "numbers")])
        #expect(checked.repaired >= 1)
        let version = rendered.span(of: rendered.text.range(of: "v0.5.3")!)
        let left = checked.marks.map { rendered.pixelX($0.x) }.min() ?? .infinity
        #expect(left <= version.lowerBound + 2, "the v is covered now")
    }

    /// Two OCR readings of one line place a step a few pixels apart: it is still one step.
    @Test func stepsFromTwoReadingsAreOne() {
        let step = Mark(kind: .step, x: 0.3, y: 0.40, label: "1")
        var nearby = step
        (nearby.x, nearby.y) = (0.302, 0.403)
        #expect(nearby.isDuplicate(of: step))
        (nearby.x, nearby.y) = (0.3, 0.43)  // the next line down
        #expect(!nearby.isDuplicate(of: step))
    }

    /// A narrowed request isn't re-run: its context is covered by then, and without it every phone
    /// number on screen would be covered.
    @Test func checkKeepsNarrowedRequestsNarrow() throws {
        let screenshot = RenderedText("a 0123 b").screenshot
        let request = Mark(kind: .redact, x: 0, y: 0, context: "a 0123", detect: "numbers")
        let checked = screenshot.checkingRedactions([], requested: [request])
        #expect(checked.marks.isEmpty && checked.repaired == 0)
    }

    /// "11" isn't "ll": a look-alike match must keep one of the text's own characters.
    @Test func digitsDontMatchLookalikeWords() {
        let screenshot = RenderedText("it is still here").screenshot
        #expect(screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, match: "11")]).isEmpty)
    }

    /// Dark mode's diff counts, cut from a real capture: green "+6" and red "−6" on tinted chips,
    /// placed in a full-size Retina screen. Vision shrinks each image it reads, so the whole screen
    /// and 2048 px tiles lose this text; the 2× pass over smaller tiles reads it.
    @Test(.enabled("needs on-device text recognition") { await visionReadsText() })
    func readsSmallColouredChipsInAFullScreen() throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/diff-chips", withExtension: "png"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let chips = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try #require(
            CGContext(
                data: nil, width: 3600, height: 2338, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0x18 / 255, green: 0x18 / 255, blue: 0x18 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3600, height: 2338))
        context.draw(chips, in: CGRect(x: 1840, y: 1643, width: chips.width, height: chips.height))
        let image = try #require(context.makeImage())
        let screenshot = try #require(RecognizedScreenshot(image: image))
        let covers = screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, detect: "numbers")]).map {
            $0.frame(in: CGSize(width: 3600, height: 2338))
        }
        for (count, center) in [("+6", CGPoint(x: 2052, y: 672)), ("−6", CGPoint(x: 2096, y: 672))] {
            #expect(covers.contains { $0.contains(center) }, "\(count) is covered")
        }
    }

    /// A listed match, once covered, isn't searched for again: "11" would find the "ll" in "still".
    @Test(.enabled("needs on-device text recognition") { await visionReadsText() })
    func checkLeavesLookalikeWordsAlone() throws {
        let rendered = RenderedText("open ask11 and still wait", font: .systemFont(ofSize: 48))
        let screenshot = try rendered.recognized()
        let request = Mark(kind: .redact, x: 0, y: 0, match: "11", context: "ask11")
        let checked = screenshot.checkingRedactions(screenshot.resolve([request]), requested: [request])
        let still = rendered.span(of: rendered.text.range(of: "still")!)
        #expect(checked.marks.allSatisfy { rendered.pixelX($0.x) < still.lowerBound })
    }

    /// An email address wrapped onto the next line: covered on both lines; an arrow points once.
    @Test func matchesAcrossALineBreak() {
        let rendered = RenderedText("contact jane.doe@exam\nple.com today")
        let box = rendered.line.box
        let half = box.height / 2
        let screenshot = RecognizedScreenshot(
            lines: [
                .init(
                    text: "contact jane.doe@exam", box: CGRect(x: box.minX, y: box.minY, width: box.width, height: half)
                ),
                .init(
                    text: "ple.com today",
                    box: CGRect(x: box.minX, y: box.minY + half, width: box.width * 0.6, height: half)),
            ], pixels: Pixels(rendered.image)!)
        let covers = screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, match: "jane.doe@example.com")])
        #expect(covers.count == 2)
        #expect(Set(covers.map { $0.y < box.minY + half / 2 }).count == 2, "one cover per line")
        #expect(screenshot.resolve([Mark(kind: .arrow, x: 0, y: 0, match: "jane.doe@example.com")]).count == 1)
    }

    @Test func exactMatchesBeatLookalikes() {
        #expect(RenderedText("O and 0").screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "0")]).count == 1)
    }

    @Test func contextPicksOneOccurrence() throws {
        let rendered = RenderedText("v1 here and v1 there")
        let marks = rendered.screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "v1", context: "v1 there")])
        try #require(marks.count == 1)
        let second = rendered.text.range(of: "v1", options: .backwards)!
        #expect(rendered.span(of: second).contains(rendered.pixelX(marks[0].x + (marks[0].w ?? 0) / 2)))
    }

    @Test func cropByTextKeepsAMargin() throws {
        let rendered = RenderedText("crop to me please")
        let box = try #require(rendered.screenshot.resolve([Mark(kind: .box, x: 0, y: 0, match: "me")]).first)
        let crop = try #require(rendered.screenshot.resolve([Mark(kind: .crop, x: 0, y: 0, match: "me")]).first)
        #expect(crop.kind == .crop && crop.x < box.x && (crop.h ?? 0) > (box.h ?? 0))
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
    @Test(.enabled("needs on-device text recognition") { await visionReadsText() })
    func recognizesTextInAnImageFile() throws {
        let rendered = RenderedText("Vocume reads every word", font: .systemFont(ofSize: 48))
        let screenshot = try rendered.recognized()
        #expect(screenshot.textSummary.contains("Vocume reads every word"))
        let es = rendered.text.filter { $0 == "e" }.count
        #expect(screenshot.resolve([Mark(kind: .redact, x: 0, y: 0, match: "e")]).count == es)
    }

    /// A small label and large text that Vision reads as one line, like a log prefix: each word
    /// must be found in its own font size.
    @Test(.enabled("needs on-device text recognition") { await visionReadsText() })
    func mixedFontSizesInOneLine() throws {
        let text = NSMutableAttributedString(
            string: "jev-model-router   ",
            attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.gray])
        text.append(
            NSAttributedString(
                string: "[jev-model-router] main loop → effort low",
                attributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black]))
        let rendered = RenderedText(text)
        let marks = try rendered.recognized().resolve([Mark(kind: .highlight, x: 0, y: 0, match: "jev-model-router")])
            .sorted { $0.x < $1.x }
        try #require(marks.count == 2)
        for (mark, target) in zip(marks, rendered.text.ranges(of: "jev-model-router")) {
            let span = rendered.span(of: target)
            #expect(abs(rendered.pixelX(mark.x) - span.lowerBound) < 5)
            #expect(abs(rendered.pixelX(mark.x + (mark.w ?? 0)) - span.upperBound) < 5)
        }
        #expect((marks[0].h ?? 0) < (marks[1].h ?? 0) * 0.8, "the small label gets a small mark")
    }
}
