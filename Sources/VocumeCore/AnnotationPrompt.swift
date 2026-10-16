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
            - a position, one of:
              - "detect": a class of text the app finds itself, every occurrence, more reliably than any list: \
            \(TextKind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: " | ")). \
            ALWAYS use it when the request is about all text of a kind ("redact all numbers", "highlight every \
            email", "box the red text"): one item per kind, never a list of the items. "ids" are UUIDs and long hex \
            strings; "secrets" are API keys, tokens and passwords; "names" are people's names (also list the names \
            you see with "match", as the detector can miss some). Example: {"type":"redact","detect":"numbers"}
              - or "match": exact text to find. The app places one mark on EVERY occurrence, precisely, via OCR. \
            Prefer this whenever the target is visible text, even a single letter. Case-sensitive unless "anyCase": true. \
            Also matches inside longer words ("on" hits "only") unless "word": true (whole words only). \
            OCR may confuse look-alikes (0/O, 1/l/I); matching allows for that, so write the text as you see it.
                - "context" (optional, with "match"): a longer exact text around the one occurrence you mean, \
            when the same text appears several times but needs different marks or labels. Never fall back to \
            x,y for visible text.
              - or "pattern": a regular expression (ICU) for a class of text no "detect" kind covers; the app marks \
            every match in the OCR text.
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

    /// The reply's fields in the order they should be written: enforcement emits properties in
    /// schema order, so `detect`, `match`, `color` and `label` come before coordinates, or models write
    /// coordinates first and never get to them. Each field's JSON schema type and allowed values.
    private static let fields: [(name: String, type: String, values: [String]?)] = [
        ("type", "string", Mark.Kind.allCases.map(\.rawValue)), ("detect", "string", TextKind.allCases.map(\.rawValue)),
        ("match", "string", nil), ("context", "string", nil), ("pattern", "string", nil),
        ("color", "string", Palette.colors.map(\.name)), ("label", "string", nil), ("size", "number", nil),
        ("word", "boolean", nil), ("anyCase", "boolean", nil), ("x", "number", nil), ("y", "number", nil),
        ("w", "number", nil), ("h", "number", nil), ("points", "array", nil),
    ]

    /// The reply's shape as a JSON schema, for providers that enforce one, so they can't return
    /// broken JSON: a list of marks (Ollama's `format`). Written as text to keep the field order.
    public static let replySchema = schema(strict: false)

    /// The list inside an object, as Claude Code's `--json-schema` takes it.
    public static let objectReplySchema =
        #"{"type":"object","properties":{"marks":"# + replySchema
        + #"},"required":["marks"]}"#

    /// OpenAI's strict form, for Codex's `--output-schema`: an object at the top, every field listed
    /// and required (null when unused), no other fields.
    public static let strictReplySchema =
        #"{"type":"object","additionalProperties":false,"properties":{"marks":"# + schema(strict: true)
        + #"},"required":["marks"]}"#

    private static func schema(strict: Bool) -> String {
        func quoted(_ values: [String]) -> String { values.map { "\"\($0)\"" }.joined(separator: ",") }
        let properties = fields.map { field -> String in
            let nullable = strict && field.name != "type"
            let type = nullable ? #"["\#(field.type)","null"]"# : "\"\(field.type)\""
            var schema = #""type":\#(type)"#
            if let values = field.values { schema += #","enum":[\#(quoted(values))\#(nullable ? ",null" : "")]"# }
            if field.type == "array" { schema += #","items":{"type":"array","items":{"type":"number"}}"# }
            return #""\#(field.name)":{\#(schema)}"#
        }.joined(separator: ",")
        let required = strict ? quoted(fields.map(\.name)) : #""type""#
        let closed = strict ? #","additionalProperties":false"# : ""
        return
            #"{"type":"array","items":{"type":"object","properties":{\#(properties)},"required":[\#(required)]\#(closed)}}"#
    }

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
