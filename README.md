# Inkling

On-device, system-wide inline autocomplete for macOS. Inkling shows gray
"ghost text" predictions after your caret in (almost) any text field and lets
you accept them word-by-word — all running locally on Apple Silicon via
[MLX](https://github.com/ml-explore/mlx-swift), with nothing sent to the cloud.

> **Status:** personal, work-in-progress project.
>
> Inkling is a from-scratch, educational, independent on-device autocomplete
> app for macOS.

## How it works

A non-sandboxed menu-bar agent wires together five pieces:

```
keystroke → context (Accessibility) → debounced engine → overlay (ghost text) → accept
```

- **Event tap** captures keystrokes and swallows the accept/dismiss keys when a
  suggestion is showing.
- **Tiered suggestions:** an instant, deterministic completion from your own
  learned vocabulary ("memory") shows immediately, and the on-device LLM
  upgrades it a beat later when it has a better guess.
- **Eager + gated decoding:** suggestions surface readily, but a confidence
  "garbage floor" (dominance + a repetition penalty) keeps degenerate loops and
  rephrases of what you just typed from showing.
- **Overlay** draws the ghost text at the caret; **Tab-accept** inserts it
  word-by-word.

### Project layout

| Target | Responsibility |
|---|---|
| `InklingCore` | Pure logic (gate, memory, prompt/spacing, arbiter) — no MLX/AppKit. Unit-tested. |
| `InklingMLX` | MLX decode loop + confidence gating. |
| `Inkling` | The macOS menu-bar app (AppKit overlay, event tap, Accessibility). |
| `InklingBench` | Offline eval harness for model comparison and threshold tuning. |

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode with the **Metal Toolchain** (`xcodebuild -downloadComponent MetalToolchain`)
  — required to compile MLX's Metal shaders (`swift build` alone cannot).
- The Hugging Face CLI to download models (see below).

## Getting started

```bash
# 1. Download the on-device models into ./models (needs the Hugging Face CLI)
Scripts/fetch-models.sh

# 2. Create a stable self-signed dev identity (keeps the Accessibility grant
#    across rebuilds)
Scripts/make-signing-cert.sh

# 3a. Build + run the app
Scripts/bundle.sh           # produces Inkling.app
open Inkling.app

# 3b. …or build a self-contained, signed DMG with a model bundled inside
Scripts/make-dmg.sh Qwen2.5-3B-Instruct-4bit
```

The default model is `Qwen2.5-3B-Instruct-4bit`. Models are **not** included in
this repo (they're large and gitignored); fetch them with the script above.

On first launch, grant **Accessibility** (and Input Monitoring) in
System Settings → Privacy & Security so the event tap and caret tracking work.

### Using it

- Type anywhere; pause to see a gray suggestion at the caret.
- **`` ` ``** (backtick) accepts the next word; press it repeatedly to accept
  word-by-word.
- **Esc** dismisses the current suggestion.

### Eval harness

```bash
Scripts/run-bench.sh                                  # per-token confidence dump + threshold sweep
.xcbuild/.../InklingBench compare                     # rank installed models on a prompt suite
.xcbuild/.../InklingBench sweep                        # eager-gate threshold ladder
```

## License

[MIT](LICENSE) © 2026 Dmytro Makarenko
