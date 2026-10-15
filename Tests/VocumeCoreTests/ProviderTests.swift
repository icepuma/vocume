import Foundation
import Testing

@testable import VocumeCore

@Suite("Provider detection")
struct ProviderCheckTests {
    @Test func claudeSignedIn() {
        let output = #"{"loggedIn": true, "authMethod": "claude.ai", "email": "a@b.dev", "subscriptionType": "team"}"#
        #expect(ProviderCheck.claude(exitCode: 0, output: output) == .ready(detail: "Signed in as a@b.dev (Team plan)"))
    }

    @Test func claudeSignedOutOrMissing() {
        #expect(!ProviderCheck.claude(exitCode: 0, output: #"{"loggedIn": false}"#).isReady)
        #expect(!ProviderCheck.claude(exitCode: 1, output: "unknown command 'auth'").isReady)
        guard case .unavailable(let reason, _) = ProviderCheck.claude(exitCode: 127, output: "") else {
            Issue.record("expected unavailable")
            return
        }
        #expect(reason.contains("isn't installed"))
    }

    @Test func codexStatus() {
        #expect(
            ProviderCheck.codex(exitCode: 0, output: "Logged in using ChatGPT\n")
                == .ready(detail: "Logged in using ChatGPT"))
        #expect(!ProviderCheck.codex(exitCode: 1, output: "Not logged in").isReady)
        #expect(!ProviderCheck.codex(exitCode: 0, output: "Not logged in").isReady)
        #expect(!ProviderCheck.codex(exitCode: 127, output: "").isReady)
    }

    @Test func ollamaStatus() {
        #expect(!ProviderCheck.ollama(visionModels: nil).isReady)
        #expect(!ProviderCheck.ollama(visionModels: []).isReady)
        #expect(ProviderCheck.ollama(visionModels: ["qwen2.5vl:7b"]) == .ready(detail: "1 vision model installed"))
    }
}

@Suite("Ollama wire format")
struct OllamaTests {
    @Test func parsesModelNames() throws {
        let tags = #"{"models":[{"name":"qwen2.5vl:7b","size":1},{"name":"llama3.2:3b"}]}"#
        #expect(try Ollama.modelNames(fromTags: Data(tags.utf8)) == ["qwen2.5vl:7b", "llama3.2:3b"])
    }

    @Test func detectsVisionCapability() {
        #expect(Ollama.supportsVision(showResponse: Data(#"{"capabilities":["completion","vision"]}"#.utf8)))
        #expect(!Ollama.supportsVision(showResponse: Data(#"{"capabilities":["completion"]}"#.utf8)))
        #expect(Ollama.supportsVision(showResponse: Data(#"{"details":{}}"#.utf8)))  // older servers
        #expect(!Ollama.supportsVision(showResponse: Data("not json".utf8)))
    }

    @Test func buildsChatRequestWithImage() throws {
        let body = try Ollama.chatBody(model: "m", system: "sys", prompt: "hi", image: Data([1, 2, 3]))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "m")
        #expect(json["stream"] as? Bool == false)
        #expect(json["think"] as? Bool == false)
        #expect((json["format"] as? [String: Any])?["type"] as? String == "array", "enforces the reply's JSON shape")
        let schema = AnnotationPrompt.replySchema
        #expect(
            schema.range(of: #""color""#)!.lowerBound < schema.range(of: #""x""#)!.lowerBound,
            "colour before coordinates")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[1]["images"] as? [String] == [Data([1, 2, 3]).base64EncodedString()])
        let plain = try Ollama.chatBody(model: "m", system: "s", prompt: "p", image: Data(), enforcingFormat: false)
        #expect((try JSONSerialization.jsonObject(with: plain) as? [String: Any])?["format"] == nil)
    }

    @Test func readsChatReply() throws {
        let reply = #"{"model":"m","message":{"role":"assistant","content":"[{\"type\":\"box\"}]"},"done":true}"#
        #expect(try Ollama.reply(fromChat: Data(reply.utf8)) == #"[{"type":"box"}]"#)
    }
}
