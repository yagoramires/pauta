import Foundation

/// Onde o app guarda seus dados. A pasta do nome antigo (Radar) é movida para a nova na primeira execução.
/// Injetável: o selftest usa uma raiz temporária e nunca toca na pasta de verdade.
struct AppPaths {
    let support: URL
    let legacySupport: URL

    init(root: URL) {
        support = root.appendingPathComponent("Pauta")
        legacySupport = root.appendingPathComponent("Radar")
    }

    static let real = AppPaths(root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))

    var credentials: URL { support.appendingPathComponent("credentials.json") }
    var slackState: URL { support.appendingPathComponent("slack-state.json") }
    /// Id da notificação → permalink, para o toque abrir a mensagem certa mesmo depois de reiniciar.
    var notices: URL { support.appendingPathComponent("avisos.json") }
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
