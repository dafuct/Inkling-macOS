import Foundation

/// Chosen local model + generation settings for the real engine.
enum ModelConfig {
    /// Absolute path so it resolves when the app is launched via `open` (CWD = /).
    static let modelDirectory = URL(
        filePath: "/Users/makar/dev/own-cotypist/models/Qwen2.5-1.5B-Instruct-4bit")

    static let maxTokens = 12
    static let promptMaxChars = 400

    /// Steers the instruct model to continue the text instead of chatting.
    static let systemInstruction =
        "You are an inline text autocomplete. Continue the user's text. Reply with ONLY "
        + "the few words that naturally follow — no greeting, no explanation, no quotes, "
        + "and do not repeat the user's text."
}
