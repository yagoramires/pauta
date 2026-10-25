import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private(set) var item: NSStatusItem!
    private let popover = NSPopover()
    private var credentials = Credentials.load()
    /// Muda a cada abertura do popover para o SwiftUI recriar a raiz (filtro e busca zerados, ajustes relidos do disco).
    private var generation = 0
    /// Escuta cliques nos outros apps enquanto o popover está aberto.
    private var outsideClicks: Any?
    private let jiraStore = JiraStore(client: nil)
    private let prefsStore = PrefsStore()
    /// O SlackStore grava o registro de "já avisado" antes de chamar `notify`, então filtrar aqui não trava o registro.
    private lazy var slackStore = SlackStore(client: nil, notify: { [prefsStore] in
        Notifier.postIfSlackClosed(notifiable($0, prefs: prefsStore.prefs))
    })
    private let githubStore = GitHubStore()
    private lazy var poller = Poller(jira: jiraStore, slack: slackStore, github: githubStore,
                                     interval: TimeInterval(prefsStore.prefs.refreshMinutes * 60))
    /// Os fluxos "Conectar" moram aqui (e não na tela): continuam com o popover fechado, enquanto o usuário copia o token no navegador.
    private lazy var connector = Connector(save: { [weak self] in self?.save($0) })
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        // A janelinha acompanha o tamanho do conteúdo (listas que crescem, ajustes).
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
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
        updateBar()
        jiraStore.reconfigure(credentials)
        slackStore.reconfigure(credentials)
        Notifier.onOpen = { [weak self] channel, ts, link in MainActor.assumeIsolated { self?.slackStore.openLink(channel: channel, ts: ts, permalink: link) } }
        Notifier.start()
        poller.start()
        // Para funcionar "sozinho": na primeira vez já entra nos itens de início.
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            do { try SMAppService.mainApp.register() } catch { debugLog("abrir ao iniciar falhou: \(error)") }
        }
        debugLog("iniciou · jira \(credentials.jiraReady ? "configurado" : "sem credenciais") · slack \(credentials.slackReady ? "configurado" : "sem credenciais")")
    }

    func applicationWillTerminate(_ notification: Notification) { connector.cancelAll() }

    private func updateBar(prefs: Prefs? = nil) {
        // Erro de qualquer serviço conectado vira o triângulo; "gh não logado" não é erro, a seção explica.
        let failed = jiraStore.error != nil || slackStore.error != nil || githubStore.error != nil
        let (slack, jira, github) = barCounts(slack: slackStore.items, mine: jiraStore.mine.count, freeCount: jiraStore.freeCount,
                                              prs: githubStore.count, prefs: prefs ?? prefsStore.prefs)
        let text = barDescription(slack: slack, jira: jira, github: github, failed: failed)
        item.button?.image = barImage(barState(slack: slack, jira: jira, github: github, failed: failed), description: text)
        item.button?.toolTip = text
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
            PopoverView(slack: slackStore, jira: jiraStore, github: githubStore, connector: connector, prefs: prefsStore,
                        onSave: { [weak self] in self?.save($0) },
                        refresh: { [weak self] in self?.poller.refreshNow() })
                .id(generation))
    }

    @objc private func toggle() {
        if popover.isShown { return popover.performClose(nil) }
        guard let button = item.button else { return }
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

    func popoverDidClose(_ notification: Notification) {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }
}
