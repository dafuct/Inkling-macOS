import Foundation

/// Chosen local model + generation settings + prompt for the real engine.
enum ModelConfig {
    /// Absolute path so it resolves when the app is launched via `open` (CWD = /).
    static let modelDirectory = URL(
        filePath: "/Users/makar/dev/own-cotypist/models/Qwen2.5-1.5B-Instruct-4bit")

    static let maxTokens = 12
    static let promptMaxChars = 400

    /// Role instruction: behave as a completion engine, not a chat assistant.
    static let systemInstruction =
        "You are an inline text autocomplete. Given a text fragment, output only the "
        + "text that comes next — first completing the current word if it is partial, "
        + "then continuing naturally. Output just the continuation: no greeting, no "
        + "explanation, no quotes, and never repeat the user's text."

    /// Few-shot user message that strongly biases the instruct model toward
    /// continuation (including partial-word completion) instead of chatting.
    static func userMessage(for text: String) -> String {
        """
        Continue the text. Output only the next few words.

        Text: The quick brown fox
        Continuation: jumps over the lazy dog
        Text: I was wondering if you could hel
        Continuation: p me with something
        Text: Let me know if you have any
        Continuation: questions
        Text: \(text)
        Continuation:
        """
    }
}
