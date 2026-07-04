import Foundation

/// Composes the single prompt preamble the engine prepends before the document
/// tail, in order: instructions → clipboard → screen. Each block is gated and
/// capped by its own builder; blocks are blank-line separated and the result
/// already ends with the separator so the caller prepends it directly before the
/// tail. Returns nil when none apply. Pure.
public enum ContextPreamble {
    public static func build(_ context: PromptContext, tailLength: Int) -> String? {
        // InstructionPreamble.build already appends "\n\n"; the other two do not.
        let instrBlock = context.instructions.flatMap {
            InstructionPreamble.build(instructions: $0, tailLength: tailLength)
        }
        let clipBlock = context.clipboard
            .flatMap { ClipboardContext.build(clipboard: $0, tailLength: tailLength) }
            .map { $0 + "\n\n" }
        let screenBlock = context.screen
            .flatMap { ScreenContext.build(screenText: $0, tailLength: tailLength) }
            .map { $0 + "\n\n" }
        let combined = [instrBlock, clipBlock, screenBlock].compactMap { $0 }.joined()
        return combined.isEmpty ? nil : combined
    }
}
