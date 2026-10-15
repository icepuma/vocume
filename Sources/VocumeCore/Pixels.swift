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
        let x0 = max(Int(rect.minX * Double(width)), 0)
        let x1 = min(Int(rect.maxX * Double(width)), width)
        let y0 = max(Int(rect.minY * Double(height)), 0)
        let y1 = min(Int(rect.maxY * Double(height)), height)
        guard x1 > x0, y1 > y0 else { return (x0, []) }

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
        }
        // Background: the most common colour, sampled every other pixel and quantized to 4 bits.
        var counts: [Int: Int] = [:]
        for y in stride(from: y0, to: y1, by: 2) {
            for x in stride(from: x0, to: x1, by: 2) {
                let (r, g, b) = rgb(x, y)
                counts[(r >> 4) << 8 | (g >> 4) << 4 | b >> 4, default: 0] += 1
            }
        }
        let key = counts.max { $0.value < $1.value }?.key ?? 0
        let background = ((key >> 8) * 16 + 8, (key >> 4 & 15) * 16 + 8, (key & 15) * 16 + 8)
        let ink = (x0..<x1).map { x in
            (y0..<y1).contains { y in
                let (r, g, b) = rgb(x, y)
                return max(abs(r - background.0), abs(g - background.1), abs(b - background.2)) > 72
            }
        }
        return (x0, ink)
    }
}
