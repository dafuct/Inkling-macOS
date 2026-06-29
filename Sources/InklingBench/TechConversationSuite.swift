import Foundation

/// Prompt suite + steering for the model comparison (`InklingBench compare`).
///
/// These prompts model how this user actually types: *conversation about code*
/// — PR/review chat, commit messages, design talk, and mid-identifier
/// completions — NOT raw source. The point is to compare candidate models on
/// realistic input rather than generic prose, so the winner is the one that's
/// good at *our* distribution. A few partial-word cases exercise the
/// finish-the-word path; two adversarial loop cases guard the prefix-echo bug.
enum TechConversationSuite {

    /// System steering — identical to the app's, so the comparison reflects the
    /// real instruct path. Ignored for base models (they get `rawPrompt`).
    static let system =
        "You are an inline text autocomplete. Output only the text that comes next. If "
        + "the text stops in the middle of a word, finish that exact word first, then "
        + "continue naturally. Never restart the sentence, never greet, never explain, "
        + "never use quotes, and never repeat the user's text."

    /// Few-shot continuation prompt. Reused two ways: as the instruct `userMessage`
    /// (wrapped in the chat template) and as the base-model `rawPrompt` (plain
    /// text). Same examples either way, so the two paths stay comparable.
    static func userMessage(_ text: String) -> String {
        """
        Continue the text. Output only the next few words.

        Text: The quick brown fox
        Continuation: jumps over the lazy dog
        Text: I was wondering if you could hel
        Continuation: help me with something
        Text: hello, ho
        Continuation: how are you doing
        Text: Let me know if you have any
        Continuation: questions
        Text: \(text)
        Continuation:
        """
    }

    /// Conversation-about-code prompts. Mix of word-boundary and mid-word cases,
    /// project jargon, and chat registers (Slack, review, commits).
    static let prompts: [String] = [
        // --- chat / review register, word boundary ---
        "Hey, can you review my PR when you get a chance? I refactored the event tap so it",
        "yeah i think the bug is in how we debounce the keystrokes before calling the",
        "honestly the MLX metallib build situation is such a",
        "lgtm overall, but can you rename that variable to something more",
        "The confidence gate silently drops any token whose probability is below the",
        "I wrapped the decode call in a Task so it wouldn't block the main",
        "Per the latency budget we want time-to-first-token under 300",
        "I'll open a follow-up issue to handle the partial-word",
        "the repetition penalty finally fixed the prefix-echo",
        "switching the default model from Qwen2.5-3B to the smaller 1.5",
        // --- mid-word / identifier completion (autocomplete fires inside a token) ---
        "can you take a look at my implementation of the Suggestion",
        "we load the weights lazily by calling loadModelContai",
        "the overlay renderer draws ghost text right after the car",
        // --- commit-message register ---
        "fix: suppress new-word suggestions while mid-",
        "refactor: extract the gated decode loop into a shared",
        // --- adversarial: keep permanently so tuning always checks loops ---
        "the the the the the",
        "Look at this Look Look at this Look Look",
    ]

    /// The last `adversarialCount` prompts are the adversarial loop cases
    /// (degenerate repetition + prefix-echo) — they must stay silent at any gate.
    static let adversarialCount = 2

    /// A model is "instruct" if its directory name carries an instruct/chat tag
    /// (`Instruct`, or an `it` segment as in `gemma-...-it-4bit`). Everything else
    /// is treated as a base model and fed `rawPrompt`.
    static func isInstruct(_ name: String) -> Bool {
        let segments = name.lowercased().split(separator: "-").map(String.init)
        return segments.contains { $0 == "instruct" || $0 == "it" }
    }

    /// Default model set when `compare` is given no explicit dirs: every MLX
    /// model folder under `models/`, sorted (groups sizes/families sensibly).
    static func defaultModelDirs() -> [URL] {
        let root = URL(filePath: "models")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root.path)
        else { return [] }
        return entries
            .filter { name in
                let cfg = root.appendingPathComponent(name).appendingPathComponent("config.json")
                return FileManager.default.fileExists(atPath: cfg.path)
            }
            .sorted()
            .map { root.appendingPathComponent($0) }
    }
}
