import AppKit

/// The Vocume mark (capture corners + V-arrow) as a monochrome template image for the menu bar.
/// Drawn from the same path data as `assets/vocume.svg`, without its background tile.
enum LogoGlyph {
    /// Paths from `assets/vocume.svg` (viewBox 0 0 256 256): three capture corners and the V-arrow.
    private static let paths = [
        "M91 53H74C62.402 53 53 62.402 53 74V91H65V74C65 69.029 69.029 65 74 65H91Z",
        "M191 165V182C191 186.971 186.971 191 182 191H165V203H182C193.598 203 203 193.598 203 182V165Z",
        "M91 191H74C69.029 191 65 186.971 65 182V165H53V182C53 193.598 62.402 203 74 203H91Z",
        "M76 98H100L128 156L157 95L141 88L190 64L196 118L179 108L142 184H114Z",
    ]
    /// The artwork's bounds inside the viewBox, padded slightly.
    private static let artwork = NSRect(x: 48, y: 48, width: 160, height: 160)

    static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let scale = rect.width / artwork.width
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.translateX(by: -artwork.minX, yBy: -artwork.minY)
            NSColor.black.setFill()
            for data in paths { transform.transform(path(data)).fill() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Vocume"
        return image
    }

    /// A minimal SVG path reader for the absolute commands the logo uses (M, L, H, V, C, Z).
    private static func path(_ data: String) -> NSBezierPath {
        let path = NSBezierPath()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var point = NSPoint.zero

        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                point = NSPoint(x: numbers[0], y: numbers[1])
                path.move(to: point)
            case "L" where numbers.count >= 2:
                for i in stride(from: 0, to: numbers.count - 1, by: 2) {
                    point = NSPoint(x: numbers[i], y: numbers[i + 1])
                    path.line(to: point)
                }
            case "H":
                for x in numbers {
                    point.x = x
                    path.line(to: point)
                }
            case "V":
                for y in numbers {
                    point.y = y
                    path.line(to: point)
                }
            case "C" where numbers.count >= 6:
                for i in stride(from: 0, to: numbers.count - 5, by: 6) {
                    point = NSPoint(x: numbers[i + 4], y: numbers[i + 5])
                    path.curve(
                        to: point,
                        controlPoint1: NSPoint(x: numbers[i], y: numbers[i + 1]),
                        controlPoint2: NSPoint(x: numbers[i + 2], y: numbers[i + 3]))
                }
            case "Z":
                path.close()
            default:
                break
            }
            numbers.removeAll()
        }

        var token = ""
        for char in data + " " {
            if char.isLetter {
                if !token.isEmpty { numbers.append(CGFloat(Double(token) ?? 0)) }
                token = ""
                flush()
                command = char
            } else if char == " " || char == "," {
                if !token.isEmpty { numbers.append(CGFloat(Double(token) ?? 0)) }
                token = ""
            } else {
                token.append(char)
            }
        }
        flush()
        return path
    }
}
