import NeyKit
import SwiftUI

/// O popover único: o destaque no topo e, embaixo, Slack, Revisões e Jira compactos numa rolagem com altura máxima,
/// e um rodapé só.
/// ⚙︎ troca para os ajustes (com voltar).
struct PopoverView: View {
    /// Passando disso a lista rola.
    nonisolated static let defaultMaxHeight: CGFloat = 500

    @ObservedObject var slack: SlackStore
    @ObservedObject var jira: JiraStore
    @ObservedObject var github: GitHubStore
    @ObservedObject var connector: Connector
    @ObservedObject var prefs: PrefsStore
    @ObservedObject var shell: Shell
    var onSave: (Credentials) -> Void
    var refresh: () -> Void
    var maxHeight: CGFloat
    @ViewState private var showSettings: Bool
    /// Volta para "Tudo" e busca fechada a cada abertura: o AppDelegate recria a raiz do popover.
    @ViewState private var filter: ServiceFilter
    @ViewState private var searchOpen: Bool
    @ViewState private var query: String
    /// Estado inicial só para os snapshots (eles não clicam).
    private let preview: (slackShowAll: Bool, jiraFreeOpen: Bool, jiraExpanded: Set<String>, advancedOpen: Bool)

    init(slack: SlackStore, jira: JiraStore, github: GitHubStore, connector: Connector, prefs: PrefsStore, shell: Shell,
         onSave: @escaping (Credentials) -> Void, refresh: @escaping () -> Void = {},
         showSettings: Bool = false, slackShowAll: Bool = false, jiraFreeOpen: Bool = false,
         jiraExpanded: Set<String> = [], advancedOpen: Bool = false, filter: ServiceFilter = .all, searchQuery: String = "",
         maxHeight: CGFloat = PopoverView.defaultMaxHeight) {
        self.maxHeight = maxHeight
        self.slack = slack; self.jira = jira; self.github = github; self.connector = connector; self.prefs = prefs; self.shell = shell
        self.onSave = onSave; self.refresh = refresh
        preview = (slackShowAll, jiraFreeOpen, jiraExpanded, advancedOpen)
        _showSettings = ViewState(wrappedValue: showSettings)
        _filter = ViewState(wrappedValue: filter)
        _searchOpen = ViewState(wrappedValue: !searchQuery.isEmpty)
        _query = ViewState(wrappedValue: searchQuery)
    }

    var body: some View {
        Group {
            if showSettings {
                VStack(alignment: .leading, spacing: 0) {
                    Button("‹ Voltar") { showSettings = false }.buttonStyle(.link).foregroundStyle(Grafite.text).padding([.top, .horizontal], 16)
                    SettingsView(slack: slack, jira: jira, connector: connector, prefs: prefs, shell: shell, advancedOpen: preview.advancedOpen,
                                 onSave: { onSave($0); showSettings = false })
                }
            } else {
                main
            }
        }
        .frame(width: 360)
        .environment(\.density, prefs.prefs.density)
        .foregroundStyle(Grafite.text)
        .background(Grafite.bg.ignoresSafeArea())
        .tint(Grafite.accent)
        .environment(\.colorScheme, .dark)
    }

