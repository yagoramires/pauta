import Foundation

/// Onde o app guarda seus dados. A pasta do nome antigo (Radar) é movida para a nova na primeira execução.
enum AppPaths {
    private static let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support")
    static let support = applicationSupport.appendingPathComponent("Pauta")
    static let legacySupport = applicationSupport.appendingPathComponent("Radar")
}

/// Move a pasta antiga para a nova (mover mantém as permissões 0700/0600). Devolve `true` só se moveu; não mexe em
/// nada quando a antiga não existe ou a nova já existe (a nova vence).
func migrateLegacyFolder(from old: URL, to new: URL, fileManager: FileManager = .default) -> Bool {
    guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return false }
    do {
        try fileManager.moveItem(at: old, to: new)
        Log.write("pasta de dados movida de \(old.lastPathComponent) para \(new.lastPathComponent)")
        return true
    } catch {
        Log.write("não consegui mover a pasta \(old.lastPathComponent): \(error.localizedDescription)")
        return false
    }
}
