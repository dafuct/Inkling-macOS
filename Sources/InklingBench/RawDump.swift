import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// `InklingBench rawdump [model-dir]` — decodes a handful of suite prompts
/// through the RAW path with no online stops beyond the budget, dumping every
/// token piece with its top-1/top-2 probability plus the prompt's leading
/// token ids (BOS check). Diagnoses why the raw arm loops/goes silent without
/// any gating in the way.
func runRawDump(modelDir: URL, adhocPrompts: [String] = []) async throws {
    let container = try await loadModelContainer(
        from: modelDir, using: #huggingFaceTokenizerLoader())

    let picks = [11, 17]   // 0-based: mid-identifier + the UA prompt that leaks turn markers
    let prompts = adhocPrompts.isEmpty
        ? picks.map { TechConversationSuite.prompts[$0] }
        : adhocPrompts

    // BOS check: what does encode() put at the head of the raw prompt?
    try await container.perform { ctx in
        let ids = ctx.tokenizer.encode(text: "hello world")
        let head = ids.prefix(3).map { "\($0)=\"\(ctx.tokenizer.decode(tokenIds: [$0]))\"" }
        print("encode(\"hello world\") head: \(head.joined(separator: ", "))")
        print("eosTokenId=\(ctx.tokenizer.eosTokenId.map(String.init) ?? "nil")\n")
    }

    for p in prompts {
        print("PROMPT: \"\(p.suffix(70))\"")
        let r = try await GatedDecoder.decode(
            container: container, systemInstruction: "", userMessage: "",
            thresholds: ConfidenceThresholds(firstTokenMinProb: 0, minProb: 0, dominance: 1.0),
            maxTokens: 40, stopEarly: false,
            repetitionPenalty: 1.0, repetitionContextSize: 0,
            rawPrompt: p)
        for (i, t) in r.probs.enumerated() {
            let piece = t.piece.replacingOccurrences(of: "\n", with: "\\n")
            print(String(format: "  %2d %-16s p1=%.3f p2=%.3f tok=%d",
                         i, (piece as NSString).utf8String!, t.top1, t.top2, t.token))
        }
        print("  endedNaturally=\(r.endedNaturally) full=\"\(r.prefixes.last ?? "")\"\n")
    }
}
