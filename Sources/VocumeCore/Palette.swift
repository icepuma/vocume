import AppKit
import SwiftUI

/// The colours a mark can have: the eight named inks (also what the AI may use), or any custom
/// colour as `#RRGGBB`.
public enum Palette {
    public static let colors: [(name: String, color: Color)] = [
        ("red", Color(red: 1, green: 0.23, blue: 0.19)),
        ("orange", Color(red: 1, green: 0.58, blue: 0)),
        ("yellow", Color(red: 1, green: 0.8, blue: 0)),
        ("green", Color(red: 0.2, green: 0.78, blue: 0.35)),
        ("blue", Color(red: 0, green: 0.48, blue: 1)),
        ("purple", Color(red: 0.69, green: 0.32, blue: 0.87)),
        ("black", Color(white: 0.12)),
        ("white", .white),
    ]

    public static let defaultName = "red"

    /// The colour for a name or `#RRGGBB`; unknown or missing names fall back to red.
    public static func color(named name: String?) -> Color {
        if let (red, green, blue) = rgb(name) { return Color(.sRGB, red: red, green: green, blue: blue) }
        return colors.first { $0.name == name }?.color ?? colors[0].color
    }

    /// A text colour that stays readable on top of the named colour: for custom colours whichever
    /// of black and white contrasts more (WCAG relative luminance).
    public static func ink(on name: String?) -> Color {
        guard let (red, green, blue) = rgb(name) else { return name == "yellow" || name == "white" ? .black : .white }
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return luminance > 0.179 ? .black : .white
    }

    /// A custom colour's name: `#RRGGBB` in sRGB.
    public static func name(for color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let byte = { (c: CGFloat) in Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X", byte(srgb.redComponent), byte(srgb.greenComponent), byte(srgb.blueComponent))
    }

    private static func rgb(_ name: String?) -> (Double, Double, Double)? {
        guard let name, name.count == 7, name.first == "#", let value = Int(name.dropFirst(), radix: 16) else {
            return nil
        }
        return (Double(value >> 16 & 255) / 255, Double(value >> 8 & 255) / 255, Double(value & 255) / 255)
    }
}
