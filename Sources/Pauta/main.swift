import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    Log.enabled = false
    SelfTest.run()
    print("selftest ok")
    exit(0)
}

/// Renderiza as telas em PNG com dados falsos, sem abrir janela nem usar credenciais.
if let index = arguments.firstIndex(of: "--snapshots"), let directory = arguments.dropFirst(index + 1).first {
    exit(MainActor.assumeIsolated { Snapshots.run(into: directory) })
}

/// O app se chamava Radar: traz a pasta de dados antiga antes de qualquer coisa ler as credenciais.
_ = migrateLegacyFolder(from: AppPaths.legacySupport, to: AppPaths.support)

/// Confere as credenciais salvas nas APIs reais, sem abrir janela.
if arguments.contains("--check") {
    Log.enabled = false
    Task { exit(await Check.run()) }
    dispatchMain()
}

/// Imprime o que o Jira devolve (boards, sprint, meus e livres), sem abrir janela.
if let index = arguments.firstIndex(of: "--dump"), arguments.dropFirst(index + 1).first == "jira" {
    Log.enabled = false
    Task { exit(await JiraDump.run()) }
    dispatchMain()
}

/// Imprime as DMs e menções não lidas do Slack, sem abrir janela.
if let index = arguments.firstIndex(of: "--dump"), arguments.dropFirst(index + 1).first == "slack" {
    Log.enabled = false
    Task { exit(await SlackDump.run()) }
    dispatchMain()
}

/// Imprime os PRs que esperam sua revisão no GitHub (via gh), sem abrir janela.
if let index = arguments.firstIndex(of: "--dump"), arguments.dropFirst(index + 1).first == "github" {
    Log.enabled = false
    Task { exit(await GitHubDump.run()) }
    dispatchMain()
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
