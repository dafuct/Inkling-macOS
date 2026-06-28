import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// `InklingBench compare [model-dir …]` — runs every candidate model over the
/// technical-conversation suite and prints (1) a latency/coverage summary and
/// (2) every model's continuation side-by-side, so model choice is decided on
/// our real input distribution rather than generic leaderboards.
///
/// Per model it measures: load time, time-to-first-token (a single-token decode,
/// the inline-UX-critical metric), and how often the gate surfaces a suggestion
/// at the app's thresholds. Base models go through the raw-completion path;
/// instruct models through the chat path — same prompts, fair comparison.
func runComparison(modelDirs: [URL]) async throws {
    // Mirror the app's decode settings so the comparison reflects shipped behavior.
    let thresholds = ConfidenceThresholds(firstTokenMinProb: 0.65, minProb: 0.45, dominance: 1.5)
    let repetitionPenalty: Float = 1.3
    let repetitionContextSize = 40
    let maxTokens = 24

    struct Cell {
        let ttftMs: Int
        let kept: String        // cleaned suggestion text, or "(silent)"
        let accepted: Int
    }
    struct ModelResult {
        let name: String
        let kind: String        // "instruct" | "base"
        let loadMs: Int
        let cells: [Cell]
    }

    let prompts = TechConversationSuite.prompts
    var results: [ModelResult] = []

    func fmt(_ d: Double) -> String { String(format: "%.2f", d) }

    print("comparing \(modelDirs.count) models over \(prompts.count) technical-conversation prompts")
    print("gate \(fmt(thresholds.firstTokenMinProb))/\(fmt(thresholds.minProb))/\(fmt(thresholds.dominance)), "
        + "repPenalty \(fmt(Double(repetitionPenalty))), maxTokens \(maxTokens)\n")

    for dir in modelDirs {
        let name = dir.lastPathComponent
        let instruct = TechConversationSuite.isInstruct(name)
        let kind = instruct ? "instruct" : "base"

        print("loading \(name) [\(kind)] …")
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

        // Base models get the few-shot text raw (no chat template); instruct
        // models get nil and go through the chat path. Same examples either way.
        func raw(_ p: String) -> String? {
            instruct ? nil : TechConversationSuite.userMessage(p)
        }
        func runDecode(_ p: String, _ maxTok: Int) async throws -> GatedDecodeResult {
            try await GatedDecoder.decode(
                container: container, systemInstruction: TechConversationSuite.system,
                userMessage: TechConversationSuite.userMessage(p), thresholds: thresholds,
                maxTokens: maxTok, stopEarly: false, repetitionPenalty: repetitionPenalty,
                repetitionContextSize: repetitionContextSize, rawPrompt: raw(p))
        }

        // First decode compiles Metal kernels; never time it.
        _ = try? await runDecode("warm up the kernel cache", 4)

        var cells: [Cell] = []
        for p in prompts {
            // TTFT: a single-token decode is prefill + one forward pass.
            let tt = Date()
            _ = try await runDecode(p, 1)
            let ttftMs = Int(Date().timeIntervalSince(tt) * 1000)
            // Full decode at the app's thresholds for the actual suggestion text.
            let r = try await runDecode(p, maxTokens)
            let kept = r.acceptedCount == 0 ? "(silent)" : CompletionPrompt.clean(r.text)
            cells.append(Cell(ttftMs: ttftMs, kept: kept, accepted: r.acceptedCount))
        }
        results.append(ModelResult(name: name, kind: kind, loadMs: loadMs, cells: cells))
        print("  done\n")
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

    // --- Summary table: latency + coverage at the app's gate -------------------
    print("==== summary ====\n")
    print(pad("model", nameW) + pad("kind", 10) + pad("load(ms)", 10)
        + pad("TTFT med", 10) + pad("TTFT max", 10) + "shown")
    for r in results {
        let ttfts = r.cells.map { $0.ttftMs }
        let shown = r.cells.filter { $0.accepted > 0 }.count
        print(pad(r.name, nameW) + pad(r.kind, 10) + pad("\(r.loadMs)", 10)
            + pad("\(median(ttfts))", 10) + pad("\(ttfts.max() ?? 0)", 10)
            + "\(shown)/\(prompts.count)")
    }
    print("")

    // --- Side-by-side continuations: eyeball quality on real input -------------
    print("==== continuations (gate \(fmt(thresholds.firstTokenMinProb))) ====\n")
    for (i, p) in prompts.enumerated() {
        print("[\(i + 1)] \"\(p)\"")
        for r in results {
            let c = r.cells[i]
            print("   " + pad(r.name, nameW) + " " + c.kept)
        }
        print("")
    }
}
