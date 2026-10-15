import Foundation

/// What Vocume asks the AI, and how it reads the answer.
public enum AnnotationPrompt {
    public static let systemPrompt = "You annotate screenshots. Output only the JSON array requested."
    public static let defaultRequest = "Point out anything that looks wrong or noteworthy."

    /// The full instructions for one request. The screenshot itself is attached separately.
    public static func make(request: String, textSummary: String) -> String {
        let request = request.isEmpty ? defaultRequest : request
        return """
            You annotate a screenshot using an annotation app's tools. The user's request: \(request)

            The screenshot is attached. Respond with ONLY a JSON array, no prose. Each item has:
            - "type": "arrow" | "line" (plain line; with "match" it underlines the text) | "box" \
            | "ellipse" (circles something) | "highlight" (translucent marker) \
            | "redact" (solid filled block that hides content) | "pen" (freehand line) | "text" (a note) \
            | "step" (auto-numbered circle 1, 2, 3…) \
            | "crop" (crops the image to this area: with "match" it keeps a margin around the text; several crop \
            items crop to the area that contains them all, e.g. a panel's title and its last button)
            - a position, either:
              - "match": exact text to find. The app places one mark on EVERY occurrence, precisely, via OCR. \
            Prefer this whenever the target is visible text, even a single letter. Case-sensitive unless "anyCase": true. \
            Also matches inside longer words ("on" hits "only") unless "word": true (whole words only). \
            OCR may confuse look-alikes (0/O, 1/l/I); matching allows for that, so write the text as you see it.
                - "context" (optional, with "match"): a longer exact text around the one occurrence you mean, \
            when the same text appears several times but needs different marks or labels. Never fall back to \
            x,y for visible text.
              - or "x","y","w","h" (only for things that are not text): fractions 0-1 of image width/height, origin top-left. \
            box/ellipse/highlight/redact/crop: the rectangle. arrow/line: from (x,y) to (x+w,y+h), an arrow's tip at the end. text/step: x,y is the spot. pen: "points": [[x,y], …] instead.
            - "color": \(Palette.colors.map(\.name).joined(separator: " | ")) (default \(Palette.defaultName))
            - "size": 0.6 small, 1 medium, 1.6 large (default 1)
            - "label": short note shown in a coloured pill. Only include it when a note helps; never for plain \
            redactions or highlights. Required for "text" (it is the text).
            Example: [{"type":"redact","match":"o","color":"white"},{"type":"arrow","x":0.2,"y":0.3,"w":0.1,"h":0.05,"label":"bug here"}]

            Text found by OCR (x,y,w,h then the text). Use it to place marks accurately:
            \(textSummary.isEmpty ? "(none)" : textSummary)
            """
    }

    /// The reply's shape as a JSON schema, for providers that enforce one (Ollama's `format`), so
    /// small local models can't return broken JSON. Written as text because enforcement emits
    /// properties in schema order (a dictionary's order changes every launch): `color` and `label`
    /// come right after `match`, or models write coordinates first and never get to them.
    public static let replySchema: String = {
        func list(_ values: [String]) -> String { "[" + values.map { "\"\($0)\"" }.joined(separator: ",") + "]" }
        let number = #"{"type":"number"}"#
        return """
            {"type":"array","items":{"type":"object","properties":{\
            "type":{"type":"string","enum":\(list(Mark.Kind.allCases.map(\.rawValue)))},\
            "match":{"type":"string"},"context":{"type":"string"},\
            "color":{"type":"string","enum":\(list(Palette.colors.map(\.name)))},\
            "label":{"type":"string"},"size":\(number),"word":{"type":"boolean"},"anyCase":{"type":"boolean"},\
            "x":\(number),"y":\(number),"w":\(number),"h":\(number),\
            "points":{"type":"array","items":{"type":"array","items":\(number)}}},\
            "required":["type"]}}
            """
    }()

    /// The marks in an AI reply: the outermost JSON array, ignoring any prose or code fences around it.
    public static func parseMarks(from reply: String) throws -> [Mark] {
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end else {
            throw AnnotationError(description: reply.isEmpty ? "The AI returned nothing." : reply)
        }
        return try JSONDecoder().decode([Mark].self, from: Data(reply[start...end].utf8))
    }
}

public struct AnnotationError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(description: String) { self.description = description }
}
