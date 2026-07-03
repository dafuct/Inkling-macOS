import Foundation

/// Builds the optional document preamble that carries the user's custom
/// instructions into the raw-continuation prompt. Pure. The result is meant to
/// be prepended before the document tail; nil means "inject nothing".
public enum InstructionPreamble {
    /// Hard cap on the injected instruction text (excludes the separator).
    public static let maxChars = 240
    /// Only inject when the document tail is shorter than this (long tails
    /// already dominate the continuation, so a preamble there is dead weight
    /// and pure echo risk).
    public static let shortTailThreshold = 400

    public static func build(instructions: String, tailLength: Int) -> String? {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, tailLength < shortTailThreshold else { return nil }
        return capToWordBoundary(trimmed, maxChars: maxChars) + "\n\n"
    }

    /// Truncate to <= maxChars, cutting at the last whitespace within the cap so
    /// a word is never split; if there is no whitespace within the cap, hard-cut.
    static func capToWordBoundary(_ s: String, maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        let cutIndex = s.index(s.startIndex, offsetBy: maxChars)
        let head = s[..<cutIndex]
        if let lastSpace = head.lastIndex(where: { $0.isWhitespace }) {
            return String(head[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        }
        return String(head)
    }
}
