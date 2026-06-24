import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

// Usage: InklingBench <model-directory>
// Mirrors MLXEngine's few-shot continuation prompt to gauge completion quality.
guard CommandLine.arguments.count >= 2 else {
    print("usage: InklingBench <model-directory>")
    exit(1)
}
let modelDir = URL(filePath: CommandLine.arguments[1])

let system =
    "You are an inline text autocomplete. Given a text fragment, output only the "
    + "text that comes next — first completing the current word if it is partial, "
    + "then continuing naturally. Output just the continuation: no greeting, no "
    + "explanation, no quotes, and never repeat the user's text."

func fewShot(_ text: String) -> String {
    // The text right after "Continuation:" IS the literal insertion — a leading
    // space means a new word, no leading space means completing the current word.
    "Continue the writing. Output only the text to insert at the cursor: begin with"
    + " a space for a new word, or no space to finish the current word.\n\n"
    + "Text: The quick brown fox\nContinuation: jumps over the lazy dog\n"
    + "Text: I was wondering if you could hel\nContinuation:p me with something\n"
    + "Text: hello, ho\nContinuation:w are you doing\n"
    + "Text: Let me know if you have any\nContinuation: questions\n"
    + "Text: \(text)\nContinuation:"
}

let prompts = [
    "hello, ho",
    "I think we should go to the",
    "Can you please send me the",
    "Thanks so much for your hel",
    "The meeting is scheduled for next",
]

print("loading \(modelDir.lastPathComponent) …")
let loadStart = Date()
let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
print("loaded in \(Int(Date().timeIntervalSince(loadStart) * 1000)) ms\n")

for prompt in prompts {
    let input = UserInput(chat: [.system(system), .user(fewShot(prompt))])
    let lmInput = try await container.prepare(input: input)
    var params = GenerateParameters()
    params.maxTokens = 12
    params.temperature = 0
    let start = Date()
    var out = ""
    let stream = try await container.generate(input: lmInput, parameters: params)
    for await gen in stream {
        if case .chunk(let t) = gen { out += t }
    }
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print("prompt=\"\(prompt)\"\n  -> \"\(out)\"  (\(ms) ms)\n")
}
