import VocumeCore

/// The editor's tools: selection plus one tool per mark kind.
enum Tool: String, CaseIterable {
    case select, arrow, box, highlight, redact, pen, text, step

    /// The kind of mark this tool draws (`nil` for selection).
    var markKind: Mark.Kind? { Mark.Kind(rawValue: rawValue) }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .box: "Box"
        case .highlight: "Highlight"
        case .redact: "Redact"
        case .pen: "Pen"
        case .text: "Text"
        case .step: "Numbered Step"
        }
    }

    var icon: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .box: "rectangle"
        case .highlight: "highlighter"
        case .redact: "rectangle.inset.filled"
        case .pen: "scribble.variable"
        case .text: "textformat"
        case .step: "1.circle"
        }
    }

    /// Single-key shortcut.
    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .box: "r"
        case .highlight: "h"
        case .redact: "x"
        case .pen: "p"
        case .text: "t"
        case .step: "n"
        }
    }
}
