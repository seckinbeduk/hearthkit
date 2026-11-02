import Foundation
import FoundationModels

/// Where Hearth is listening, and the HTTP it speaks.
struct HearthConnection: Sendable {
    let baseURL: URL

    /// Hearth prefers port 8800 and falls back to one of the next nine when it's taken.
    static func candidatePorts() -> [Int] {
        var ports = Array(8800...8809)
        if let preferred = CFPreferencesCopyAppValue("hearth.port" as CFString, "io.github.seckinbeduk.hearth" as CFString) as? Int,
           preferred > 0 {
            ports.removeAll { $0 == preferred }
            ports.insert(preferred, at: 0)
        }
        return ports
    }

    /// The first port that answers `/health` as Hearth.
    static func discover() async -> HearthConnection? {
        for port in candidatePorts() {
            guard let base = URL(string: "http://127.0.0.1:\(port)") else { continue }
            var request = URLRequest(url: base.appendingPathComponent("health"))
            request.timeoutInterval = 0.5
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let health = try? JSONDecoder().decode(Health.self, from: data),
                  health.server == "Hearth" else { continue }
            return HearthConnection(baseURL: base)
        }
        return nil
    }

    struct Health: Decodable {
        let server: String?
    }

    /// The `/v1/chat/completions` body: streamed, with usage, and with the schema when there is one.
    static func chatBody(model: String, messages: [ChatMessage], temperature: Double?, maxTokens: Int?,
                         schema: Data?) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        if let temperature { body["temperature"] = temperature }
        if let maxTokens { body["max_tokens"] = maxTokens }
        if let schema {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "Response", "schema": try JSONSerialization.jsonObject(with: schema), "strict": true],
            ]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// Server-sent event lines from Hearth.
    func stream(body: Data, appName: String) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(appName, forHTTPHeaderField: "X-Title")
        request.setValue("\(appName) (HearthKit)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw HearthError.notRunning
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw HearthError.server(SSE.errorMessage(in: data) ?? "request failed (\(status))")
        }
        return bytes.lines
    }
}

struct ChatMessage: Equatable, Sendable {
    let role: String
    let content: String
}

/// Turns a Foundation Models transcript into OpenAI-style chat messages.
enum TranscriptMessages {
    static func messages(from entries: some Collection<Transcript.Entry>) -> [ChatMessage] {
        entries.compactMap { entry -> ChatMessage? in
            switch entry {
            case .instructions(let instructions):
                text(instructions.segments).map { ChatMessage(role: "system", content: $0) }
            case .prompt(let prompt):
                text(prompt.segments).map { ChatMessage(role: "user", content: $0) }
            case .response(let response):
                text(response.segments).map { ChatMessage(role: "assistant", content: $0) }
            case .toolOutput(let output):
                text(output.segments).map { ChatMessage(role: "tool", content: $0) }
            default:
                // Tool calls and reasoning aren't replayed: HearthKit doesn't declare those capabilities.
                nil
            }
        }
    }

    /// Text segments as they are; a structured (@Generable) earlier answer as its JSON.
    static func text(_ segments: [Transcript.Segment]) -> String? {
        let parts = segments.compactMap { segment -> String? in
            switch segment {
            case .text(let text): text.content
            case .structure(let structure): structure.content.jsonString
            default: nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

/// Parses the OpenAI streaming format Hearth uses.
enum SSE {
    enum Event: Equatable {
        case text(String)
        case usage(prompt: Int, completion: Int)
        case error(String)
        case done
    }

    static func parse(_ line: String) -> Event? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)) else { return nil }
        if let message = chunk.error?.message { return .error(message) }
        if let text = chunk.choices?.first?.delta?.content, !text.isEmpty { return .text(text) }
        if let usage = chunk.usage { return .usage(prompt: usage.prompt_tokens, completion: usage.completion_tokens) }
        return nil
    }

    static func errorMessage(in data: Data) -> String? {
        (try? JSONDecoder().decode(Chunk.self, from: data))?.error?.message
    }

    struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
        struct ErrorDetail: Decodable { let message: String }
        let choices: [Choice]?
        let usage: Usage?
        let error: ErrorDetail?
    }
}
