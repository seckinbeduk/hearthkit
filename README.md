# HearthKit

**Run Foundation Models code on Hearth: one local model shared by every app on your Mac.**

[Hearth](https://github.com/seckinbeduk/hearth) is a menu bar app that keeps a model in memory and
serves it to every app on the Mac. HearthKit makes Hearth a Foundation Models `LanguageModel`, so
your code stays what you'd write for Apple Intelligence: sessions, streaming, `@Generable`.

```swift
import FoundationModels
import HearthKit

let session = LanguageModelSession(model: HearthModel(.appleIntelligence))
let recipe = try await session.respond(to: "A quick chickpea dinner", generating: Recipe.self)
```

## Why

- **One model, every app.** An app that embeds a local model loads gigabytes of weights for itself.
  Through Hearth, all your apps share one copy, and the user picks the model once.
- **Same API as Apple Intelligence.** Change one line. `@Generable`, `@Guide`, streaming and
  multi-turn sessions keep working.
- **No overhead.** Apple Intelligence through Hearth answers as fast as calling it directly.
- **Visible.** Each app shows up by name in Hearth's **Who's using it**, with requests and tokens.
- **Keeps working without Hearth.** `HearthModel.preferred()` falls back to Apple Intelligence.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/seckinbeduk/hearthkit.git", from: "0.1.0")
```

Requires macOS 27 and Xcode 27. The Hearth backends need [Hearth 0.2 or later](https://github.com/seckinbeduk/hearth/releases) running.

## Use

```swift
// Apple's on-device model, through Hearth: fast, free, and counted in Hearth.
let session = LanguageModelSession(model: HearthModel(.appleIntelligence, appName: "My App"))

// The local model chosen in Hearth (Qwen, Gemma…), on the GPU.
let local = LanguageModelSession(model: HearthModel(.local, appName: "My App"))

// Hearth if it's running, Apple Intelligence directly if it isn't.
let model = await HearthModel.preferred(appName: "My App")
let fallbackSafe = LanguageModelSession(model: model)

// Streaming works as usual.
for try await snapshot in session.streamResponse(to: "A haiku about a warm hearth") {
    print(snapshot.content)
}
```

| Backend | Answered by | `@Generable` |
|---|---|---|
| `.appleIntelligence` | Apple's on-device model, through Hearth | Guaranteed: Hearth uses guided generation |
| `.local` | The MLX model chosen in Hearth; Apple Intelligence if none is loaded | Best effort: the schema is passed as an instruction |

`appName` is what Hearth shows in **Who's using it**; it defaults to your process name.
`HearthModel.status()` tells you whether Hearth is running, its version, and which local model is loaded.

## The demo

`./run.sh` builds, tests, and runs the same `@Generable` request three ways. On an M3 with 16 GB:

```
── Apple Intelligence, direct ──
✓ 2.4s · Chickpea and Spinach Stir-Fry · 20 min

── Apple Intelligence via Hearth ──
✓ 2.4s · Chickpea and Spinach Stir-Fry · 20 min

── Local model via Hearth ──            (Qwen3 8B, 4-bit)
✓ 8.2s · Chickpea and Spinach Stir-Fry · 20 min

── Streaming through Hearth ──
Flames flicker low,
Smoke curls through silent air—
Warmth blooms in the dark.
```

## How it works

`HearthModel` conforms to `LanguageModel`, the protocol the macOS 27 SDK opened to third-party
models. Its `Executor` turns the session's transcript into chat messages, encodes the request's
`GenerationSchema` as JSON Schema, and calls Hearth's OpenAI-compatible `/v1/chat/completions`
with `response_format: json_schema`, streamed. For Apple Intelligence, Hearth converts the schema
to a `DynamicGenerationSchema` and answers through guided generation; the executor forwards the
reply token by token and Foundation Models decodes it into your type.

## Limitations

- **Tool calling** isn't supported yet.
- **Local models** follow the schema by instruction, not by constrained decoding, so complex
  schemas can fail to decode. Use `.appleIntelligence` when the output must parse.
- **Regex `pattern` guides** aren't supported by Apple's guided generation; Hearth drops them.
  Use enums (`.anyOf`) instead.
- The Apple Intelligence path through Hearth keeps prompts under about 10,000 characters.

## Troubleshooting

**`SensitiveContentAnalysisML error 15`.** Apple Intelligence's safety check failed to start. It
happens with plain `SystemLanguageModel` too, so it isn't HearthKit or Hearth; it has been
[reported to Apple](https://developer.apple.com/forums/thread/836285). Restarting the Mac fixed it in our testing.
HearthKit reports it as `HearthError.appleSafetyCheckFailed`.

**`Hearth isn't running`.** Open Hearth from the menu bar, or use `HearthModel.preferred()` to fall
back to Apple Intelligence.

**`Hearth 0.1 can't return structured output`.** `@Generable` needs Hearth 0.2 or later.

## License

MIT
