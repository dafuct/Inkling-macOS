import Foundation

/// Builds the optional clipboard-context block for the completion prompt. Pure.
/// Sibling of `InstructionPreamble`: same short-tail gate and word-boundary cap,
/// but returns the capped text WITHOUT a trailing separator — `ContextPreamble`
/// composes the separators between blocks.
public enum ClipboardContext {
    /// Hard cap on the injected clipboard text.
    public static let maxChars = 240
    /// Only inject when the document tail is shorter than this (a long tail
    /// already dominates the continuation, so injected context there is dead
    /// weight and pure echo risk). Shared rationale with `InstructionPreamble`.
    public static let shortTailThreshold = 400

    /// nil when the clipboard text is empty/whitespace or the tail is long.
    public static func build(clipboard: String, tailLength: Int) -> String? {
        let trimmed = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, tailLength < shortTailThreshold else { return nil }
        // Reuse InstructionPreamble's boundary-cut (same module, internal).
        return InstructionPreamble.capToWordBoundary(trimmed, maxChars: maxChars)
    }
}
