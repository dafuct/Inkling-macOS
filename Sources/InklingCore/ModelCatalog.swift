import Foundation

/// Discovers locally-installed models: subdirectories of a root that contain a
/// `config.json` (an MLX model folder).
public enum ModelCatalog {
    public static func availableModels(
        in root: URL, fileManager: FileManager = .default
    ) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        return entries.filter { name in
            let dir = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue
            else { return false }
            return fileManager.fileExists(atPath: dir.appendingPathComponent("config.json").path)
        }.sorted()
    }
}
