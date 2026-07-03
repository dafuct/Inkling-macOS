import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import InklingCore

/// One generated token plus its decoded text and confidence. Used by the eval
/// harness to show what was kept vs. rejected.
public struct TokenProb: Sendable {
    public let token: Int
    public let piece: String
    public let top1: Double
    public let top2: Double
}

/// Result of one gated decode.
public struct GatedDecodeResult: Sendable {
    /// Every generated step (for diagnostics), aligned in order.
    public let probs: [TokenProb]
    /// How many leading tokens the gate keeps. 0 means "show nothing".
    public let acceptedCount: Int
    /// Decoded text of just the accepted tokens (raw — caller still cleans it).
    public let text: String
    /// `prefixes[i]` is the decoded text of tokens 0...i — cumulative, so
    /// multi-token UTF-8 sequences are always whole. Input to PhraseTrimmer.
    public let prefixes: [String]
    /// Generation stopped because the model closed the text (EOS or newline),
    /// not because the budget or a floor cut it off.
    public let endedNaturally: Bool
    /// Degenerate repetition was detected (only when `stopOnLoop`); the caller
    /// should suppress the suggestion.
    public let loopDetected: Bool
}

/// Greedy decoding with confidence gating, shared by the app and the harness.
public enum GatedDecoder {
    /// Generate a continuation for `systemInstruction` + `userMessage`, recording
    /// each token's confidence and keeping only the confident leading run.
    ///
    /// - `stopEarly`: true for the app (stop generating at the first token that
    ///   fails the gate — minimal latency on the common silent path). false for
    ///   the harness (generate the full `maxTokens` so rejected tail tokens are
    ///   visible for tuning).
    /// - `rawPrompt`: when set, the model is fed this plain text directly
    ///   (tokenized with no chat template) and `systemInstruction`/`userMessage`
    ///   are ignored. Use it for BASE (non-instruct) models, which do pure
    ///   continuation and have no chat template — the harness compares them
    ///   against instruct models this way. nil = the normal instruct chat path.
    public static func decode(
        container: ModelContainer,
        systemInstruction: String,
        userMessage: String,
        thresholds: ConfidenceThresholds,
        maxTokens: Int,
        stopEarly: Bool,
        repetitionPenalty: Float,
        repetitionContextSize: Int,
        rawPrompt: String? = nil,
        stopAtNewline: Bool = false,
        stopOnLoop: Bool = false
    ) async throws -> GatedDecodeResult {
        try await container.perform { ctx in
            let lmInput: LMInput
            if let rawPrompt {
                // Raw continuation: tokenize the text as-is and continue it.
                // encode() does NOT add special tokens here, and BOS-trained
                // models (Gemma!) degenerate into pathological echo-loops with
                // p≈1.0 when the sequence doesn't start with it — so prepend
                // the model's BOS explicitly when the vocabulary has one.
                var ids = ctx.tokenizer.encode(text: rawPrompt)
                if let bos = ["<bos>", "<s>"].compactMap(ctx.tokenizer.convertTokenToId).first,
                   ids.first != bos {
                    ids.insert(bos, at: 0)
                }
                lmInput = LMInput(tokens: MLXArray(ids))
            } else {
                let input = UserInput(chat: [
                    .system(systemInstruction),
                    .user(userMessage),
                ])
                lmInput = try await ctx.processor.prepare(input: input)
            }

            var params = GenerateParameters()
            params.temperature = 0                     // greedy -> ArgMaxSampler
            if repetitionPenalty > 1 {
                params.repetitionPenalty = repetitionPenalty
                params.repetitionContextSize = repetitionContextSize
            }
            // Penalty processor down-weights tokens already in the recent context
            // (incl. the prompt), composed into the recorder so the gate sees the
            // penalized distribution. This is what stops prefix-echo / loop output
            // that confidence gating alone can't catch (loop tokens are confident).
            let recorder = ConfidenceLogitProcessor(inner: params.processor())
            let sampler = params.sampler()

            var iterator = try TokenIterator(
                input: lmInput, model: ctx.model, cache: nil,
                processor: recorder, sampler: sampler, maxTokens: maxTokens)

            // Turn-end markers are hard stops alongside EOS: an instruct model
            // continuing raw text may close its "turn" and then degenerate —
            // everything after the marker is garbage by construction. Matched
            // both by probed id and by decoded piece (vocabularies name these
            // differently: gemma-4's id 106 renders as "<turn|>").
            var stopTokens = Set<Int>()
            if let eos = ctx.tokenizer.eosTokenId { stopTokens.insert(eos) }
            for marker in ["<end_of_turn>", "<turn|>", "<|im_end|>", "<|endoftext|>"] {
                if let id = ctx.tokenizer.convertTokenToId(marker) { stopTokens.insert(id) }
            }
            let stopPieces: Set<String> = [
                "<end_of_turn>", "<start_of_turn>", "<turn|>",
                "<|im_end|>", "<|im_start|>", "<|endoftext|>",
            ]

            var tokens: [Int] = []
            var prefixes: [String] = []
            var endedNaturally = false
            var loopDetected = false
            for _ in 0..<maxTokens {
                if Task.isCancelled { break }
                guard let tok = iterator.next() else { endedNaturally = true; break }
                if stopTokens.contains(tok)
                    || stopPieces.contains(ctx.tokenizer.decode(tokenIds: [tok])) {
                    endedNaturally = true
                    break
                }
                let idx = tokens.count                 // index this token occupies
                tokens.append(tok)
                let prefixText = ctx.tokenizer.decode(tokenIds: tokens)
                if stopAtNewline {
                    let prior = prefixes.last ?? ""
                    let delta = prefixText.count >= prior.count
                        ? String(prefixText.dropFirst(prior.count)) : prefixText
                    if delta.contains(where: { $0 == "\n" || $0 == "\r" }) {
                        tokens.removeLast()            // the newline token itself is never shown
                        endedNaturally = true
                        break
                    }
                }
                prefixes.append(prefixText)
                if stopOnLoop, LoopDetector.hasLoop(tokens) {
                    loopDetected = true
                    break
                }
                let p = recorder.recorded[idx]         // aligned: produced this token
                if stopEarly && !ConfidenceGate.accepts(
                    top1: p.top1, top2: p.top2, isFirst: idx == 0, thresholds: thresholds) {
                    break
                }
            }

            // recorder.recorded may hold one lookahead entry past `tokens`; align.
            let aligned = Array(recorder.recorded.prefix(tokens.count))
            let accepted = ConfidenceGate.acceptedTokenCount(probs: aligned, thresholds: thresholds)
            let text = ctx.tokenizer.decode(tokenIds: Array(tokens.prefix(accepted)))

            let dump = tokens.enumerated().map { i, t in
                TokenProb(
                    token: t, piece: ctx.tokenizer.decode(tokenIds: [t]),
                    top1: aligned[i].top1, top2: aligned[i].top2)
            }
            return GatedDecodeResult(
                probs: dump, acceptedCount: accepted, text: text,
                prefixes: prefixes, endedNaturally: endedNaturally, loopDetected: loopDetected)
        }
    }
}
