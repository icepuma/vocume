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
            - "type": "arrow" | "box" | "highlight" (translucent marker) | "redact" (solid filled block that hides content) \
            | "pen" (freehand line) | "text" (a note) | "step" (auto-numbered circle 1, 2, 3…)
            - a position, either:
              - "match": exact text to find. The app places one mark on EVERY occurrence, precisely, via OCR. \
            Prefer this whenever the target is visible text, even a single letter. Case-sensitive unless "anyCase": true. \
            Also matches inside longer words ("on" hits "only") unless "word": true (whole words only).
              - or "x","y","w","h": fractions 0-1 of image width/height, origin top-left. box/highlight/redact: the rectangle. \
            arrow: from (x,y) to (x+w,y+h), tip at the end. text/step: x,y is the spot. pen: "points": [[x,y], …] instead.
            - "color": \(Palette.colors.map(\.name).joined(separator: " | ")) (default \(Palette.defaultName))
            - "size": 0.6 small, 1 medium, 1.6 large (default 1)
            - "label": short note shown in a coloured pill. Only include it when a note helps; never for plain \
            redactions or highlights. Required for "text" (it is the text).
            Example: [{"type":"redact","match":"o","color":"white"},{"type":"arrow","x":0.2,"y":0.3,"w":0.1,"h":0.05,"label":"bug here"}]

            Text found by OCR (x,y,w,h then the text). Use it to place marks accurately:
            \(textSummary.isEmpty ? "(none)" : textSummary)
            """
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
