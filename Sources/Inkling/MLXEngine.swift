import Foundation
import InklingCore
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// SuggestionEngine backed by a local MLX instruct model, steered to continue
/// text via a system instruction. Loads the model lazily and keeps it warm.
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

    func suggestion(for context: InklingCore.TextContext) async -> String {
        let promptText = CompletionPrompt.prompt(for: context, maxChars: ModelConfig.promptMaxChars)
        guard promptText.count >= 2 else { return "" }
        do {
            let container = try await loadedContainer()
            let input = UserInput(chat: [
                .system(ModelConfig.systemInstruction(personalization: personalization)),
                .user(ModelConfig.userMessage(for: promptText)),
            ])
            let lmInput = try await container.prepare(input: input)
            var params = GenerateParameters()
            params.maxTokens = ModelConfig.maxTokens
            params.temperature = 0

            var raw = ""
            let stream = try await container.generate(input: lmInput, parameters: params)
            for await generation in stream {
                if Task.isCancelled { break }
                if case .chunk(let text) = generation { raw += text }
            }

            let cleaned = CompletionPrompt.clean(raw)
            let endsWithSpace = promptText.last.map { $0 == " " || $0 == "\n" || $0 == "\t" } ?? true
            return CompletionPrompt.inlineSuggestion(
                continuation: cleaned, currentWord: context.currentWord,
                prefixEndsWithSpace: endsWithSpace)
        } catch {
            NSLog("Inkling: MLXEngine error: \(error)")
            return ""
        }
    }
}
