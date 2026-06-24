import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

// Usage: InklingBench <model-directory>
// Loads a local MLX model, runs a few completion prompts, prints output + tok/s.
guard CommandLine.arguments.count >= 2 else {
    print("usage: InklingBench <model-directory>")
    exit(1)
}
let modelDir = URL(filePath: CommandLine.arguments[1])

let prompts = [
    "I think we should go to the",
    "Can you please send me the",
    "The meeting is scheduled for next",
    "Thanks so much for your",
    "Let me know if you have any",
]

print("loading \(modelDir.lastPathComponent) …")
let loadStart = Date()
let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
print("loaded in \(Int(Date().timeIntervalSince(loadStart) * 1000)) ms\n")

for prompt in prompts {
    let system = "You are an inline autocomplete. Continue the user's text. Reply with ONLY the next few words that naturally follow — no greeting, no explanation, no quotes, do not repeat their text."
    let userInput = UserInput(chat: [.system(system), .user(prompt)])
    let lmInput = try await container.prepare(input: userInput)
    var params = GenerateParameters()
    params.maxTokens = 8
    params.temperature = 0   // greedy — deterministic completion, less noise
    let start = Date()
    var out = ""
    let stream = try await container.generate(input: lmInput, parameters: params)
    for await gen in stream {
        if case .chunk(let t) = gen { out += t }
    }
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print("prompt=\"\(prompt)\"\n  -> \"\(out)\"  (\(ms) ms)\n")
}
