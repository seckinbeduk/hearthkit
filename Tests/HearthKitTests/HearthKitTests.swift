import Foundation
import FoundationModels
import Testing
@testable import HearthKit

@Suite("Streaming format")
struct SSETests {
    @Test func textDelta() {
        let line = #"data: {"id":"x","choices":[{"index":0,"delta":{"content":"Hel"},"finish_reason":null}]}"#
        #expect(SSE.parse(line) == .text("Hel"))
    }

    @Test func usageAndDone() {
        #expect(SSE.parse(#"data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":34,"total_tokens":46}}"#)
                == .usage(prompt: 12, completion: 34))
        #expect(SSE.parse("data: [DONE]") == .done)
    }

    @Test func inBandError() {
        #expect(SSE.parse(#"data: {"error":{"message":"No model is running.","type":"server_error"}}"#)
                == .error("No model is running."))
    }

    @Test func ignoresNoise() {
        #expect(SSE.parse("") == nil)
        #expect(SSE.parse(": keep-alive") == nil)
        #expect(SSE.parse(#"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#) == nil)
    }
}

@Generable
struct Sample {
    @Guide(description: "A title")
    var title: String
    @Guide(.maximumCount(3))
    var tags: [String]
}

@Suite("Request body")
struct BodyTests {
    @Test func generableSchemaBecomesJSONSchema() throws {
        let schema = try JSONEncoder().encode(Sample.generationSchema)
        let body = try HearthConnection.chatBody(
            model: "apple-intelligence",
            messages: [ChatMessage(role: "system", content: "Be brief."), ChatMessage(role: "user", content: "Hi")],
            temperature: 0.2, maxTokens: 100, schema: schema)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "apple-intelligence")
        #expect(json["stream"] as? Bool == true)
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let inner = try #require((format["json_schema"] as? [String: Any])?["schema"] as? [String: Any])
        let properties = try #require(inner["properties"] as? [String: Any])
        #expect(properties["title"] != nil)
        #expect(properties["tags"] != nil)
    }

    @Test func plainRequestHasNoSchema() throws {
        let body = try HearthConnection.chatBody(model: "hearth", messages: [ChatMessage(role: "user", content: "Hi")],
                                                 temperature: nil, maxTokens: nil, schema: nil)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["response_format"] == nil)
        #expect(json["temperature"] == nil)
    }
}

@Suite("Versions and errors")
struct VersionTests {
    @Test func versionComparison() {
        #expect(HearthConnection.isAtLeast("0.2.0", "0.2"))
        #expect(HearthConnection.isAtLeast("0.10.1", "0.2"))
        #expect(HearthConnection.isAtLeast("1.0", "0.2"))
        #expect(!HearthConnection.isAtLeast("0.1.0", "0.2"))
        #expect(HearthConnection(baseURL: URL(string: "http://x")!, version: nil).supportsStructuredOutput == false)
    }

    @Test func appleSafetyCheckGetsAClearError() {
        let raw = "The operation couldn’t be completed. (com.apple.SensitiveContentAnalysisML error 15.)"
        #expect(HearthError.fromServer(raw) == .appleSafetyCheckFailed)
        #expect(HearthError.fromServer("No model is running.") == .server("No model is running."))
    }

    @Test func clearErrorWhenHearthIsNotThere() async {
        // Nothing listens on port 1.
        let model = HearthModel(.appleIntelligence, appName: "HearthKit Tests", baseURL: URL(string: "http://127.0.0.1:1")!)
        let session = LanguageModelSession(model: model, tools: [], instructions: nil)
        do {
            _ = try await session.respond(to: "Hi")
            Issue.record("expected an error")
        } catch {
            #expect("\(error)".contains("notRunning") || error.localizedDescription.contains("isn't running"))
        }
    }
}

@Generable
enum Pace {
    case relaxed, balanced, packed
}

@Generable
struct Stop {
    @Guide(description: "A place to visit")
    var place: String
    var pace: Pace
}

@Generable
struct Itinerary {
    @Guide(description: "The city")
    var city: String
    @Guide(.maximumCount(3))
    var stops: [Stop]
}

@Suite("Against a running Hearth")
struct LiveTests {
    @Test func structuredAnswerThroughHearth() async throws {
        guard await HearthModel.isRunning() else { return }   // nothing to test without Hearth
        let session = LanguageModelSession(model: HearthModel(.appleIntelligence, appName: "HearthKit Tests"),
                                           tools: [], instructions: "Name things briefly.")
        let sample = try await session.respond(to: "A title and tags for a photo of a sunset at the beach.",
                                               generating: Sample.self).content
        #expect(!sample.title.isEmpty)
        #expect(sample.tags.count <= 3)
    }

    @Test func nestedTypesAndEnumsThroughHearth() async throws {
        guard await HearthModel.isRunning() else { return }
        let session = LanguageModelSession(model: HearthModel(.appleIntelligence, appName: "HearthKit Tests"),
                                           tools: [], instructions: "Plan short city walks.")
        let plan = try await session.respond(to: "Three stops for an afternoon in Istanbul.", generating: Itinerary.self).content
        #expect(!plan.city.isEmpty)
        #expect(!plan.stops.isEmpty && plan.stops.count <= 3)
        #expect(plan.stops.allSatisfy { !$0.place.isEmpty })
    }

    @Test func multiTurnKeepsContext() async throws {
        guard await HearthModel.isRunning() else { return }
        let session = LanguageModelSession(model: HearthModel(.appleIntelligence, appName: "HearthKit Tests"),
                                           tools: [], instructions: "Answer in one short sentence.")
        _ = try await session.respond(to: "My cat is called Pamuk. Just say OK.")
        let answer = try await session.respond(to: "What is my cat called?").content
        #expect(answer.localizedCaseInsensitiveContains("Pamuk"))
    }
}
