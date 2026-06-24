import Foundation

/// Chosen local model + generation settings + prompt for the real engine.
enum ModelConfig {
    /// Root folder holding installed model directories.
    static let modelsRoot = URL(filePath: "/Users/makar/dev/own-cotypist/models")
    /// Fallback model when none is selected (best quality).
    static let defaultModelName = "gemma-4-e4b-it-4bit"

    static func directory(for name: String) -> URL {
        modelsRoot.appendingPathComponent(name)
    }
    /// The currently selected model name (persisted), or the default.
    static var currentModelName: String { Settings.selectedModel ?? defaultModelName }
    /// Absolute path to the selected model directory.
    static var modelDirectory: URL { directory(for: currentModelName) }

    static let maxTokens = 12
    static let promptMaxChars = 400

    /// Common complete words: when the caret sits right after one of these (no
    /// trailing space), the model continues with a NEW word, so we add a leading
    /// space. Any other partial word is treated as something the model completes.
    static let completeShortWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at", "for",
        "is", "are", "was", "were", "be", "i", "you", "he", "she", "it", "we",
        "they", "this", "that", "with", "as", "by", "next", "last", "my", "your",
        "his", "her", "our", "their", "so", "if", "no", "yes", "do", "did", "can",
    ]

    /// Role instruction: behave as a completion engine, not a chat assistant.
    static let systemInstruction =
        "You are an inline text autocomplete. Output only the text that comes next. If "
        + "the text stops in the middle of a word, finish that exact word first, then "
        + "continue naturally. Never restart the sentence, never greet, never explain, "
        + "never use quotes, and never repeat the user's text."

    /// Few-shot user message that strongly biases the instruct model toward
    /// continuation (incl. partial-word completion) instead of chatting. The
    /// "hello, ho" example specifically breaks the assistant-greeting reflex.
    static func userMessage(for text: String) -> String {
        """
        Continue the text. Output only the next few words.

        Text: The quick brown fox
        Continuation: jumps over the lazy dog
        Text: I was wondering if you could hel
        Continuation: p me with something
        Text: I am fine thank you, I have a sugg
        Continuation: estion for you
        Text: hello, ho
        Continuation: w are you doing
        Text: Let me know if you have any
        Continuation: questions
        Text: \(text)
        Continuation:
        """
    }
}
