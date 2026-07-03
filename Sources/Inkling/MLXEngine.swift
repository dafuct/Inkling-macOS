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

    func suggestion(for context: InklingCore.TextContext, currentWordIsComplete: Bool) async -> String {
        let promptText = CompletionPrompt.prompt(for: context, maxChars: ModelConfig.promptMaxChars)
        guard promptText.count >= 2 else { return "" }
        do {
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
                rawPrompt: promptText,
                stopAtNewline: true,
                stopOnLoop: true)
            if Task.isCancelled { return "" }
            if result.loopDetected { return "" }
            let trimmed = PhraseTrimmer.trim(
                prefixes: result.prefixes,
                probs: result.probs.map(\.top1),
                endedNaturally: result.endedNaturally,
                config: ModelConfig.trim)
            guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ""
            }
            // Raw framing rarely restates, but a rephrase-restart is still the
            // one failure the probability signals can't see; content-word guard.
            if SuggestionRepeatGuard.repeatsRecent(continuation: trimmed, recentText: promptText) {
                return ""
            }
            // BPE boundary artifact: continuing mid-identifier ("loadModelContai")
            // the tokenizer can only emit the word-tail as a fresh " ner" token.
            // When the word under the caret is NOT a complete word, a leading
            // space before a letter/digit means "finish the word" — glue it.
            if !currentWordIsComplete, !context.currentWord.isEmpty, trimmed.first == " ",
               let next = trimmed.dropFirst().first, next.isLetter || next.isNumber {
                return String(trimmed.dropFirst())
            }
            return trimmed
        } catch {
            NSLog("Inkling: MLXEngine error: \(error)")
            return ""
        }
    }
}
