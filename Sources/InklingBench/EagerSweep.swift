import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// `InklingBench sweep [model-dir]` — sweeps the confidence gate's first-token /
/// min floors DOWNWARD on the technical-conversation suite, keeping `dominance`
/// as the garbage floor, to find the most eager threshold that still keeps the
/// adversarial loop cases (the last two prompts) silent. Prints shown/total and
/// the adversarial-silent check per rung.
func runEagerSweep(modelDir: URL) async throws {
    let repetitionPenalty: Float = 1.3
    let repetitionContextSize = 40
    let maxTokens = 24
    let prompts = TechConversationSuite.prompts
    let adversarialIdx = Set((prompts.count - TechConversationSuite.adversarialCount ..< prompts.count))

    let ladder: [ConfidenceThresholds] = [
        .init(firstTokenMinProb: 0.65, minProb: 0.45, dominance: 1.5),   // today
        .init(firstTokenMinProb: 0.40, minProb: 0.30, dominance: 1.5),
        .init(firstTokenMinProb: 0.25, minProb: 0.20, dominance: 1.5),
        .init(firstTokenMinProb: 0.15, minProb: 0.12, dominance: 1.5),
        .init(firstTokenMinProb: 0.10, minProb: 0.10, dominance: 1.5),
        .init(firstTokenMinProb: 0.05, minProb: 0.05, dominance: 1.5),
    ]

    func fmt(_ d: Double) -> String { String(format: "%.2f", d) }

    print("loading \(modelDir.lastPathComponent) …")
    let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
    print("loaded — warming up\n")
    _ = try? await GatedDecoder.decode(
        container: container, systemInstruction: TechConversationSuite.system,
        userMessage: TechConversationSuite.userMessage("warm up"), thresholds: ladder[0],
        maxTokens: 4, stopEarly: false, repetitionPenalty: repetitionPenalty,
        repetitionContextSize: repetitionContextSize)

    print("first/min/dom      shown    adversarialSilent")
    for th in ladder {
        var shown = 0
        var advSilent = true
        for (i, p) in prompts.enumerated() {
            let r = try await GatedDecoder.decode(
                container: container, systemInstruction: TechConversationSuite.system,
                userMessage: TechConversationSuite.userMessage(p), thresholds: th,
                maxTokens: maxTokens, stopEarly: false, repetitionPenalty: repetitionPenalty,
                repetitionContextSize: repetitionContextSize)
            if r.acceptedCount > 0 {
                shown += 1
                if adversarialIdx.contains(i) { advSilent = false }
            }
        }
        print("\(fmt(th.firstTokenMinProb))/\(fmt(th.minProb))/\(fmt(th.dominance))"
            + "       \(shown)/\(prompts.count)      \(advSilent ? "yes" : "NO")")
    }
}
