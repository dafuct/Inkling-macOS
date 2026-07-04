import Foundation

/// Builds the optional OCR'd-screen context block for the completion prompt.
/// Pure. Sibling of `ClipboardContext`: same short-tail gate and word-boundary
/// cap, returns the capped text WITHOUT a trailing separator (`ContextPreamble`
/// composes separators between blocks).
public enum ScreenContext {
    public static let maxChars = 240
    public static let shortTailThreshold = 400

    /// nil when the OCR text is empty/whitespace or the tail is long.
    public static func build(screenText: String, tailLength: Int) -> String? {
        let trimmed = screenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, tailLength < shortTailThreshold else { return nil }
        return InstructionPreamble.capToWordBoundary(trimmed, maxChars: maxChars)
    }
}
