/// The three optional text sources injected as a prompt preamble, in
/// composition order: instructions → clipboard → screen. Pure value type.
public struct PromptContext: Equatable, Sendable {
    public var instructions: String?
    public var clipboard: String?
    public var screen: String?

    public init(instructions: String? = nil, clipboard: String? = nil, screen: String? = nil) {
        self.instructions = instructions
        self.clipboard = clipboard
        self.screen = screen
    }

    public static let empty = PromptContext()
}
