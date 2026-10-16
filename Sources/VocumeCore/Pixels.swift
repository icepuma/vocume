import CoreGraphics
import Foundation
import ImageIO

/// An RGBA copy of the screenshot, so OCR estimates can snap to the real letter pixels.
struct Pixels: Sendable {
    let width: Int
    let height: Int
    private let rgba: [UInt8]

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.init(image)
    }

    init?(_ image: CGImage) {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        (width, height, rgba) = (image.width, image.height, buffer)
    }

    /// For each pixel column of `rect` (normalized, top-left origin): does it hold ink, i.e. a colour
    /// clearly unlike the background (the most common colour in `rect`)? Works for dark-on-light and
    /// light-on-dark text alike.
    func inkColumns(in rect: CGRect) -> (firstColumn: Int, ink: [Bool]) {
        guard let (xs, ys, isInk) = inkTest(in: rect) else { return (max(Int(rect.minX * Double(width)), 0), []) }
        return (xs.lowerBound, xs.map { x in ys.contains { isInk(x, $0) } })
    }

    /// Like ``inkColumns(in:)``, per pixel row.
    func inkRows(in rect: CGRect) -> (firstRow: Int, ink: [Bool]) {
        guard let (xs, ys, isInk) = inkTest(in: rect) else { return (max(Int(rect.minY * Double(height)), 0), []) }
        return (ys.lowerBound, ys.map { y in xs.contains { isInk($0, y) } })
    }

    /// The colour of the ink in `rect`: the average of its most distinct half of ink pixels, which
    /// skips the anti-aliased edges that blend into the background. `nil` without ink.
    func inkColor(in rect: CGRect) -> InkColor? {
        guard let (xs, ys, isInk) = inkTest(in: rect) else { return nil }
        var ink: [(r: Int, g: Int, b: Int, strength: Int)] = []
        let background = backgroundColor(xs, ys)
        for y in ys {
            for x in xs where isInk(x, y) {
                let i = (y * width + x) * 4
                let (r, g, b) = (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
                ink.append((r, g, b, max(abs(r - background.0), abs(g - background.1), abs(b - background.2))))
            }
        }
        guard !ink.isEmpty else { return nil }
        let strongest = ink.sorted { $0.strength > $1.strength }.prefix(max(1, ink.count / 2))
        let n = Double(strongest.count)
        let (r, g, b) = (
            Double(strongest.map(\.r).reduce(0, +)) / n / 255, Double(strongest.map(\.g).reduce(0, +)) / n / 255,
            Double(strongest.map(\.b).reduce(0, +)) / n / 255
        )
        let (high, low) = (max(r, g, b), min(r, g, b))
        let chroma = high - low
        var hue = 0.0
        if chroma > 0 {
            hue =
                high == r
                ? 60 * ((g - b) / chroma).truncatingRemainder(dividingBy: 6)
                : high == g ? 60 * ((b - r) / chroma + 2) : 60 * ((r - g) / chroma + 4)
        }
        return InkColor(hue: hue < 0 ? hue + 360 : hue, saturation: high == 0 ? 0 : chroma / high, brightness: high)
    }

    private func inkTest(in rect: CGRect) -> (Range<Int>, Range<Int>, (Int, Int) -> Bool)? {
        let x0 = max(Int(rect.minX * Double(width)), 0)
        let x1 = min(Int(rect.maxX * Double(width)), width)
        let y0 = max(Int(rect.minY * Double(height)), 0)
        let y1 = min(Int(rect.maxY * Double(height)), height)
        guard x1 > x0, y1 > y0 else { return nil }
        let background = backgroundColor(x0..<x1, y0..<y1)
        return (
            x0..<x1, y0..<y1,
            { x, y in
                let (r, g, b) = rgb(x, y)
                return max(abs(r - background.0), abs(g - background.1), abs(b - background.2)) > 72
            }
        )
    }

    private func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
    }

    /// The image with `rects` (normalized, top-left origin) painted solid black: redactions applied,
    /// for reading the result again.
    func image(covering rects: [CGRect]) -> CGImage? {
        var copy = rgba
        for rect in rects {
            let x0 = max(Int((rect.minX * Double(width)).rounded(.down)), 0)
            let x1 = min(Int((rect.maxX * Double(width)).rounded(.up)), width)
            let y0 = max(Int((rect.minY * Double(height)).rounded(.down)), 0)
            let y1 = min(Int((rect.maxY * Double(height)).rounded(.up)), height)
            guard x1 > x0, y1 > y0 else { continue }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = (y * width + x) * 4
                    (copy[i], copy[i + 1], copy[i + 2], copy[i + 3]) = (0, 0, 0, 255)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(copy) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The most common colour along the image's outer edge: the margin OCR passes are padded with.
    var borderColor: (red: Int, green: Int, blue: Int) {
        var counts: [Int: Int] = [:]
        let edge =
            (0..<width).flatMap { [($0, 0), ($0, height - 1)] } + (0..<height).flatMap { [(0, $0), (width - 1, $0)] }
        for (x, y) in edge {
            let (r, g, b) = rgb(x, y)
            counts[(r >> 4) << 8 | (g >> 4) << 4 | b >> 4, default: 0] += 1
        }
        let key = counts.max { $0.value < $1.value }?.key ?? 0
        return ((key >> 8) * 16 + 8, (key >> 4 & 15) * 16 + 8, (key & 15) * 16 + 8)
    }

    /// Whether an area (in pixels) has a dark background: light text, as in dark mode.
    func isDark(_ area: CGRect) -> Bool {
        let (r, g, b) = backgroundColor(
            max(Int(area.minX), 0)..<min(Int(area.maxX), width), max(Int(area.minY), 0)..<min(Int(area.maxY), height))
        return 299 * r + 587 * g + 114 * b < 128_000
    }

    /// The most common colour in the area, sampled every other pixel and quantized to 4 bits.
    private func backgroundColor(_ xs: Range<Int>, _ ys: Range<Int>) -> (Int, Int, Int) {
        var counts: [Int: Int] = [:]
        for y in stride(from: ys.lowerBound, to: ys.upperBound, by: 2) {
            for x in stride(from: xs.lowerBound, to: xs.upperBound, by: 2) {
                let (r, g, b) = rgb(x, y)
                counts[(r >> 4) << 8 | (g >> 4) << 4 | b >> 4, default: 0] += 1
            }
        }
        let key = counts.max { $0.value < $1.value }?.key ?? 0
        return ((key >> 8) * 16 + 8, (key >> 4 & 15) * 16 + 8, (key & 15) * 16 + 8)
    }
}
