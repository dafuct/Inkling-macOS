import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// `InklingBench compare [model-dir …]` — runs every candidate model over the
/// technical-conversation suite and prints (1) a latency/coverage summary and
/// (2) continuations side-by-side, so pipeline/model choices are decided on our
/// real input distribution rather than generic leaderboards.
///
/// Instruct models run TWO arms:
///  - `chat-old`: the pre-redesign shipped pipeline (few-shot chat prompt,
///    repetition penalty 1.3/40, eager gate 0.10/0.10/1.5, 24 tokens);
///  - `raw-new`: the shipped raw-continuation pipeline (document tail fed raw,
///    no penalty, catastrophic online floor, newline/loop stops, PhraseTrimmer
///    + content-word repeat guard — mirror of the app's ModelConfig).
/// Base models keep the single legacy few-shot raw arm.
func runComparison(modelDirs: [URL]) async throws {
    // chat-old constants — the pipeline shipped before the 2026-07-03 redesign.
    let oldThresholds = ConfidenceThresholds(firstTokenMinProb: 0.10, minProb: 0.10, dominance: 1.5)
    let oldPenalty: Float = 1.3
    let oldPenaltyWindow = 40
    let oldMaxTokens = 24

    // raw-new constants — keep in sync with the app's ModelConfig.
    let newFloor = ConfidenceThresholds(firstTokenMinProb: 0.02, minProb: 0.02, dominance: 1.0)
    let newMaxTokens = 40
    let newTrim = TrimConfig(firstTokenMinProb: 0.15, lengthBonus: 0.04, minMeanLogProb: -1.2)

    struct Cell {
        let ttftMs: Int
        let kept: String        // rendered suggestion text, or "(silent)"/"(loop)"/"(repeat)"
        let shown: Bool
    }
    struct ArmResult {
        let name: String        // "<model> [chat-old]" etc.
        let loadMs: Int
        let cells: [Cell]
    }

    let prompts = TechConversationSuite.prompts
    var results: [ArmResult] = []

    func fmt(_ d: Double) -> String { String(format: "%.2f", d) }

    print("comparing \(modelDirs.count) models over \(prompts.count) technical-conversation prompts")
    print("chat-old: gate \(fmt(oldThresholds.firstTokenMinProb))/\(fmt(oldThresholds.dominance)), "
        + "repPenalty \(fmt(Double(oldPenalty))), maxTokens \(oldMaxTokens)")
    print("raw-new:  floor \(fmt(newFloor.firstTokenMinProb)), trim(first \(fmt(newTrim.firstTokenMinProb)), "
        + "λ \(fmt(newTrim.lengthBonus)), τ \(fmt(newTrim.minMeanLogProb))), maxTokens \(newMaxTokens)\n")

    for dir in modelDirs {
        let name = dir.lastPathComponent
        let instruct = TechConversationSuite.isInstruct(name)

        print("loading \(name) [\(instruct ? "instruct" : "base")] …")
        let t0 = Date()
        let container: ModelContainer
        do {
            container = try await loadModelContainer(from: dir, using: #huggingFaceTokenizerLoader())
        } catch {
            print("  ⚠️  skipped (load failed): \(error)\n")
            continue
        }
        let loadMs = Int(Date().timeIntervalSince(t0) * 1000)
        print("  loaded in \(loadMs) ms — warming up …")

        // chat-old for instruct models; legacy few-shot raw for base models.
        func decodeOld(_ p: String, _ maxTok: Int) async throws -> GatedDecodeResult {
            try await GatedDecoder.decode(
                container: container, systemInstruction: TechConversationSuite.system,
                userMessage: TechConversationSuite.userMessage(p), thresholds: oldThresholds,
                maxTokens: maxTok, stopEarly: false, repetitionPenalty: oldPenalty,
                repetitionContextSize: oldPenaltyWindow,
                rawPrompt: instruct ? nil : TechConversationSuite.userMessage(p))
        }
        func renderOld(_ r: GatedDecodeResult) -> (String, Bool) {
            let kept = r.acceptedCount == 0 ? "(silent)" : CompletionPrompt.clean(r.text)
            return (kept, r.acceptedCount > 0)
        }

        // raw-new: the app pipeline verbatim.
        func decodeNew(_ p: String, _ maxTok: Int) async throws -> GatedDecodeResult {
            try await GatedDecoder.decode(
                container: container, systemInstruction: "", userMessage: "",
                thresholds: newFloor, maxTokens: maxTok, stopEarly: true,
                repetitionPenalty: 1.0, repetitionContextSize: 0,
                rawPrompt: p, stopAtNewline: true, stopOnLoop: true)
        }
        func renderNew(_ r: GatedDecodeResult, prompt: String) -> (String, Bool) {
            if r.loopDetected { return ("(loop)", false) }
            let trimmed = PhraseTrimmer.trim(
                prefixes: r.prefixes, probs: r.probs.map(\.top1),
                endedNaturally: r.endedNaturally, config: newTrim)
            if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ("(silent)", false)
            }
            if SuggestionRepeatGuard.repeatsRecent(continuation: trimmed, recentText: prompt) {
                return ("(repeat)", false)
            }
            return ("\"\(trimmed)\"", true)
        }

        // First decode compiles Metal kernels; never time it.
        _ = try? await decodeNew("warm up the kernel cache", 4)

        struct Arm {
            let label: String
            let maxTokens: Int
            let decode: (String, Int) async throws -> GatedDecodeResult
            let render: (GatedDecodeResult, String) -> (String, Bool)
        }
        var arms: [Arm] = []
        if instruct {
            arms.append(Arm(label: "chat-old", maxTokens: oldMaxTokens,
                            decode: decodeOld, render: { r, _ in renderOld(r) }))
            arms.append(Arm(label: "raw-new", maxTokens: newMaxTokens,
                            decode: decodeNew, render: renderNew))
        } else {
            arms.append(Arm(label: "base-fewshot", maxTokens: oldMaxTokens,
                            decode: decodeOld, render: { r, _ in renderOld(r) }))
        }

        for arm in arms {
            var cells: [Cell] = []
            for p in prompts {
                // TTFT: a single-token decode is prefill + one forward pass.
                let tt = Date()
                _ = try await arm.decode(p, 1)
                let ttftMs = Int(Date().timeIntervalSince(tt) * 1000)
                let r = try await arm.decode(p, arm.maxTokens)
                let (kept, shown) = arm.render(r, p)
                cells.append(Cell(ttftMs: ttftMs, kept: kept, shown: shown))
            }
            results.append(ArmResult(name: "\(name) [\(arm.label)]", loadMs: loadMs, cells: cells))
            print("  \(arm.label) done")
        }
        print("")
    }

    guard !results.isEmpty else { print("no models ran."); return }

    func median(_ xs: [Int]) -> Int {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s[s.count / 2]
    }
    func pad(_ s: String, _ w: Int) -> String {
        s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
    }
    let nameW = max(28, (results.map { $0.name.count }.max() ?? 28) + 2)

    // --- Summary table: latency + coverage per arm ------------------------------
    print("==== summary ====\n")
    print(pad("model [arm]", nameW) + pad("load(ms)", 10)
        + pad("TTFT med", 10) + pad("TTFT max", 10) + "shown")
    for r in results {
        let ttfts = r.cells.map { $0.ttftMs }
        let shown = r.cells.filter { $0.shown }.count
        print(pad(r.name, nameW) + pad("\(r.loadMs)", 10)
            + pad("\(median(ttfts))", 10) + pad("\(ttfts.max() ?? 0)", 10)
            + "\(shown)/\(prompts.count)")
    }
    print("")

    // --- Side-by-side continuations: eyeball quality on real input -------------
    print("==== continuations ====\n")
    for (i, p) in prompts.enumerated() {
        print("[\(i + 1)] \"\(p)\"")
        for r in results {
            print("   " + pad(r.name, nameW) + " " + r.cells[i].kept)
        }
        print("")
    }
}
