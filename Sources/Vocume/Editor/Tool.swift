import VocumeCore

/// The editor's tools: selection plus one tool per mark kind.
enum Tool: String, CaseIterable {
    case select, arrow, line, box, ellipse, highlight, redact, pen, text, step, crop

    /// The kind of mark this tool draws (`nil` for selection and cropping).
    var markKind: Mark.Kind? { self == .crop ? nil : Mark.Kind(rawValue: rawValue) }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .line: "Line"
        case .box: "Box"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        case .redact: "Redact"
        case .pen: "Pen"
        case .text: "Text"
        case .step: "Numbered Step"
        case .crop: "Crop"
        }
    }

    var icon: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .box: "rectangle"
        case .ellipse: "circle"
        case .highlight: "highlighter"
        case .redact: "rectangle.inset.filled"
        case .pen: "scribble.variable"
        case .text: "textformat"
        case .step: "1.circle"
        case .crop: "crop"
        }
    }

    /// Single-key shortcut.
    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .box: "r"
        case .ellipse: "o"
        case .highlight: "h"
        case .redact: "x"
        case .pen: "p"
        case .text: "t"
        case .step: "n"
        case .crop: "c"
        }
    }
}
