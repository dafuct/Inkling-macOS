import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

// Usage: InklingBench <model-directory>
// Dumps per-token confidence for a domain-spread prompt suite and sweeps gate
// thresholds, so we can pick defaults from real output.
guard CommandLine.arguments.count >= 2 else {
    print("usage: InklingBench <model-directory>")
    exit(1)
}
let modelDir = URL(filePath: CommandLine.arguments[1])

// Mirrors the app's steering. Kept local to the harness on purpose: the bench
// explores prompts/thresholds; only the gate + decode loop must be shared.
let system =
    "You are an inline text autocomplete. Output only the text that comes next. If "
    + "the text stops in the middle of a word, finish that exact word first, then "
    + "continue naturally. Never restart the sentence, never greet, never explain, "
    + "never use quotes, and never repeat the user's text."

func userMessage(_ text: String) -> String {
    """
    Continue the text. Output only the next few words.

    Text: The quick brown fox
    Continuation: jumps over the lazy dog
    Text: I was wondering if you could hel
    Continuation: p me with something
    Text: hello, ho
    Continuation: w are you doing
    Text: Let me know if you have any
    Continuation: questions
    Text: \(text)
    Continuation:
    """
}

// Domain-spread suite: email, chat, notes, code, mid-word, at-space.
let prompts = [
    "Hi team, just following up on the",
    "lol yeah i think we should just",
    "TODO: refactor the parser so it",
    "func add(_ a: Int, _ b: Int) -> Int { return a +",
    "Thanks so much for your hel",
    "The meeting is scheduled for next ",
    "Per my last email, the deliverables are",
    "honestly idk maybe we",
]

let sweep: [ConfidenceThresholds] = [
    ConfidenceThresholds(firstTokenMinProb: 0.50, minProb: 0.35, dominance: 1.3),
    ConfidenceThresholds(firstTokenMinProb: 0.65, minProb: 0.45, dominance: 1.5),
    ConfidenceThresholds(firstTokenMinProb: 0.80, minProb: 0.55, dominance: 2.0),
]

print("loading \(modelDir.lastPathComponent) …")
let loadStart = Date()
let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
print("loaded in \(Int(Date().timeIntervalSince(loadStart) * 1000)) ms\n")

func fmt(_ d: Double) -> String { String(format: "%.2f", d) }

// --- Per-token probability dump (generate full length, gate at default) ---
let defaults = ConfidenceThresholds()
print("==== per-token confidence (default thresholds \(fmt(defaults.firstTokenMinProb))/\(fmt(defaults.minProb))/\(fmt(defaults.dominance))) ====\n")
for prompt in prompts {
    let r = try await GatedDecoder.decode(
        container: container, systemInstruction: system, userMessage: userMessage(prompt),
        thresholds: defaults, maxTokens: 24, stopEarly: false)
    print("prompt=\"\(prompt)\"")
    for (i, tp) in r.probs.enumerated() {
        let mark = i < r.acceptedCount ? "✓" : "✗"
        print("  \(mark) \"\(tp.piece)\"  p1=\(fmt(tp.top1)) p2=\(fmt(tp.top2))")
    }
    print("  => kept \(r.acceptedCount): \"\(r.text)\"\n")
}

// --- Threshold sweep: shown-vs-silent counts per setting ---
print("==== threshold sweep ====\n")
for th in sweep {
    var shown = 0
    var lines: [String] = []
    for prompt in prompts {
        let r = try await GatedDecoder.decode(
            container: container, systemInstruction: system, userMessage: userMessage(prompt),
            thresholds: th, maxTokens: 24, stopEarly: false)
        if r.acceptedCount > 0 { shown += 1 }
        lines.append("    \"\(prompt)\" => \(r.acceptedCount == 0 ? "(silent)" : "\"\(r.text)\"")")
    }
    print("first=\(fmt(th.firstTokenMinProb)) min=\(fmt(th.minProb)) dom=\(fmt(th.dominance)) -> shown \(shown)/\(prompts.count)")
    for l in lines { print(l) }
    print("")
}