    private var main: some View {
        let visible = visibleItems(slack: slack.items, prs: github.items, mine: jira.mine, free: jira.free,
                                   prefs: prefs.prefs, query: query)
        let searching = isSearching(query)
        let counts = pillCounts(visible)
        // Conectado mas falhou sem itens (erro ou aviso) = desconhecido (nil), para o destaque não dizer "em dia".
        let slackIn = heroInput(connected: slack.configured, loaded: slack.loaded,
                                failed: slack.error != nil || slack.notice != nil, items: visible.slack)
        let prsIn = heroInput(connected: !github.needsLogin, loaded: github.loaded,
                              failed: github.error != nil || github.notice != nil, items: visible.prs)
        // Card nunca é destaque: no Jira não há destaque (nil). Na busca tudo vira lista.
        let hero: HeroState? = if searching { nil } else {
            switch filter {
            case .all: heroState(slack: slackIn, prs: prsIn)
            case .slack: heroState(slack: slackIn, prs: [])
            case .github: heroState(slack: [], prs: prsIn)
            case .jira: nil
            }
        }
        let highlighted: String? = if case .item(let item) = hero { item.id } else { nil }
        let services: [ServiceFilter] = [slack.configured ? .slack : nil, github.needsLogin ? nil : .github,
                                         jira.configured ? .jira : nil].compactMap { $0 }
        // Pronto = conectado, carregado, sem erro e sem aviso. Na busca, só a seção pronta e sem resultado some: as outras
        // seguem mostrando o carregando, o erro ou o conectar.
        let ready: Set<ServiceFilter> = Set([
            slack.configured && slack.loaded && slack.error == nil && slack.notice == nil ? .slack : nil,
            !github.needsLogin && github.loaded && github.error == nil && github.notice == nil ? .github : nil,
            jira.configured && jira.loaded && jira.error == nil && jira.notice == nil ? .jira : nil,
        ].compactMap { $0 })
        let shows = { (f: ServiceFilter, found: Bool) in
            (filter == .all || filter == f) && (!searching || found || !ready.contains(f))
        }
        // Jira carregado sem nenhum card na aba Jira: o aviso no lugar da área vazia (a seção some sozinha).
        let jiraEmpty = filter == .jira && !searching && jira.configured
            && !showsSection(connected: true, loaded: jira.loaded, failed: jira.error != nil || jira.notice != nil,
                             rows: visible.mine.count + visible.free.count + (jira.sprintIsEmpty ? 1 : 0))
        let emptyNote: String? = showsNoResults(filter: filter, query: query, counts: counts, ready: ready)
            ? "Nada com “\(query)”." : jiraEmpty ? clearTitle(.jira) : nil
        return VStack(alignment: .leading, spacing: 0) {
            FilterBar(filter: $filter, counts: counts, services: services, searchOpen: $searchOpen, query: $query)
            ScrollView {
                if let emptyNote {
                    Note(emptyNote).padding(16)
                } else {
                    VStack(alignment: .leading, spacing: prefs.prefs.density == .compact ? 10 : 16) {
                        if let hero { HighlightView(state: hero, filter: filter, slack: slack, github: github) }
                        Group {
                            if shows(.slack, !visible.slack.isEmpty) {
                                SlackView(store: slack, connector: connector, items: visible.slack, highlightedId: highlighted,
                                          query: query, openSettings: { showSettings = true }, showAll: preview.slackShowAll)
                            }
                            if shows(.github, !visible.prs.isEmpty) {
                                GitHubView(store: github, items: visible.prs, highlightedId: highlighted, query: query)
                            }
                            if shows(.jira, !visible.mine.isEmpty || !visible.free.isEmpty) {
                                // No filtro Jira os livres já vêm abertos; o id recria a seção ao entrar e sair dele.
                                JiraView(store: jira, connector: connector, mine: visible.mine, free: visible.free, query: query,
                                         openSettings: { showSettings = true },
                                         freeOpen: filter == .jira || preview.jiraFreeOpen, expanded: preview.jiraExpanded)
                                    .id(filter == .jira)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    // Sem destaque (carregando, no Jira ou na busca) a primeira seção ainda precisa da margem de cima.
                    .padding(.top, hero == nil || hero == .loading ? 12 : 0).padding(.bottom, 12)
                }
            }
            .motion(filter)
            .frame(maxHeight: maxHeight)
            FooterBar(updatedAt: lastUpdate, results: searching ? counts[filter] ?? 0 : nil, refresh: refresh,
                      settings: { showSettings = true })
                .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    /// A atualização mais recente entre os três.
    private var lastUpdate: Date? { [slack.updatedAt, jira.updatedAt, github.updatedAt].compactMap { $0 }.max() }
}
