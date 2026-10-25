import AppKit
import Combine
import NeyKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// O Pauta inteiro, sem a casca: o avulso (`Pauta`) e o plugin do NeyHub (`PautaPlugin`) usam o mesmo.
@MainActor
public final class PautaApp: NSObject, NSPopoverDelegate {
    private let defaults: UserDefaults
    /// Dentro do NeyHub: sem item de login, sem modos, sem atualização e sem pedir notificações.
    private let hosted: Bool
    let paths: AppPaths
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var credentials: Credentials
    /// Muda a cada abertura do popover para o SwiftUI recriar a raiz (filtro e busca zerados, ajustes relidos do disco).
    private var generation = 0
    /// Escuta cliques nos outros apps enquanto o popover está aberto.
    private var outsideClicks: Any?
    let jiraStore = JiraStore(client: nil)
    let prefsStore: PrefsStore
    let slackStore: SlackStore
    let githubStore: GitHubStore
    let notifier: Notifier
    private(set) lazy var poller = Poller(jira: jiraStore, slack: slackStore, github: githubStore,
                                          interval: TimeInterval(prefsStore.prefs.refreshMinutes * 60))
    /// Os fluxos "Conectar" moram aqui (e não na tela): continuam com o popover fechado, enquanto o usuário copia o token no navegador.
    private(set) lazy var connector = Connector(save: { [weak self] in self?.save($0) }, open: { [weak self] in self?.open($0) },
                                                pasteboard: pasteboard)
    /// A vigia do "Conectar" lê esta; o selftest passa uma própria (nunca a do usuário).
    private let pasteboard: NSPasteboard
    let shell: Shell
    private var subscriptions = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var screenWindow: NSWindow?
    /// Abre links (Slack, páginas de token); o selftest troca por um gravador.
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Hospedado: o "Ligar" das notificações vai para a tela de Permissões do NeyHub.
    public var onOpenPermissions: (() -> Void)?
    /// Hospedado: o NeyHub mostra a tela do Pauta (`NeyHost.showScreen`). nil = NeyHub sem esse pedido.
    public var onShowScreen: (() -> Void)?
    /// Avulso: o Updater já preparou uma versão, que entra quando o app fechar.
    public var updateReady = false { didSet { shell.state.updateReady = updateReady } }
    /// Avulso: "Reiniciar agora" ao lado da linha de atualização; a casca liga ao `Updater.relaunchNow`.
    public var onRelaunch: (() -> Void)?

    public convenience init(defaults: UserDefaults, hosted: Bool, version: String) {
        self.init(defaults: defaults, hosted: hosted, version: version, paths: .real, center: nil,
                  github: GitHubStore(details: { try await GitHubClient().details(token: $0) }))
    }

    /// `paths`, `center` e `github` só mudam no selftest: pasta temporária, centro de notificações e `gh` falsos.
    init(defaults: UserDefaults, hosted: Bool, version: String, paths: AppPaths, center: NotifyCenter?, github: GitHubStore,
         pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.hosted = hosted
        self.paths = paths
        // As telas de conexão leem e gravam pelo `Credentials.url`; um app por processo, então vale para todas.
        Credentials.url = paths.credentials
        credentials = Credentials.load()
        prefsStore = PrefsStore(defaults: defaults)
        githubStore = github
        let notifier = Notifier(hosted: hosted, center: center, linksURL: paths.notices)
        self.notifier = notifier
        // O SlackStore grava o registro de "já avisado" antes de chamar `notify`, então filtrar aqui não trava o registro.
        let prefsStore = prefsStore
        slackStore = SlackStore(client: nil, stateURL: paths.slackState, notify: { [weak notifier] in
            notifier?.postIfSlackClosed(notifiable($0, prefs: prefsStore.prefs))
        })
        shell = Shell(state: PopoverState(version: version, hosted: hosted))
        super.init()
        slackStore.open = { [weak self] in self?.open($0) }
        shell.relaunch = { [weak self] in if self?.hosted == false { self?.onRelaunch?() } }
        shell.openPermissions = { [weak self] in self?.onOpenPermissions?() }
        shell.checkPermission = { [weak self] in self?.checkPermission() }
        shell.presence = hosted ? nil : presence
        shell.onPresence = { [weak self] presence in
            guard let self else { return }
            presence.save(defaults)
            shell.presence = presence
            applyPresence(presence)
        }
    }

