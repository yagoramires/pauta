import AppKit
import NeyKit
import PautaCore

let app = NSApplication.shared
let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    NeyKitSelfTest.run()
    MainActor.assumeIsolated { PautaApp.selfTest() }
    print("selftest ok")
    exit(0)
}

/// Renderiza as telas em PNG com dados falsos, sem abrir janela nem usar credenciais.
if let index = arguments.firstIndex(of: "--snapshots"), let directory = arguments.dropFirst(index + 1).first {
    app.setActivationPolicy(.prohibited)
    exit(MainActor.assumeIsolated { PautaApp.runSnapshots(into: directory) })
}

/// O app se chamava Radar: traz a pasta de dados antiga antes de qualquer coisa ler as credenciais.
PautaApp.migrateLegacyData()

/// Confere as credenciais salvas nas APIs reais, sem abrir janela.
if arguments.contains("--check") {
    Task { exit(await PautaApp.check()) }
    dispatchMain()
}

/// `--dump jira|slack|github`: imprime o que a API devolve, sem abrir janela.
if let index = arguments.firstIndex(of: "--dump"), let service = arguments.dropFirst(index + 1).first {
    Task { exit(await PautaApp.dump(service) ?? 2) }
    dispatchMain()
}

let delegate = MainActor.assumeIsolated { PautaAppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
