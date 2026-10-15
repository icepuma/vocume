import SwiftUI

/// The colours a mark can have, by name (the names are also what the AI may use).
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

    /// The colour for a name; unknown or missing names fall back to red.
    public static func color(named name: String?) -> Color {
        colors.first { $0.name == name }?.color ?? colors[0].color
    }

    /// A text colour that stays readable on top of the named colour.
    public static func ink(on name: String?) -> Color {
        name == "yellow" || name == "white" ? .black : .white
    }
}
