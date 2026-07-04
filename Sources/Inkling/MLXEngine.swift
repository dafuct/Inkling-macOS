import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// SuggestionEngine backed by a local MLX model fed the document tail RAW — no
/// chat template, no few-shot, no repetition penalty. Pure continuation is
/// natively topical, continues the user's language (incl. code-switching) by
/// construction, and its output is caret-exact, so it is inserted verbatim.
/// Where to stop is decided post-hoc by PhraseTrimmer over the whole decoded
/// trajectory. Loads the model lazily and keeps it warm.
actor MLXEngine: SuggestionEngine {
    private let modelDirectory: URL
    private var container: ModelContainer?

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    /// Loads the model now so the first real suggestion isn't delayed.
    func preload() async {
        _ = try? await loadedContainer()
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }
        let c = try await loadModelContainer(
            from: modelDirectory, using: #huggingFaceTokenizerLoader())
        container = c
        return c
    }

    /// SuggestionEngine conformance (no custom instructions, no clipboard).
    func suggestion(for context: InklingCore.TextContext, currentWordIsComplete: Bool) async -> String {
        await suggestion(for: context, currentWordIsComplete: currentWordIsComplete,
                         instructions: nil, clipboard: nil)
    }

    func suggestion(for context: InklingCore.TextContext, currentWordIsComplete: Bool,
                    instructions: String?) async -> String {
        await suggestion(for: context, currentWordIsComplete: currentWordIsComplete,
                         instructions: instructions, clipboard: nil)
    }

    func suggestion(for context: InklingCore.TextContext, currentWordIsComplete: Bool,
                    instructions: String?, clipboard: String?) async -> String {
        let promptText = CompletionPrompt.prompt(for: context, maxChars: ModelConfig.promptMaxChars)
        guard promptText.count >= 2 else { return "" }
        // Optional context preamble (instructions + clipboard), prepended before
        // the document tail on short tails only. nil when nothing applies — then
        // this path is byte-identical to the instruction-only cycle-D result.
        let preamble = ContextPreamble.build(
            instructions: instructions, clipboard: clipboard, tailLength: promptText.count)
        let framed = preamble.map { $0 + promptText } ?? promptText
        let word = context.currentWord
        let completing = !word.isEmpty && !currentWordIsComplete
        do {
            guard completing else {
                let direct = try await decodeAndTrim(rawPrompt: framed, preamble: preamble)
                return Task.isCancelled ? "" : direct
            }
            // Mid-word on a non-dictionary fragment: NEVER glue a direct
            // continuation — BPE seams duplicate letters ("implem"+"ement" →
            // "implemement"). Back up to the word boundary so the model
            // regenerates the word WHOLE, and show only the remainder when it
            // prefix-matches what the user typed. A mid-word suggestion that
            // fights the user's word is worse than silence (and the instant
            // memory tier already covers learned-word completions).
            let backupPrompt = MidWordCompletion.decodePrompt(prefix: framed, currentWord: word)
            let regenerated = try await decodeAndTrim(rawPrompt: backupPrompt, preamble: preamble)
            if Task.isCancelled { return "" }
            guard let remainder = MidWordCompletion.resolve(candidate: regenerated, currentWord: word)
            else { return "" }
            return remainder
        } catch {
            NSLog("Inkling: MLXEngine error: \(error)")
            return ""
        }
    }

    /// One raw decode + trim + guards; "" means nothing worth showing.
    private func decodeAndTrim(rawPrompt: String, preamble: String? = nil) async throws -> String {
        let container = try await loadedContainer()
        let result = try await GatedDecoder.decode(
            container: container,
            systemInstruction: "",                  // unused on the raw path
            userMessage: "",
            thresholds: ModelConfig.onlineFloor,    // catastrophic floor only
            maxTokens: ModelConfig.maxTokens,
            stopEarly: true,
            repetitionPenalty: 1.0,                 // trust the raw distribution
            repetitionContextSize: 0,
            rawPrompt: rawPrompt,
            stopAtNewline: true,
            stopOnLoop: true)
        if result.loopDetected { return "" }
        let trimmed = PhraseTrimmer.trim(
            prefixes: result.prefixes,
            probs: result.probs.map(\.top1),
            endedNaturally: result.endedNaturally,
            config: ModelConfig.trim)
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        // Raw framing rarely restates, but a rephrase-restart is still the one
        // failure the probability signals can't see; content-word guard.
        if SuggestionRepeatGuard.repeatsRecent(continuation: trimmed, recentText: rawPrompt) {
            return ""
        }
        // The shared guard above only sees the last ~16 words of rawPrompt, which
        // are the document tail — not the prepended preamble. Check the preamble
        // explicitly with a wide window so an instruction echo is suppressed.
        if let preamble,
           SuggestionRepeatGuard.repeatsRecent(
               continuation: trimmed, recentText: preamble, recentWindow: 100) {
            return ""
        }
        return trimmed
    }
}
