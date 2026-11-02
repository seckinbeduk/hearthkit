import Foundation
import FoundationModels

/// A Foundation Models `LanguageModel` served by Hearth, the local inference app for the Mac
/// (github.com/seckinbeduk/hearth).
///
/// Use it wherever you'd use `SystemLanguageModel`:
///
/// ```swift
/// let session = LanguageModelSession(model: HearthModel(.appleIntelligence))
/// let recipe = try await session.respond(to: "A quick chickpea dinner", generating: Recipe.self)
/// ```
///
/// Every app on the Mac shares the one model Hearth keeps in memory, instead of each loading
/// its own copy, and each app shows up by name in Hearth's "Who's using it".
public struct HearthModel: LanguageModel, Sendable {
    /// Which of Hearth's models answers.
    public enum Backend: String, Sendable, Hashable, CaseIterable {
        /// The local MLX model chosen in Hearth (Qwen, Gemma…), on the GPU.
        case local = "hearth"
        /// Apple's on-device model, through Hearth: fast, free, and counted in Hearth's stats.
        case appleIntelligence = "apple-intelligence"
    }

    public let backend: Backend
    /// Shown in Hearth's "Who's using it".
    public let appName: String
    /// Where Hearth listens. Nil finds it (port 8800, or the next free one Hearth picked).
    public let baseURL: URL?

    public init(_ backend: Backend = .local, appName: String = ProcessInfo.processInfo.processName, baseURL: URL? = nil) {
        self.backend = backend
        self.appName = appName
        self.baseURL = baseURL
    }

    /// Hearth turns a response schema into guided generation for Apple Intelligence, so `@Generable`
    /// output always parses there. Local models get the schema as an instruction (best effort).
    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(backend: backend, appName: appName, baseURL: baseURL)
    }

    /// Whether Hearth is running on this Mac right now.
    public static func isRunning() async -> Bool {
        await HearthConnection.discover() != nil
    }

    /// Hearth when it's running, Apple Intelligence directly otherwise, so an app keeps working either way.
    public static func preferred(_ backend: Backend = .appleIntelligence,
                                 appName: String = ProcessInfo.processInfo.processName) async -> any LanguageModel {
        await isRunning() ? HearthModel(backend, appName: appName) : SystemLanguageModel.default
    }

    // MARK: - Executor

    /// Sends each request to Hearth's OpenAI-compatible endpoint and streams the answer back.
    /// Stateless: Hearth holds the model and its cache, so there's nothing to load or keep here.
    public struct Executor: LanguageModelExecutor, Sendable {
        public struct Configuration: Hashable, Sendable {
            public let backend: Backend
            public let appName: String
            public let baseURL: URL?
        }

        let configuration: Configuration

        public init(configuration: Configuration) throws {
            self.configuration = configuration
        }

        public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: HearthModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            let connection: HearthConnection
            if let baseURL = configuration.baseURL {
                connection = HearthConnection(baseURL: baseURL)
            } else if let found = await HearthConnection.discover() {
                connection = found
            } else {
                throw HearthError.notRunning
            }

            let entryID = UUID().uuidString
            await channel.send(.response(entryID: entryID, action: .updateMetadata([
                "modelID": configuration.backend.rawValue,
                "requestID": request.id.uuidString,
                "server": connection.baseURL.absoluteString,
            ])))

            // A @Generable request carries its schema; Hearth expects standard JSON Schema,
            // which is what GenerationSchema encodes to.
            let schema = try request.schema.map { try JSONEncoder().encode($0) }
            let body = try HearthConnection.chatBody(
                model: configuration.backend.rawValue,
                messages: TranscriptMessages.messages(from: request.transcript),
                temperature: request.generationOptions.temperature,
                maxTokens: request.generationOptions.maximumResponseTokens,
                schema: schema
            )

            var usage: (prompt: Int, completion: Int) = (0, 0)
            for try await line in try await connection.stream(body: body, appName: configuration.appName) {
                switch SSE.parse(line) {
                case .text(let text):
                    await channel.send(.response(entryID: entryID, action: .appendText(text, tokenCount: 1)))
                case .usage(let prompt, let completion):
                    usage = (prompt, completion)
                case .error(let message):
                    throw HearthError.server(message)
                case .done, nil:
                    continue
                }
            }
            await channel.send(.response(entryID: entryID, action: .updateUsage(
                input: .init(totalTokenCount: usage.prompt, cachedTokenCount: 0),
                output: .init(totalTokenCount: usage.completion, reasoningTokenCount: 0)
            )))
        }
    }
}

public enum HearthError: Error, LocalizedError, Equatable {
    case notRunning
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning: "Hearth isn't running. Open it from the menu bar, or get it at github.com/seckinbeduk/hearth."
        case .server(let message): "Hearth: \(message)"
        }
    }
}
