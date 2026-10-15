import Foundation

/// A local Ollama server (http://localhost:11434), used with a vision model to annotate.
public enum Ollama {
    public static let baseURL = URL(string: "http://localhost:11434")!

    /// Installed models that can see images, or `nil` when the server isn't reachable.
    public static func visionModels(session: URLSession = .shared) async -> [String]? {
        var tags = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        tags.timeoutInterval = 2
        guard let (data, _) = try? await session.data(for: tags), let names = try? modelNames(fromTags: data) else {
            return nil
        }
        var vision: [String] = []
        for name in names {
            var show = URLRequest(url: baseURL.appendingPathComponent("api/show"))
            show.httpMethod = "POST"
            show.timeoutInterval = 5
            show.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name])
            if let (info, _) = try? await session.data(for: show), supportsVision(showResponse: info) {
                vision.append(name)
            }
        }
        return vision
    }

    /// One non-streaming chat turn with the screenshot attached; returns the reply text.
    ///
    /// Asks Ollama to enforce the reply's JSON shape. Models on its MLX engine (the default build on
    /// Apple silicon) can't, and answer 501; those are asked again without it.
    public static func chat(
        model: String,
        system: String,
        prompt: String,
        image: Data,
        session: URLSession = .shared
    ) async throws -> String {
        func send(enforcingFormat: Bool) async throws -> (Data, Int) {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 600  // local vision models can be slow on large screenshots
            request.httpBody = try chatBody(
                model: model, system: system, prompt: prompt, image: image, enforcingFormat: enforcingFormat)
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
        }
        var (data, status) = try await send(enforcingFormat: true)
        if status == 501 { (data, status) = try await send(enforcingFormat: false) }
        guard status == 200 else {
            throw AnnotationError(description: "Ollama: \(String(decoding: data, as: UTF8.self).prefix(300))")
        }
        return try reply(fromChat: data)
    }

    // MARK: Wire format

    static func modelNames(fromTags data: Data) throws -> [String] {
        struct Tags: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        return try JSONDecoder().decode(Tags.self, from: data).models.map(\.name)
    }

    /// `/api/show` lists `capabilities` (e.g. `["completion", "vision"]`). Older servers don't, so a
    /// model is assumed able to see when the list is missing.
    static func supportsVision(showResponse data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        guard let capabilities = json["capabilities"] as? [String] else { return true }
        return capabilities.contains("vision")
    }

    static func chatBody(
        model: String, system: String, prompt: String, image: Data, enforcingFormat: Bool = true
    ) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            // Thinking multiplied local latency 5–20× without better marks; the model only picks
            // what to mark, OCR places it.
            "think": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt, "images": [image.base64EncodedString()]],
            ],
        ]
        let json = try JSONSerialization.data(withJSONObject: body)
        // Spliced in as text so the schema keeps its property order (see `replySchema`).
        return enforcingFormat ? Data(#"{"format":\#(AnnotationPrompt.replySchema),"#.utf8) + json.dropFirst() : json
    }

    static func reply(fromChat data: Data) throws -> String {
        struct Chat: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        return try JSONDecoder().decode(Chat.self, from: data).message.content
    }
}
