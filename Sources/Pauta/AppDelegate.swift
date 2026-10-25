import AppKit
import NeyKitApp
import PautaCore

/// Casca do avulso: o Pauta em si mora no PautaCore, o mesmo que o NeyHub carrega como plugin.
@MainActor
final class PautaAppDelegate: NSObject, NSApplicationDelegate {
    private var pauta: PautaApp?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if HubCheck.isHosted(id: "local.pauta") && HubCheck.leaveForHub(id: "local.pauta", name: "Pauta") { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let pauta = PautaApp(defaults: .standard, hosted: false, version: version)
        pauta.start()
        setupMenu()
        pauta.applyPresence(pauta.presence)
        self.pauta = pauta

        let updater = Updater(name: "Pauta", repo: "yagoramires/pauta", id: "local.pauta")
        pauta.updateReady = updater.staged != nil
        updater.onChange = { [weak pauta, weak updater] in pauta?.updateReady = updater?.staged != nil }
        pauta.onRelaunch = { [weak updater] in updater?.relaunchNow() }
        updater.start()
        self.updater = updater
        // Toda abertura: mostra as novidades uma vez e limpa um preparado velho.
        if let notes = Updater.notesAfterUpdate(id: "local.pauta", current: version) {
            WhatsNew.show(name: "Pauta", version: version, notes: notes)
        }
    }

    /// Para a vigia da área de transferência (um "Conectar" em andamento), o relógio e os avisos antes de sair.
    func applicationWillTerminate(_ notification: Notification) {
        pauta?.stop()
        _ = updater?.applyStaged()
    }

    /// Clique no Dock (modo Tela) ou aberto de novo pelo Finder: traz a janela de volta.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let pauta, pauta.presence.screen else { return true }
        pauta.showScreen()
        return false
    }

    /// No modo Tela (com ícone no Dock) o menu do app é o caminho até as configurações sem o ícone da barra.
    private func setupMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Configurações…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do Pauta", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        // Editar: sem ele ⌘C/⌘V/⌘Z não chegam aos campos de texto (busca, e-mail e site do Jira, tokens).
        let edit = NSMenu(title: "Editar")
        for (title, action, key, mods) in [("Desfazer", "undo:", "z", NSEvent.ModifierFlags.command), ("Refazer", "redo:", "z", [.command, .shift]),
                                           ("Recortar", "cut:", "x", .command), ("Copiar", "copy:", "c", .command),
                                           ("Colar", "paste:", "v", .command), ("Selecionar tudo", "selectAll:", "a", .command)] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key).keyEquivalentModifierMask = mods
            if action == "redo:" { edit.addItem(.separator()) }
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(item)
        NSApp.mainMenu?.addItem(editItem)
    }

    @objc private func showSettings() { pauta?.showSettings() }
}
