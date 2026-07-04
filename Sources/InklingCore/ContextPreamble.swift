import Foundation

/// Composes the single prompt preamble the engine prepends before the document
/// tail, in order: instructions, then clipboard reference. Each block is gated
/// and capped by its own builder. Returns nil when neither applies. The result
/// already ends with the blank-line separator, so the caller prepends it
/// directly before the tail. Pure.
public enum ContextPreamble {
    public static func build(instructions: String?, clipboard: String?, tailLength: Int) -> String? {
        // InstructionPreamble.build already appends "\n\n"; ClipboardContext does not.
        let instrBlock = instructions.flatMap {
            InstructionPreamble.build(instructions: $0, tailLength: tailLength)
        }
        let clipBlock = clipboard
            .flatMap { ClipboardContext.build(clipboard: $0, tailLength: tailLength) }
            .map { $0 + "\n\n" }
        switch (instrBlock, clipBlock) {
        case (nil, nil): return nil
        case let (i?, nil): return i
        case let (nil, c?): return c
        case let (i?, c?): return i + c
        }
    }
}
