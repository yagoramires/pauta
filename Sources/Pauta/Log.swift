import Foundation

/// Registro de depuração em ~/Library/Logs/Pauta/pauta.log: o que o app fez (atualizações, erros),
/// pra entender uma atualização que falhou. Passou de ~1 MB, recomeça.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Pauta/pauta.log")
    private static let limit = 1_000_000
    private static let queue = DispatchQueue(label: "local.pauta.log")
    private static let clock = ISO8601DateFormatter()

    /// Desligado no modo --snapshots, que usa dados de mentira (nas próximas tarefas).
    static var enabled = true

    static func write(_ message: String) {
        guard enabled else { return }
        let line = Data("\(clock.string(from: Date())) \(message)\n".utf8)
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int, size > limit {
                try? manager.removeItem(at: url)
            }
            if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}

func debugLog(_ message: @autoclosure () -> String) {
    Log.write(message())
}
