import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

// Usage:
//   InklingBench <model-directory>          tune gate thresholds for one model
//   InklingBench compare [model-dir …]      compare models on the tech-conversation
//                                           suite (defaults to all under models/)
//   InklingBench sweep [model-dir]          eager-gate threshold sweep on the tech suite
// The single-model mode dumps per-token confidence + sweeps gate thresholds.
guard CommandLine.arguments.count >= 2 else {
    print("usage: InklingBench <model-directory>")
    print("       InklingBench compare [model-dir …]")
    print("       InklingBench sweep [model-dir]")
    exit(1)
}

if CommandLine.arguments[1] == "compare" {
    let explicit = CommandLine.arguments.dropFirst(2).map { URL(filePath: $0) }
    let dirs = explicit.isEmpty ? TechConversationSuite.defaultModelDirs() : Array(explicit)
    guard !dirs.isEmpty else {
        print("compare: no models given and none found under models/")
        exit(1)
    }
    try await runComparison(modelDirs: dirs)
    exit(0)
}

if CommandLine.arguments[1] == "rawdump" {
    let dir = CommandLine.arguments.count > 2
        ? URL(filePath: CommandLine.arguments[2])
        : URL(filePath: "models/gemma-4-e4b-it-4bit")
    let adhoc = Array(CommandLine.arguments.dropFirst(3))
    try await runRawDump(modelDir: dir, adhocPrompts: adhoc)
    exit(0)
}

if CommandLine.arguments[1] == "sweep" {
    let dir = CommandLine.arguments.count > 2
        ? URL(filePath: CommandLine.arguments[2])
        : URL(filePath: "models/gemma-4-e4b-it-4bit")
    try await runEagerSweep(modelDir: dir)
    exit(0)
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
    Continuation: help me with something
    Text: hello, ho
    Continuation: how are you doing
    Text: Let me know if you have any
    Continuation: questions
    Text: \(text)
    Continuation:
    """
}

// Domain-spread suite + adversarial repetition cases. The latter guard against
// the prefix-echo loop bug: keep them permanently so tuning always checks loops.
let prompts = [
    "Hi team, just following up on the",
    "lol yeah i think we should just",
    "TODO: refactor the parser so it",
    "func add(_ a: Int, _ b: Int) -> Int { return a +",
    "Thanks so much for your hel",
    "The meeting is scheduled for next ",
    "Per my last email, the deliverables are",
    "honestly idk maybe we",
    "Look at this Look Look at this Look Look",   // prefix-echo loop trigger
    "the the the the the",                        // degenerate repetition
    "Look at this fo",                            // partial-word completion (fo -> fox/folder)
]

// Decoding penalty — keep in sync with Inkling's ModelConfig.
let repetitionPenalty: Float = 1.3
let repetitionContextSize = 40

let sweep: [ConfidenceThresholds] = [
    ConfidenceThresholds(firstTokenMinProb: 0.55, minProb: 0.45, dominance: 1.5),
    ConfidenceThresholds(firstTokenMinProb: 0.58, minProb: 0.45, dominance: 1.5),
    ConfidenceThresholds(firstTokenMinProb: 0.65, minProb: 0.45, dominance: 1.5),
]

print("loading \(modelDir.lastPathComponent) …")
let loadStart = Date()
let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
print("loaded in \(Int(Date().timeIntervalSince(loadStart) * 1000)) ms\n")

func fmt(_ d: Double) -> String { String(format: "%.2f", d) }

// --- Per-token probability dump (generate full length, gate at the app's value) ---
let defaults = ConfidenceThresholds(firstTokenMinProb: 0.65, minProb: 0.45, dominance: 1.5)
print("==== per-token confidence (thresholds \(fmt(defaults.firstTokenMinProb))/\(fmt(defaults.minProb))/\(fmt(defaults.dominance)), repPenalty \(fmt(Double(repetitionPenalty)))) ====\n")
for prompt in prompts {
    let r = try await GatedDecoder.decode(
        container: container, systemInstruction: system, userMessage: userMessage(prompt),
        thresholds: defaults, maxTokens: 24, stopEarly: false,
        repetitionPenalty: repetitionPenalty, repetitionContextSize: repetitionContextSize)
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
            thresholds: th, maxTokens: 24, stopEarly: false,
            repetitionPenalty: repetitionPenalty, repetitionContextSize: repetitionContextSize)
        if r.acceptedCount > 0 { shown += 1 }
        lines.append("    \"\(prompt)\" => \(r.acceptedCount == 0 ? "(silent)" : "\"\(r.text)\"")")
    }
    print("first=\(fmt(th.firstTokenMinProb)) min=\(fmt(th.minProb)) dom=\(fmt(th.dominance)) -> shown \(shown)/\(prompts.count)")
    for l in lines { print(l) }
    print("")
}
