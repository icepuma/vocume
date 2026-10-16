import Testing

@testable import VocumeCore

@Suite("Detectors")
struct DetectorTests {
    /// The text each detector finds in `text`.
    private func found(_ kind: TextKind, in text: String) -> [String] {
        kind.ranges(in: text).map { String(text[$0]) }
    }

    @Test func numbersIncludingOCRLookalikes() {
        let text = "release v0.5.3, effort 0.1 → low, −6 and -б, 12% of $1,234.56 on arm64"
        #expect(found(.numbers, in: text) == ["0.5.3", "0.1", "−6", "-б", "12%", "1,234.56", "64"])
    }

    @Test func lookalikeDigitsInsideWordsAreMisreads() {
        #expect(found(.numbers, in: "marktp1atz-dev and C0de").isEmpty)
        #expect(found(.numbers, in: "arm64 x86 v2beta") == ["64", "86", "2"])
        #expect(found(.numbers, in: "lооk at о").isEmpty)  // Cyrillic о, read for a Latin o
    }

    @Test func emailsAndURLs() {
        #expect(found(.emails, in: "mail jane.doe@example.com or ops @ team.io now").contains("jane.doe@example.com"))
        #expect(found(.emails, in: "mail ops @ team.io now") == ["ops @ team.io"])
        let urls = found(.urls, in: "see https://github.com/icepuma/vocume and docs.apple.com/vision")
        #expect(urls.contains("https://github.com/icepuma/vocume") && urls.contains("docs.apple.com/vision"))
    }

    @Test func networkAndIdentifiers() {
        #expect(
            found(.ips, in: "from 10.0.0.12 to fe80::1ff:fe23:4567:890a") == ["10.0.0.12", "fe80::1ff:fe23:4567:890a"])
        #expect(found(.ids, in: "id 3f2b8c1e-9a4d-4c7e-8b1a-2f6d9e0c5a7b") == ["3f2b8c1e-9a4d-4c7e-8b1a-2f6d9e0c5a7b"])
        #expect(found(.cards, in: "card 4111 1111 1111 1111 exp") == ["4111 1111 1111 1111"])
        #expect(found(.ibans, in: "IBAN DE89 3704 0044 0532 0130 00.") == ["DE89 3704 0044 0532 0130 00"])
        #expect(!found(.phones, in: "call +1 (415) 555-0132 today").isEmpty)
    }

    @Test func secrets() {
        let key = "ghp_" + String(repeating: "aB3", count: 12)
        #expect(found(.secrets, in: "export GITHUB_TOKEN=\(key)").contains { $0.contains(key) })
        #expect(found(.secrets, in: "password: hunter2!x") == ["hunter2!x"])
        #expect(found(.secrets, in: "a perfectly ordinary sentence with words").isEmpty)
    }

    @Test func names() {
        #expect(found(.names, in: "Please forward this to Tim Cook before Friday").contains("Tim Cook"))
        #expect(found(.names, in: "Approved — John Smith on Monday").contains("John Smith"))
    }

    /// Kinds read from the unfolded text keep valid ranges when a line has dashes or Cyrillic.
    @Test func wholeLinesWithLookalikes() {
        #expect(found(.allText, in: "Vocume – Settings") == ["Vocume – Settings"])
        #expect(found(.numbers, in: "build — 6 б") == ["6"])
    }

    @Test func everyKindIsOfferedToTheAI() {
        let prompt = AnnotationPrompt.make(request: "", textSummary: "")
        for kind in TextKind.allCases {
            #expect(prompt.contains("\"\(kind.rawValue)\""), "prompt lacks \(kind.rawValue)")
            #expect(AnnotationPrompt.replySchema.contains("\"\(kind.rawValue)\""), "schema lacks \(kind.rawValue)")
        }
    }

    @Test func inkColors() {
        #expect(InkColor(hue: 4, saturation: 0.8, brightness: 0.9) == .red)
        #expect(InkColor(hue: 210, saturation: 0.7, brightness: 0.8) == .blue)
        #expect(InkColor(hue: 0, saturation: 0.05, brightness: 0.5) == .grey)
        #expect(InkColor(hue: 0, saturation: 0.05, brightness: 0.95) == nil)  // white text isn't "grey"
    }
}