    public func start() {
        // O app se chamava Radar: traz a pasta de dados antiga antes de ler as credenciais (o avulso já fez isso no main).
        if migrateLegacyFolder(from: paths.legacySupport, to: paths.support) { credentials = Credentials.load() }
        // Ícone reativo: qualquer mudança nos três stores redesenha a barra.
        Publishers.MergeMany(jiraStore.objectWillChange, slackStore.objectWillChange, githubStore.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.updateBar() }
            .store(in: &subscriptions)
        // Sem refreshContent(): recriaria o popover e tiraria o usuário dos ajustes; o PopoverView observa o PrefsStore.
        // Só o intervalo mexe no timer: trocar densidade ou filtros não pode reiniciar a contagem.
        prefsStore.$prefs.map(\.refreshMinutes).removeDuplicates()
            .sink { [weak self] in self?.poller.setInterval(minutes: $0) }
            .store(in: &subscriptions)
        // O @Published avisa no willSet: `prefsStore.prefs` ainda é o valor velho, então a barra usa o que chegou.
        prefsStore.$prefs.removeDuplicates()
            .sink { [weak self] in self?.updateBar(prefs: $0) }
            .store(in: &subscriptions)
        jiraStore.reconfigure(credentials)
        slackStore.reconfigure(credentials)
        notifier.onOpen = { [weak self] id, action in self?.handleNotification(identifier: id, actionIdentifier: action) }
        notifier.start()
        checkPermission()
        poller.start()
        // Para funcionar "sozinho": na primeira vez já entra nos itens de início. No NeyHub o login é dele.
        if !hosted, !defaults.bool(forKey: "loginItemOffered") {
            defaults.set(true, forKey: "loginItemOffered")
            do { try SMAppService.mainApp.register() } catch { debugLog("abrir ao iniciar falhou: \(error)") }
        }
        debugLog("iniciou\(hosted ? " no NeyHub" : "") · jira \(credentials.jiraReady ? "configurado" : "sem credenciais") · slack \(credentials.slackReady ? "configurado" : "sem credenciais")")
    }

    /// Desinstalar no NeyHub (e fechar o avulso): para o relógio, o acordar, a vigia da área de transferência e os avisos.
    public func stop() {
        poller.stop()
        connector.cancelAll()
        notifier.stop()
        subscriptions = []
        setMenuBarVisible(false)
        removeOutsideClicks()
        settingsWindow?.close()
        screenWindow?.close()
        debugLog("parou")
    }

