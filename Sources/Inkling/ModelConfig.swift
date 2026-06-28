import Foundation
import InklingCore

/// Chosen local model + generation settings + prompt for the real engine.
enum ModelConfig {
    /// Root folder holding installed model directories. Resolved portably so the
    /// app runs as a distributed bundle, a user install, or a dev checkout:
    ///   1. models bundled inside the app (Contents/Resources/models),
    ///   2. ~/Library/Application Support/Inkling/models,
    ///   3. the developer source checkout (fallback).
    static let modelsRoot: URL = {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("models", isDirectory: true)
            if fm.fileExists(atPath: bundled.path) { return bundled }
        }
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("Inkling/models", isDirectory: true)
            if fm.fileExists(atPath: dir.path) { return dir }
        }
        return URL(filePath: "/Users/makar/dev/own-cotypist/models")
    }()
    /// Fallback model when none is selected (best quality).
    static let defaultModelName = "gemma-4-e4b-it-4bit"

    static func directory(for name: String) -> URL {
        modelsRoot.appendingPathComponent(name)
    }
    /// The currently selected model name (persisted), or the default.
    static var currentModelName: String { Settings.selectedModel ?? defaultModelName }
    /// Absolute path to the selected model directory.
    static var modelDirectory: URL { directory(for: currentModelName) }

    // Backstop on generation length. Confidence gating is the real stopper now,
    // so this is a safety ceiling, not the typical suggestion length.
    static let maxTokens = 24
    static let promptMaxChars = 400

    /// Confidence gates for the LLM path. Starting values — tune with InklingBench
    /// (see docs/superpowers/plans). Higher firstTokenMinProb => fewer, surer
    /// suggestions.
    static let confidenceThresholds = ConfidenceThresholds(
        firstTokenMinProb: 0.65, minProb: 0.45, dominance: 1.5)

    /// Role instruction: behave as a completion engine, not a chat assistant.
    static let baseSystemInstruction =
        "You are an inline text autocomplete. Output only the text that comes next. If "
        + "the text stops in the middle of a word, finish that exact word first, then "
        + "continue naturally. Never restart the sentence, never greet, never explain, "
        + "never use quotes, and never repeat the user's text."

    /// The system instruction, optionally appended with a short list of the
    /// writer's frequent words so the model leans toward their vocabulary.
    static func systemInstruction(personalization: String) -> String {
        guard !personalization.isEmpty else { return baseSystemInstruction }
        return baseSystemInstruction
            + " The writer frequently uses these words: \(personalization)."
    }

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
