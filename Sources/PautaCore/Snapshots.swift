import NeyKit
import SwiftUI

/// `Pauta --snapshots <pasta>`: renderiza as telas em PNG (2x) com dados de mentira, sem rede nem credenciais reais.
@MainActor
enum Snapshots {
    static func run(into directory: String) -> Int32 {
        Log.enabled = false
        // SettingsView lê as credenciais ao abrir: aponta para um arquivo que não existe, nunca o de verdade.
        Credentials.url = FileManager.default.temporaryDirectory.appendingPathComponent("pauta-snap-\(UUID().uuidString)/none.json")
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var ok = true
        func render<V: View>(_ name: String, _ view: V, appearance: NSAppearance.Name? = nil) {
            // NSHostingView (e não ImageRenderer): só ele desenha os controles nativos (Menu, botões, campos).
            // Sempre escuro: o tema Grafite não tem versão clara (o `appearance` antigo ficou só nos nomes dos arquivos).
            let host = NSHostingView(rootView: view.background(Grafite.bg.ignoresSafeArea()))
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.frame.width * 2),
                                             pixelsHigh: Int(host.frame.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0)
            else { print("falhou: \(name)"); ok = false; return }
            rep.size = host.frame.size
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]),
                  (try? png.write(to: dir.appendingPathComponent(name))) != nil
            else { print("falhou: \(name)"); ok = false; return }
            print(dir.appendingPathComponent(name).path)
        }

        // Nada daqui toca a rede, a área de transferência, o gh ou as notificações: o Connector nunca chega a iniciar um fluxo.
        let connector = Connector(save: { _ in }, open: { _ in })
        // Suíte própria de nome fixo, limpa antes e no fim: o snapshot nunca lê nem grava as preferências reais e não deixa
        // um plist novo a cada rodada. Cada PrefsStore lê a suíte só ao nascer, então o "compacto" não muda o padrão.
        let suite = "pauta-snapshots"
        let snapshotDefaults = UserDefaults(suiteName: suite)!
        snapshotDefaults.removePersistentDomain(forName: suite)
        defer { snapshotDefaults.removePersistentDomain(forName: suite) }
        func tempPrefs() -> PrefsStore { PrefsStore(defaults: snapshotDefaults) }
        let defaultPrefs = tempPrefs()
        // Avulso (com uma atualização pronta, para mostrar a linha) e hospedado no NeyHub.
        let shell = Shell(state: PopoverState(version: "0.2.0", hosted: false, updateReady: true))
        shell.presence = Presence(screen: false, menuBar: true)
        let hostedShell = Shell(state: PopoverState(version: "0.2.0", hosted: true, updateReady: true))
        func popover(slack: SlackStore, jira: JiraStore, github: GitHubStore, prefs: PrefsStore? = nil, showSettings: Bool = false, slackShowAll: Bool = false,
                     jiraFreeOpen: Bool = false, advancedOpen: Bool = false, filter: ServiceFilter = .all, search: String = "",
                     maxHeight: CGFloat = PopoverView.defaultMaxHeight, shell custom: Shell? = nil) -> PopoverView {
            PopoverView(slack: slack, jira: jira, github: github, connector: connector, prefs: prefs ?? defaultPrefs, shell: custom ?? shell, onSave: { _ in },
                        showSettings: showSettings, slackShowAll: slackShowAll, jiraFreeOpen: jiraFreeOpen,
                        jiraExpanded: ["ACME-1330"], advancedOpen: advancedOpen, filter: filter,
                        searchQuery: search, maxHeight: maxHeight)
        }

        let slack = fakeSlackStore()
        slack.items = fakeSlackItems()
        let jira = fakeStore()
        let github = fakeGitHubStore()
        render("tela-tudo.png", popover(slack: slack, jira: jira, github: github))
        render("tela-tudo-escuro.png", popover(slack: slack, jira: jira, github: github, maxHeight: 4000), appearance: .darkAqua)
        render("tela-filtro-slack.png", popover(slack: slack, jira: jira, github: github, filter: .slack, maxHeight: 4000))
        render("tela-filtro-revisoes.png", popover(slack: slack, jira: jira, github: github, filter: .github, maxHeight: 4000))
        render("tela-filtro-jira.png", popover(slack: slack, jira: jira, github: github, filter: .jira, maxHeight: 4000))
        // Busca aberta: "checkout" acha uma mensagem, um card seu e um livre; "zzz" não acha nada.
        render("tela-busca.png", popover(slack: slack, jira: jira, github: github, search: "checkout", maxHeight: 4000), appearance: .aqua)
        render("tela-busca-escuro.png", popover(slack: slack, jira: jira, github: github, search: "checkout", maxHeight: 4000), appearance: .darkAqua)
        render("tela-busca-vazia.png", popover(slack: slack, jira: jira, github: github, search: "zzz", maxHeight: 4000), appearance: .aqua)
        render("tela-busca-vazia-escuro.png", popover(slack: slack, jira: jira, github: github, search: "zzz", maxHeight: 4000), appearance: .darkAqua)
        // Aba Jira com o Jira carregado e sem nenhum card: o aviso no lugar da área vazia.
        let noCards = fakeStore()
        noCards.mine = []; noCards.free = []
        render("tela-filtro-jira-vazio.png", popover(slack: slack, jira: noCards, github: github, filter: .jira))
        render("tela-tudo-livres.png", popover(slack: slack, jira: jira, github: github, jiraFreeOpen: true, maxHeight: 4000))

        // Sem cards seus, só os livres (recolhidos).
        let onlyFree = fakeStore()
        onlyFree.mine = []
        render("tela-so-livres.png", popover(slack: slack, jira: onlyFree, github: github, maxHeight: 4000))

        // Slack e Jira desconectados, GitHub com dados.
        let offSlack = fakeSlackStore(configured: false)
        let offJira = JiraStore(client: nil)  // configured == false
        render("tela-conectar.png", popover(slack: offSlack, jira: offJira, github: github))

        // Slack aguardando a cópia do token; o Jira, com um erro de validação anterior.
        let waiting = Connector(save: { _ in }, open: { _ in })
        waiting.slack = Connector.Flow(waiting: true, error: connectErrorMessage(APIError.unauthorized, service: .slack))
        let waitingView = PopoverView(slack: offSlack, jira: offJira, github: github, connector: waiting, prefs: defaultPrefs, shell: shell, onSave: { _ in })
        render("tela-aguardando.png", waitingView)
        let waitingJira = Connector(save: { _ in }, open: { _ in })
        waitingJira.jira = Connector.Flow(waiting: true)
        render("tela-aguardando-jira.png", PopoverView(slack: slack, jira: offJira, github: github, connector: waitingJira, prefs: defaultPrefs, shell: shell, onSave: { _ in }))

        // Estados de erro e vazios.
        let broken = fakeSlackStore()
        broken.error = .unauthorized
        let brokenJira = fakeStore()
        brokenJira.error = .unauthorized
        let empty = fakeGitHubStore()
        empty.items = []
        let noGh = GitHubStore()
        noGh.needsLogin = true
        render("tela-erro.png", popover(slack: broken, jira: brokenJira, github: noGh))
        // Busca que só acha um livre, com os três em erro/sem login: as faixas e o "gh auth login" ficam, sem "Nada com…".
        render("tela-busca-erro.png", popover(slack: broken, jira: brokenJira, github: noGh, search: "cupom", maxHeight: 4000))
        // Slack sem itens: o destaque é um PR. Slack e GitHub carregados e vazios: "Ninguém esperando você.".
        let noSlackItems = fakeSlackStore()
        render("tela-revisao.png", popover(slack: noSlackItems, jira: jira, github: github, maxHeight: 4000))
        render("tela-em-dia.png", popover(slack: noSlackItems, jira: jira, github: empty, maxHeight: 4000))

        // Jira conectado e carregado, sem nenhum card na sprint.
        let noSprint = fakeStore()
        noSprint.mine = []; noSprint.free = []; noSprint.sprint = nil; noSprint.sprintIsEmpty = true
        render("tela-sem-sprint.png", popover(slack: noSlackItems, jira: noSprint, github: empty, maxHeight: 4000))

        // Tudo conectado e vazio: Jira sem cards seus nem livres (mas com sprint).
        let emptyJira = fakeStore()
        emptyJira.mine = []; emptyJira.free = []
        render("tela-vazia.png", popover(slack: fakeSlackStore(), jira: emptyJira, github: empty))

        // Listas longas: a rolagem para na altura máxima; Slack com "ver mais" aberto.
        let many = fakeSlackStore()
        var longItems: [SlackItem] = []
        for round in 0..<4 {
            longItems += fakeSlackItems(round: round, longFirst: true)
        }
        many.items = longItems
        render("tela-longa.png", popover(slack: many, jira: jira, github: github, slackShowAll: true))

        // Slack recolhido: mais de 4 linhas além do destaque, então "Ver mais N" aparece.
        render("tela-ver-mais.png", popover(slack: many, jira: jira, github: github, maxHeight: 4000))

        render("ajustes.png", popover(slack: slack, jira: offJira, github: github, showSettings: true))
        let compact = tempPrefs()
        compact.prefs.density = .compact
        render("tela-compacta.png", popover(slack: slack, jira: jira, github: github, prefs: compact, maxHeight: 4000))
        render("ajustes-avancado.png", popover(slack: slack, jira: jira, github: github, showSettings: true, advancedOpen: true))
        render("ajustes-neyhub.png", popover(slack: slack, jira: offJira, github: github, showSettings: true, shell: hostedShell))

        // Tela de app (janela do NeyHub ou do avulso no modo Janela), no tamanho do mockup e estreita.
        func screen(slack s: SlackStore? = nil, jira j: JiraStore? = nil, github g: GitHubStore? = nil, shell custom: Shell? = nil,
                    filter: ServiceFilter = .all, query: String = "", settings: Bool = false, freeOpen: Bool = false,
                    size: CGSize = CGSize(width: 1060, height: 640)) -> some View {
            ScreenView(slack: s ?? slack, jira: j ?? jira, github: g ?? github, connector: connector, prefs: defaultPrefs, shell: custom ?? shell,
                       onSave: { _ in }, filter: filter, query: query, showSettings: settings, freeOpen: freeOpen)
                .frame(width: size.width, height: size.height)
        }
        render("tela-app.png", screen())
        render("tela-app-livres.png", screen(freeOpen: true))
        render("tela-app-estreita.png", screen(size: CGSize(width: 560, height: 900)))
        render("tela-app-busca.png", screen(query: "checkout"))
        render("tela-app-jira.png", screen(filter: .jira, freeOpen: true))
        render("tela-app-conectar.png", screen(slack: offSlack, jira: offJira, github: noGh))
        render("tela-app-erro.png", screen(slack: broken, jira: brokenJira, github: github))
        render("tela-app-ajustes.png", screen(settings: true))
        render("tela-app-neyhub-ajustes.png", screen(shell: hostedShell, settings: true))
        // Configurações (janela do avulso pelo ⌘, e card no NeyHub).
        func settings(_ custom: Shell) -> some View {
            SettingsView(slack: slack, jira: jira, connector: connector, prefs: defaultPrefs, shell: custom, onSave: { _ in })
                .frame(width: 420).grafiteWindow()
        }
        render("configuracoes.png", settings(shell))
        render("configuracoes-neyhub.png", settings(hostedShell))

        // Ícone da barra (fundo escuro simulando o tema): todos os estados.
        let bars: [(Int, Int, Int, Bool)] = [(0, 0, 0, false), (3, 2, 1, false), (0, 0, 5, false), (0, 4, 0, false),
                                              (0, 0, 0, true), (12, 0, 2, true)]
        render("barra.png", VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                Image(nsImage: barImage(barState(slack: bar.0, jira: bar.1, github: bar.2, failed: bar.3), description: ""))
                    .renderingMode(.template).foregroundStyle(.primary)
            }
        }.padding(10))
        return ok ? 0 : 1
    }

    private static func fakeGitHubStore() -> GitHubStore {
        let store = GitHubStore(readToken: { nil }, search: { _ in [] })
        func pr(_ repo: String, _ number: Int, _ title: String, _ author: String, _ ago: Double, draft: Bool = false,
                checks: Checks? = nil, approvals: Int? = nil, decision: String? = nil) -> PullRequest {
            PullRequest(repo: repo, number: number, title: title, author: author, updatedAt: Date().addingTimeInterval(-ago),
                        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, draft: draft, checks: checks,
                        approvals: approvals, reviewDecision: decision)
        }
        store.items = [
            pr("acme/web-app", 4821, "feat: tela de resumo do pedido com novo fluxo de pagamento e cupom", "marina-duarte", 1500, checks: .passing),
            pr("acme/design-system", 312, "fix: foco do botão no modo escuro", "rafael-lima", 9000, draft: true, checks: .failing(1)),
            pr("acme/infra", 58, "chore: sobe a versão do node", "ana-souza", 200_000),
        ]
        store.mine = [
            pr("acme/web-app", 4815, "feat: filtro por período", "voce", 3000, checks: .passing, approvals: 2, decision: "APPROVED"),
            pr("acme/web-app", 4790, "refactor: hooks do carrinho", "voce", 90_000, checks: .pending, approvals: 0, decision: "REVIEW_REQUIRED"),
        ]
        store.loaded = true
        store.updatedAt = Date().addingTimeInterval(-60)
        return store
    }

    /// Estado num arquivo temporário: o de verdade nunca é lido nem gravado.
    private static func fakeSlackStore(configured: Bool = true) -> SlackStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pauta-snap-\(UUID().uuidString)/slack-state.json")
        let store = SlackStore(client: nil, stateURL: url, notify: { _ in })
        store.configured = configured
        store.loaded = configured
        store.updatedAt = Date().addingTimeInterval(-60)
        return store
    }

    private static func fakeSlackItems(round: Int = 0, longFirst: Bool = false) -> [SlackItem] {
        let now = Date().timeIntervalSince1970
        func item(_ n: Int, _ ago: Double, _ name: String, _ text: String, dm: Bool = true, channel: String? = nil, thread: Bool = false) -> SlackItem {
            let ts = SlackTS(String(format: "%.6f", now - ago))
            return SlackItem(channel: "C\(n + round * 10)", ts: ts, threadTs: thread ? SlackTS("1.1") : nil, userId: "U\(n)", userName: name,
                             text: text, isDM: dm, channelName: channel, permalink: nil)
        }
        return [
            // longFirst: ~400 caracteres e dois \n; o destaque corta em 4 linhas.
            item(1, 120, "Marina Duarte", longFirst
                 ? "Oi! Conseguiu olhar aquele PR do checkout? Preciso fechar hoje ainda, porque o cliente cobrou duas vezes e a gente prometeu a correção até o fim do dia.\nResumindo o que falta: revisar o fluxo de cupom, conferir o cálculo do frete com o novo CEP e validar o estado de erro do pagamento no mobile.\nSe der, me chama na call das 16h que a gente passa junto, senão eu deixo anotado no PR e sigo com o resto da lista amanhã cedo, tudo bem?"
                 : "Oi! Conseguiu olhar aquele PR do checkout? Preciso fechar hoje ainda"),
            item(2, 1500, "Rafael Lima", "@voce o deploy de homologação quebrou depois do merge, pode dar uma olhada?", dm: false, channel: "frontend"),
            item(3, 9000, "Ana Souza", "Valeu pela ajuda ontem", dm: false, channel: "design-system", thread: true),
            item(4, 200_000, "Carlos Pereira", "Te mandei o link da reunião"),
        ]
    }

    private static func fakeStore() -> JiraStore {
        func issue(_ key: String, _ summary: String, status: String = "To Do", category: StatusCategory = .todo,
                   assignee: String? = nil, parent: ParentRef? = nil, subtask: Bool = false) -> JiraIssue {
            JiraIssue(key: key, summary: summary, status: status, category: category, assigneeId: assignee,
                      parent: parent, isSubtask: subtask)
        }
        let store = JiraStore(client: nil)
        store.configured = true
        store.loaded = true
        store.sprint = Sprint(id: 1, name: "Sprint Lince", endDate: Date().addingTimeInterval(4 * 86400 + 3600))
        store.updatedAt = Date().addingTimeInterval(-60)
        store.mine = [
            issue("ACME-1287", "Botão de voltar some no checkout mobile", status: "Em andamento", category: .inProgress, assignee: "me"),
            issue("ACME-1301", "Traduzir tela de perfil para EN e revisar todos os textos do fluxo de cadastro", status: "Code Review", category: .inProgress, assignee: "me"),
            issue("ACME-1310", "Ajustar tokens de cor no header", assignee: "me"),
        ]
        let epic = ParentRef(key: "ACME-1330", summary: "Ajustes de DS - Sprint Lince")
        let orphan = ParentRef(key: "ACME-1340", summary: "Migração do formulário de endereço")
        store.free = [
            issue("ACME-1320", "Erro 500 no checkout sem cupom"),
            issue("ACME-1330", "Ajustes de DS - Sprint Lince"),
            issue("ACME-1331", "Ajustar espaçamento do header", parent: epic, subtask: true),
            issue("ACME-1332", "Trocar ícones do menu lateral", parent: epic, subtask: true),
            issue("ACME-1341", "Validar CEP no blur", parent: orphan, subtask: true),
            issue("ACME-1322", "Skeleton da listagem de pedidos"),
        ]
        return store
    }
}
