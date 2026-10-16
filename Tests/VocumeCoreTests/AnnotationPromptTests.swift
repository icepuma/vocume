import Foundation
import Testing

@testable import VocumeCore

@Suite("Annotation prompt")
struct AnnotationPromptTests {
    @Test func parsesArrayInsideProseAndCodeFences() throws {
        let reply = """
            Sure! Here you go:
            ```json
            [{"type":"box","x":0.1,"y":0.1,"w":0.2,"h":0.2,"label":"bug"}]
            ```
            """
        let marks = try AnnotationPrompt.parseMarks(from: reply)
        #expect(marks.count == 1)
        #expect(marks[0].label == "bug")
    }

    @Test(arguments: ["", "I can't see an image.", "] backwards ["])
    func rejectsRepliesWithoutAnArray(reply: String) {
        #expect(throws: AnnotationError.self) { try AnnotationPrompt.parseMarks(from: reply) }
    }

    @Test func includesRequestPaletteAndText() {
        let prompt = AnnotationPrompt.make(request: "redact emails", textSummary: "0.100,0.200,0.300,0.040  hi@x.io")
        #expect(prompt.contains("redact emails"))
        #expect(prompt.contains("hi@x.io"))
        for name in Palette.colors.map(\.name) { #expect(prompt.contains(name)) }
    }

    /// The three schema forms are valid JSON; the strict one lists every field as required and
    /// allows no others (OpenAI's rules, which Codex enforces).
    @Test func schemasAreValid() throws {
        for schema in [
            AnnotationPrompt.replySchema, AnnotationPrompt.objectReplySchema, AnnotationPrompt.strictReplySchema,
        ] {
            #expect(throws: Never.self) { try JSONSerialization.jsonObject(with: Data(schema.utf8)) }
        }
        let strict = try #require(
            try JSONSerialization.jsonObject(with: Data(AnnotationPrompt.strictReplySchema.utf8)) as? [String: Any])
        let items = try #require(
            ((strict["properties"] as? [String: Any])?["marks"] as? [String: Any])?["items"] as? [String: Any])
        let properties = try #require(items["properties"] as? [String: Any])
        #expect(Set(items["required"] as? [String] ?? []) == Set(properties.keys))
        #expect(items["additionalProperties"] as? Bool == false)
    }

    /// Codex fills unused fields with null; they read as unset.
    @Test func nullFieldsReadAsUnset() throws {
        let marks = try AnnotationPrompt.parseMarks(
            from: #"{"marks":[{"type":"redact","detect":"numbers","match":null,"x":null,"color":null}]}"#)
        #expect(marks.count == 1 && marks[0].detect == "numbers" && marks[0].match == nil && marks[0].x == 0)
    }

    /// Every kind the app understands is offered to the AI, in the prompt and in the reply schema.
    @Test func offersEveryKind() {
        let prompt = AnnotationPrompt.make(request: "", textSummary: "")
        for kind in Mark.Kind.allCases {
            #expect(prompt.contains("\"\(kind.rawValue)\""), "prompt lacks \(kind.rawValue)")
            #expect(AnnotationPrompt.replySchema.contains("\"\(kind.rawValue)\""))
        }
    }

    @Test func fallsBackToDefaults() {
        let prompt = AnnotationPrompt.make(request: "", textSummary: "")
        #expect(prompt.contains(AnnotationPrompt.defaultRequest))
        #expect(prompt.contains("(none)"))
    }
}
