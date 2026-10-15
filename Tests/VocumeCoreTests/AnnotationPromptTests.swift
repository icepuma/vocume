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

    @Test func fallsBackToDefaults() {
        let prompt = AnnotationPrompt.make(request: "", textSummary: "")
        #expect(prompt.contains(AnnotationPrompt.defaultRequest))
        #expect(prompt.contains("(none)"))
    }
}
