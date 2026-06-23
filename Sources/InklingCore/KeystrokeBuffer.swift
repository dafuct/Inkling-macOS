/// A fallback record of recently typed characters, used as the prefix when
/// Accessibility cannot read the focused field. Reset on focus change.
public final class KeystrokeBuffer {
    private var chars: [Character] = []
    public init() {}

    public var text: String { String(chars) }

    public func append(_ s: String) { chars.append(contentsOf: s) }
    public func backspace() { if !chars.isEmpty { chars.removeLast() } }
    public func reset() { chars.removeAll() }
}
