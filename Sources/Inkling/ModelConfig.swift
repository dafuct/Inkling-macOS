import Foundation

/// Chosen local model + generation settings + prompt for the real engine.
enum ModelConfig {
    /// Absolute path so it resolves when the app is launched via `open` (CWD = /).
    /// Gemma 4 E4B gives the best completions (incl. partial-word) at ~300ms;
    /// swap to models/Qwen2.5-3B-Instruct-4bit for ~2x faster, slightly rougher.
    static let modelDirectory = URL(
        filePath: "/Users/makar/dev/own-cotypist/models/gemma-4-e4b-it-4bit")

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
        "You are an inline text autocomplete. Given a text fragment, output only the "
        + "text that comes next — first completing the current word if it is partial, "
        + "then continuing naturally. Output just the continuation: no greeting, no "
        + "explanation, no quotes, and never repeat the user's text."

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
        Text: hello, ho
        Continuation: w are you doing
        Text: Let me know if you have any
        Continuation: questions
        Text: \(text)
        Continuation:
        """
    }
}
