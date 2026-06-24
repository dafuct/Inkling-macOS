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
    "I ne",
    "How ar",
    "The quick brown fox jum",
    "Thank you for your he",
]

print("loading \(modelDir.lastPathComponent) …")
let loadStart = Date()
let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
print("loaded in \(Int(Date().timeIntervalSince(loadStart) * 1000)) ms\n")

for prompt in prompts {
    let lmInput = try await container.prepare(input: UserInput(prompt: prompt))
    var params = GenerateParameters()
    params.maxTokens = 8
    let start = Date()
    var out = ""
    let stream = try await container.generate(input: lmInput, parameters: params)
    for await gen in stream {
        if case .chunk(let t) = gen { out += t }
    }
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print("prompt=\"\(prompt)\"\n  -> \"\(out)\"  (\(ms) ms)\n")
}
