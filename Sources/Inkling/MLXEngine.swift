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

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
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
                .system(ModelConfig.systemInstruction),
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
            let midWord = !context.currentWord.isEmpty
            let endsWithSpace = promptText.last.map { $0 == " " || $0 == "\n" || $0 == "\t" } ?? true
            return CompletionPrompt.inlineSuggestion(
                continuation: cleaned, midWord: midWord, prefixEndsWithSpace: endsWithSpace)
        } catch {
            NSLog("Inkling: MLXEngine error: \(error)")
            return ""
        }
    }
}
