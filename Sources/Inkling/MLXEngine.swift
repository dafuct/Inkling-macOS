import Foundation
import InklingCore
import InklingMLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// SuggestionEngine backed by a local MLX instruct model, steered to continue
/// text and confidence-gated so only sure continuations surface. Loads the model
/// lazily and keeps it warm.
actor MLXEngine: SuggestionEngine {
    private let modelDirectory: URL
    private var container: ModelContainer?
    private var personalization: String = ""

    /// Set the comma-separated frequent-vocabulary hint to inject into prompts.
    func setPersonalization(_ s: String) { personalization = s }

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
                systemInstruction: ModelConfig.systemInstruction(personalization: personalization),
                userMessage: ModelConfig.userMessage(for: promptText),
                thresholds: ModelConfig.confidenceThresholds,
                maxTokens: ModelConfig.maxTokens,
                stopEarly: true,
                repetitionPenalty: ModelConfig.repetitionPenalty,
                repetitionContextSize: ModelConfig.repetitionContextSize)
            if Task.isCancelled { return "" }
            let cleaned = CompletionPrompt.clean(result.text)
            // Eager gating lets fluent sentence-RESTARTS through (the model
            // rephrasing what was just typed instead of continuing); suppress them.
            if SuggestionRepeatGuard.repeatsRecent(continuation: cleaned, recentText: promptText) {
                return ""
            }
            let endsWithSpace = promptText.last.map { $0 == " " || $0 == "\n" || $0 == "\t" } ?? true
            return CompletionPrompt.inlineSuggestion(
                continuation: cleaned, currentWord: context.currentWord,
                prefixEndsWithSpace: endsWithSpace, currentWordIsComplete: currentWordIsComplete)
        } catch {
            NSLog("Inkling: MLXEngine error: \(error)")
            return ""
        }
    }
}
