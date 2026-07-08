import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// `InklingBench trimsweep [model-dir]` — decodes each focused prompt ONCE (the
/// app's raw-continuation path) then applies `PhraseTrimmer` under several
/// (lengthBonus, punctuationBonus) configs, side-by-side against the full
/// rawOut. Cheap: trimming is pure, so one decode feeds every config. Used to
/// pick knobs that show a COMPLETE phrase — not a one-word stub (undershoot),
/// not a mid-sentence wall (overshoot). Includes the user's real "peaked"
/// budget-list case, where an over-confident first token made the old config
/// cut to one word.
func runTrimSweep(modelDir: URL) async throws {
    print("loading \(modelDir.lastPathComponent) …")
    let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
    let floor = ConfidenceThresholds(firstTokenMinProb: 0.02, minProb: 0.02, dominance: 1.0)

    // (label, lengthBonus, punctuationBonus). maxShownTokens/firstToken/minMean fixed.
    let configs: [(String, Double, Double)] = [
        ("cur  lb.03 pb.25", 0.03, 0.25),
        ("A    lb.06 pb.50", 0.06, 0.50),
        ("B    lb.06 pb.75", 0.06, 0.75),
        ("C    lb.10 pb.50", 0.10, 0.50),
        ("D    lb.08 pb1.0", 0.08, 1.00),
    ]
    func cfg(_ lb: Double, _ pb: Double) -> TrimConfig {
        TrimConfig(firstTokenMinProb: 0.15, lengthBonus: lb, minMeanLogProb: -1.2,
                   maxShownTokens: 16, punctuationBonus: pb)
    }

    // Focused set: the user's peaked budget case (2 caret positions), the known
    // undershoot/overshoot cases, a few good ones (must not regress), + adversarial.
    let budget = "Netflix - 3rd - 10$\nApple One - 16th - 14$\nMedium - 21st - 5$\nYoutube - 18th - 7.5$ "
    let prompts = [
        budget + "Let's create",                       // peaked -> old cut to "30-day"
        budget + "Let",                                 // peaked -> old cut to "'s"
        "the overlay renderer draws ghost text right after the car",  // was «,»
        "honestly the MLX metallib build situation is such a",        // wall-of-text
        "Per the latency budget we want time-to-first-token under 300",
        "привіт, я подивився твій PR, загалом виглядає добре, але треба ще",
        "подивись будь ласка логи в консолі, там повторюється помилка про",
        "the the the the the",                          // adversarial: must stay silent/loop
    ]

    // First decode compiles Metal kernels; never keep it.
    _ = try? await GatedDecoder.decode(
        container: container, systemInstruction: "", userMessage: "", thresholds: floor,
        maxTokens: 4, stopEarly: true, repetitionPenalty: 1.0, repetitionContextSize: 0,
        rawPrompt: "warm up the kernel cache", stopAtNewline: true, stopOnLoop: true)

    for p in prompts {
        let r = try await GatedDecoder.decode(
            container: container, systemInstruction: "", userMessage: "", thresholds: floor,
            maxTokens: 40, stopEarly: true, repetitionPenalty: 1.0, repetitionContextSize: 0,
            rawPrompt: p, stopAtNewline: true, stopOnLoop: true)
        print("[\(p.replacingOccurrences(of: "\n", with: "⏎"))]")
        if r.loopDetected { print("  (loop)\n"); continue }
        print("  rawOut: «\(r.prefixes.last ?? "")»")
        for (label, lb, pb) in configs {
            let t = PhraseTrimmer.trim(
                prefixes: r.prefixes, probs: r.probs.map(\.top1),
                endedNaturally: r.endedNaturally, config: cfg(lb, pb))
            print("  \(label)  «\(t)»")
        }
        print("")
    }
}
