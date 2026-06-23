/// Splits a suggestion into the next chunk to accept (any leading spaces plus
/// the following run of non-space characters) and the untouched remainder.
public enum SuggestionSplitter {
    public static func nextChunk(of suggestion: String) -> (chunk: String, remainder: String) {
        let chars = Array(suggestion)
        var i = 0
        while i < chars.count, chars[i] == " " { i += 1 }   // leading spaces
        while i < chars.count, chars[i] != " " { i += 1 }   // the word
        let chunk = String(chars[0..<i])
        let remainder = i < chars.count ? String(chars[i...]) : ""
        return (chunk, remainder)
    }
}
