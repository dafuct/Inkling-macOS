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
        rawPrompt: String? = nil
    ) async throws -> GatedDecodeResult {
        try await container.perform { ctx in
            let lmInput: LMInput
            if let rawPrompt {
                // Base model: tokenize the text as-is and continue it. BOS is
                // added (addSpecialTokens default), matching a real sequence start.
                let ids = ctx.tokenizer.encode(text: rawPrompt)
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

            var tokens: [Int] = []
            for _ in 0..<maxTokens {
                if Task.isCancelled { break }
                guard let tok = iterator.next() else { break }
                if let eos = ctx.tokenizer.eosTokenId, tok == eos { break }
                let idx = tokens.count                 // index this token occupies
                tokens.append(tok)
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
            return GatedDecodeResult(probs: dump, acceptedCount: accepted, text: text)
        }
    }
}
