import Foundation
import FoundationModels
import HearthKit

/// The same @Generable request, three ways: Apple Intelligence directly, Apple Intelligence
/// through Hearth, and Hearth's local model. Then a streamed answer through Hearth.
@Generable
struct Recipe {
    @Guide(description: "A short name for the dish")
    var name: String

    @Guide(description: "Total time in minutes", .range(5...240))
    var minutes: Int

    @Guide(description: "Ingredients with amounts", .maximumCount(6))
    var ingredients: [String]

    @Guide(description: "Short steps in order", .maximumCount(5))
    var steps: [String]
}

@main
struct Demo {
    static let prompt = "A quick vegetarian dinner with chickpeas and spinach."
    static let instructions = "You write short, practical recipes."

    static func main() async {
        print("HearthKit demo · \(prompt)\n")

        await run("Apple Intelligence, direct", model: SystemLanguageModel.default)

        guard await HearthModel.isRunning() else {
            print("Hearth isn't running, so the Hearth rows are skipped. Open Hearth and run this again.")
            return
        }
        await run("Apple Intelligence via Hearth", model: HearthModel(.appleIntelligence, appName: "HearthKit Demo"))
        await run("Local model via Hearth", model: HearthModel(.local, appName: "HearthKit Demo"))

        print("── Streaming through Hearth ──")
        let session = LanguageModelSession(model: HearthModel(.appleIntelligence, appName: "HearthKit Demo"),
                                           tools: [], instructions: "You write haiku.")
        do {
            var shown = ""
            for try await snapshot in session.streamResponse(to: "A haiku about a warm hearth on a cold night.") {
                let text = snapshot.content
                if text.hasPrefix(shown) { print(text.dropFirst(shown.count), terminator: "") } else { print("\n" + text, terminator: "") }
                fflush(stdout)
                shown = text
            }
            print("\n")
        } catch {
            print("✗ \(error.localizedDescription)\n")
        }

        let fallback = await HearthModel.preferred(appName: "HearthKit Demo")
        print("HearthModel.preferred() picked: \(fallback is HearthModel ? "Hearth" : "Apple Intelligence, direct")")
    }

    static func run(_ label: String, model: some LanguageModel) async {
        print("── \(label) ──")
        let session = LanguageModelSession(model: model, tools: [], instructions: instructions)
        let started = Date()
        do {
            let recipe = try await session.respond(to: prompt, generating: Recipe.self).content
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            print("✓ \(seconds)s · \(recipe.name) · \(recipe.minutes) min")
            print("  ingredients: " + recipe.ingredients.joined(separator: ", "))
            for (index, step) in recipe.steps.enumerated() { print("  \(index + 1). \(step)") }
        } catch {
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            print("✗ \(seconds)s · \(error.localizedDescription)")
        }
        print()
    }
}