    /// false REMOVE o ícone; true cria com autosaveName "local.pauta" (a posição na barra é lembrada).
    public func setMenuBarVisible(_ visible: Bool) {
        if !visible, let statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "local.pauta"
            item.button?.target = self
            item.button?.action = #selector(toggle)
            statusItem = item
            updateBar()
        }
    }

    public func makeScreen() -> NSViewController {
        NSHostingController(rootView: ScreenView(slack: slackStore, jira: jiraStore, github: githubStore, connector: connector,
                                                 prefs: prefsStore, shell: shell, onSave: { [weak self] in self?.save($0) },
                                                 refresh: { [weak self] in self?.poller.refreshNow() }))
    }

    public func makeSettings() -> NSViewController {
        NSHostingController(rootView: SettingsView(slack: slackStore, jira: jiraStore, connector: connector, prefs: prefsStore,
                                                   shell: shell, onSave: { [weak self] in self?.save($0) })
            .frame(width: 420).grafiteWindow())
    }

    /// Hospedado sem permissão de notificações: "Notificações desligadas · Ligar" nos ajustes e no rodapé da tela. Confere ao
    /// iniciar e a cada abertura dos ajustes; nunca pede ao sistema.
    func checkPermission() {
        guard hosted else { return }
        notifier.checkPermission { [weak self] allowed in self?.shell.notificationsOff = !allowed }
    }

    /// Os avisos do Pauta não têm botões: só o toque, que abre a mensagem.
    public func notificationCategories() -> Set<UNNotificationCategory> { [] }

    /// Toque num aviso (`local.pauta.<canal>:<ts>`), venha do próprio delegate (avulso) ou do NeyHub. Sem o prefixo não é
    /// do Pauta. Hospedado com tela, mostra a tela do Pauta no NeyHub; em qualquer caso abre a mensagem no Slack.
    /// A presença é a que o NeyHub aplica: mesmo domínio (`AppDefaults.forApp("local.pauta")` = `defaults`).
    public func handleNotification(identifier: String, actionIdentifier: String) {
        guard identifier.hasPrefix(Notifier.prefix), actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        if hosted, let onShowScreen, Presence.load(defaults, hasScreen: true).normalized(hasScreen: true).screen { onShowScreen() }
        let parts = identifier.dropFirst(Notifier.prefix.count).split(separator: ":", maxSplits: 1).map(String.init)
        // Fora do mapa (aviso antigo ou além dos 200) mas com cara de "<canal>:<ts>": abre a conversa sem o permalink.
        // O resumo (e qualquer outra coisa) só abre o Slack.
        guard parts.count == 2, Double(parts[1]) != nil else { return slackStore.openSlack() }
        let link = notifier.links.link(for: identifier) ?? ""
        slackStore.openLink(channel: parts[0], ts: parts[1], permalink: link.isEmpty ? nil : URL(string: link))
    }

    // MARK: Avulso

    /// Modo do avulso. Sem escolha salva fica só na barra de menus, como na 0.1.0 (o padrão do NeyKit com tela seria "os dois").
    public var presence: Presence {
        Presence.load(defaults, hasScreen: false).normalized(hasScreen: true)
    }

    /// Avulso: troca o modo na hora, sem reiniciar. Tela = ícone no Dock + janela; barra de menus = o ícone com o popover.
    public func applyPresence(_ presence: Presence) {
        guard !hosted else { return }
        setMenuBarVisible(presence.menuBar)
        NSApp.setActivationPolicy(presence.screen ? .regular : .accessory)
        if presence.screen { showScreen() } else { screenWindow?.close() }
    }

    public func showScreen() {
        if screenWindow == nil {
            screenWindow = window(makeScreen(), title: "Pauta")
            screenWindow?.setContentSize(NSSize(width: 1060, height: 640))
            screenWindow?.center()
        }
        bringToFront(screenWindow)
    }

    /// Janela de configurações do avulso: o menu do app (`⌘,`) no modo Tela.
    public func showSettings() {
        if settingsWindow == nil { settingsWindow = window(makeSettings(), title: "Configurações do Pauta") }
        bringToFront(settingsWindow)
    }

    private func window(_ controller: NSViewController, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func bringToFront(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Barra de menus

    private func updateBar(prefs: Prefs? = nil) {
        guard let button = statusItem?.button else { return }
        // Erro de qualquer serviço conectado vira o triângulo; "gh não logado" não é erro, a seção explica.
        let failed = jiraStore.error != nil || slackStore.error != nil || githubStore.error != nil
        let (slack, jira, github) = barCounts(slack: slackStore.items, mine: jiraStore.mine.count, freeCount: jiraStore.freeCount,
                                              prs: githubStore.count, prefs: prefs ?? prefsStore.prefs)
        let text = barDescription(slack: slack, jira: jira, github: github, failed: failed)
        button.image = barImage(barState(slack: slack, jira: jira, github: github, failed: failed), description: text)
        button.toolTip = text
    }

    private func save(_ saved: Credentials) {
        let new = saved.trimmed()
        new.save()
        credentials = new
        jiraStore.reconfigure(new)
        slackStore.reconfigure(new)
        poller.refreshNow(reason: "ajustes salvos")
        debugLog("credenciais salvas · jira \(new.jiraReady) · slack \(new.slackReady)")
        // Sem refreshContent(): recriar a raiz tiraria o usuário dos ajustes e zeraria filtro e busca. Os stores e o
        // Connector publicam a mudança, e os ajustes releem o disco quando o "conectado" muda.
    }

    private func refreshContent() {
        generation += 1
        (popover.contentViewController as? NSHostingController<AnyView>)?.rootView = AnyView(
            PopoverView(slack: slackStore, jira: jiraStore, github: githubStore, connector: connector, prefs: prefsStore, shell: shell,
                        onSave: { [weak self] in self?.save($0) },
                        refresh: { [weak self] in self?.poller.refreshNow() })
                .id(generation))
    }

    @objc private func toggle() {
        if popover.isShown { return popover.performClose(nil) }
        guard let button = statusItem?.button else { return }
        if popover.contentViewController == nil {
            popover.behavior = .transient
            popover.appearance = NSAppearance(named: .darkAqua)
            popover.delegate = self
            let host = NSHostingController(rootView: AnyView(EmptyView()))
            // A janelinha acompanha o tamanho do conteúdo (listas que crescem, ajustes).
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
        }
        refreshContent()
        poller.popoverOpened()
        // App de barra não é ativo: sem isso os campos de texto não recebem teclado.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // O .transient sozinho não fecha quando o clique cai em outro app; um monitor global pega esse clique.
        // Fechar o popover NÃO cancela um "Conectar" em andamento: o usuário vai ao navegador copiar o token.
        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    public func popoverDidClose(_ notification: Notification) { removeOutsideClicks() }

    private func removeOutsideClicks() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }

    // MARK: Modos de terminal (a casca chama)

    public static func selfTest() {
        Log.enabled = false
        SelfTest.run()
    }

    /// Desenha as telas em PNG com dados falsos, sem abrir janela nem usar credenciais.
    public static func runSnapshots(into directory: String) -> Int32 { Snapshots.run(into: directory) }

    /// O app se chamava Radar: traz a pasta de dados antiga antes de qualquer coisa ler as credenciais.
    nonisolated public static func migrateLegacyData() { _ = migrateLegacyFolder(from: AppPaths.real.legacySupport, to: AppPaths.real.support) }

    /// `--check`: confere as credenciais salvas nas APIs reais.
    public static func check() async -> Int32 {
        Log.enabled = false
        return await Check.run()
    }

    /// `--dump jira|slack|github`; nil para outro serviço.
    public static func dump(_ service: String) async -> Int32? {
        Log.enabled = false
        switch service {
        case "jira": return await JiraDump.run()
        case "slack": return await SlackDump.run()
        case "github": return await GitHubDump.run()
        default: return nil
        }
    }
}

/// O que muda no popover e nos ajustes entre o avulso e o NeyHub.
struct PopoverState: Equatable {
    var version: String
    var hosted: Bool
    var updateReady = false

    /// Hospedado fecharia o NeyHub inteiro.
    var showsQuit: Bool { !hosted }
    /// Hospedado o modo (janela/barra) é escolhido no card do NeyHub.
    var showsPresence: Bool { !hosted }
    /// Hospedado quem atualiza é o NeyHub.
    var showsUpdate: Bool { updateReady && !hosted }
}

/// Ponte entre as telas (popover, tela, ajustes) e a casca.
final class Shell: ObservableObject {
    @Published var state: PopoverState
    /// Avulso: o modo atual; nil hospedado.
    @Published var presence: Presence?
    /// Hospedado sem permissão de notificações.
    @Published var notificationsOff = false
    var openPermissions: () -> Void = {}
    var checkPermission: () -> Void = {}
    var onPresence: (Presence) -> Void = { _ in }
    var relaunch: () -> Void = {}

    init(state: PopoverState) { self.state = state }
}
