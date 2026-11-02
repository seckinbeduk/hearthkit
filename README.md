# HearthKit

**Use Hearth's local models with Apple's Foundation Models framework.**

[Hearth](https://github.com/seckinbeduk/hearth) keeps one model in memory on your Mac and serves
it to every app. HearthKit plugs Hearth into Foundation Models as a `LanguageModel`, so your code
stays exactly what you'd write for Apple Intelligence: sessions, streaming, `@Generable`.

```swift
import FoundationModels
import HearthKit

let session = LanguageModelSession(model: HearthModel(.appleIntelligence))
let recipe = try await session.respond(to: "A quick chickpea dinner", generating: Recipe.self)
```

> Status: experimental. Built against the macOS 27 SDK's third-party model API.

## Why

- **One model for every app.** Embedding a local model costs each app gigabytes of memory.
  With Hearth, three apps share one copy.
- **Same API as Apple Intelligence.** Switch with one line; `@Generable` and streaming keep working.
- **See who uses what.** Each app appears by name in Hearth's "Who's using it", with requests and tokens.
- **Works without Hearth.** `HearthModel.preferred()` falls back to Apple Intelligence directly.

## Backends

| | Answered by | `@Generable` |
|---|---|---|
| `HearthModel(.appleIntelligence)` | Apple's on-device model, through Hearth | Guaranteed: Hearth uses guided generation |
| `HearthModel(.local)` | The MLX model chosen in Hearth (Qwen, Gemma…) | Best effort: the schema is passed as an instruction |

```swift
// Hearth if it's running, Apple Intelligence directly if not.
let model = await HearthModel.preferred(appName: "My App")
let session = LanguageModelSession(model: model)
```

## Requirements

macOS 27, Xcode 27, and Hearth running for the Hearth backends.

## Try it

```sh
./run.sh   # build, test, and run the demo: the same request three ways, plus streaming
```

## How it works

`HearthModel` conforms to `LanguageModel`; its `Executor` turns the session's transcript into chat
messages, encodes the request's `GenerationSchema` as JSON Schema, and calls Hearth's
OpenAI-compatible `/v1/chat/completions` with `response_format: json_schema`. Hearth converts the
schema to a `DynamicGenerationSchema` for Apple Intelligence's guided generation and streams the
answer back, which the executor forwards token by token.

## License

MIT
