import NeyKit
import SwiftUI

/// Tela de app (janela do NeyHub, ou do avulso no modo Janela), como no mockup aprovado: filtros e busca no topo, o
/// destaque, e Slack, GitHub e Jira lado a lado (empilhados numa janela estreita). Mesmos stores e ações do popover, com o
/// que não cabe nele: a mensagem inteira, checks e autor dos PRs, "Seus PRs" e os cards em linhas com o status.
struct ScreenView: View {
    /// Abaixo disso as colunas empilham.
    nonisolated static let wideWidth: CGFloat = 760

    @ObservedObject var slack: SlackStore
    @ObservedObject var jira: JiraStore
    @ObservedObject var github: GitHubStore
    @ObservedObject var connector: Connector
    @ObservedObject var prefs: PrefsStore
    @ObservedObject var shell: Shell
    var onSave: (Credentials) -> Void
    var refresh: () -> Void
    @ViewState private var filter: ServiceFilter
    @ViewState private var query: String
    @ViewState private var showSettings: Bool
    @ViewState private var freeOpen: Bool

    /// `filter`, `query`, `showSettings` e `freeOpen` só para os snapshots (eles não clicam).
    init(slack: SlackStore, jira: JiraStore, github: GitHubStore, connector: Connector, prefs: PrefsStore, shell: Shell,
         onSave: @escaping (Credentials) -> Void, refresh: @escaping () -> Void = {},
         filter: ServiceFilter = .all, query: String = "", showSettings: Bool = false, freeOpen: Bool = false) {
        self.slack = slack; self.jira = jira; self.github = github; self.connector = connector; self.prefs = prefs; self.shell = shell
        self.onSave = onSave; self.refresh = refresh
        _filter = ViewState(wrappedValue: filter)
        _query = ViewState(wrappedValue: query)
        _showSettings = ViewState(wrappedValue: showSettings)
        _freeOpen = ViewState(wrappedValue: freeOpen)
    }

    var body: some View {
        Group {
            if showSettings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Button("‹ Voltar") { showSettings = false }.buttonStyle(.link).foregroundStyle(Grafite.text)
                            .padding([.top, .horizontal], 16)
                        SettingsView(slack: slack, jira: jira, connector: connector, prefs: prefs, shell: shell, onSave: onSave)
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                }
            } else {
                GeometryReader { geometry in main(width: geometry.size.width) }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .environment(\.density, prefs.prefs.density)
        .foregroundStyle(Grafite.text)
        .background(Grafite.bg.ignoresSafeArea())
        .tint(Grafite.accent)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Montagem

    private func main(width: CGFloat) -> some View {
        let wide = width >= Self.wideWidth
        let visible = visibleItems(slack: slack.items, prs: github.items, mine: jira.mine, free: jira.free,
                                   prefs: prefs.prefs, query: query)
        let searching = isSearching(query)
        let counts = pillCounts(visible)
        // Mesma regra do popover: conectado mas falhou sem itens = desconhecido (nil), para o destaque não dizer "em dia".
        let slackIn = heroInput(connected: slack.configured, loaded: slack.loaded,
                                failed: slack.error != nil || slack.notice != nil, items: visible.slack)
        let prsIn = heroInput(connected: !github.needsLogin, loaded: github.loaded,
                              failed: github.error != nil || github.notice != nil, items: visible.prs)
        let hero: HeroState? = if searching { nil } else {
            switch filter {
            case .all: heroState(slack: slackIn, prs: prsIn)
            case .slack: heroState(slack: slackIn, prs: [])
            case .github: heroState(slack: [], prs: prsIn)
            case .jira: nil
            }
        }
        let highlighted: String? = if case .item(let item) = hero { item.id } else { nil }
        let columns: [ServiceFilter] = filter == .all ? [.slack, .github, .jira] : [filter]
        let services: [ServiceFilter] = [slack.configured ? .slack : nil, github.needsLogin ? nil : .github,
                                         jira.configured ? .jira : nil].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 12) {
            top(counts: counts, services: services)
            if let hero, hero != .loading { heroCard(hero) }
            if wide {
                HStack(alignment: .top, spacing: 12) {
                    // Slack e GitHub 1, Jira 1,15 (o status ocupa a direita), como no mockup.
                    let unit = (width - 40 - 12 * CGFloat(columns.count - 1)) / (CGFloat(columns.count) + (columns.contains(.jira) ? 0.15 : 0))
                    ForEach(columns, id: \.self) { column in
                        card(scrolls: true) { content(column, visible: visible, highlighted: highlighted) }
                            .frame(width: max(unit * (column == .jira ? 1.15 : 1), 0))
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(columns, id: \.self) { column in
                            card(scrolls: false) { content(column, visible: visible, highlighted: highlighted) }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            footer(results: searching ? counts[filter] ?? 0 : nil)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }

    @ViewBuilder private func content(_ column: ServiceFilter, visible: VisibleItems, highlighted: String?) -> some View {
        switch column {
        case .slack: slackColumn(visible.slack.filter { $0.id != highlighted })
        case .github: githubColumn(visible.prs.filter { $0.id != highlighted },
                                   mine: github.mine.filter { matches(query, searchFields($0)) })
        default: jiraColumn(mine: visible.mine, free: visible.free)
        }
    }

    private func card<Content: View>(scrolls: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        let inner = VStack(alignment: .leading, spacing: 0) { content() }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if scrolls { ScrollView { inner } } else { inner }
        }
        .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil, alignment: .topLeading)
        .background(Grafite.card, in: RoundedRectangle(cornerRadius: Grafite.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Grafite.cardRadius).stroke(Grafite.cardBorder, lineWidth: 1))
    }

    // MARK: Topo

    private func top(counts: [ServiceFilter: Int], services: [ServiceFilter]) -> some View {
        HStack(spacing: 8) {
            chip(.all, count: counts[.all] ?? 0)
            ForEach(services, id: \.self) { chip($0, count: counts[$0] ?? 0) }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Grafite.label)
                TextField("Buscar em tudo…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Grafite.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Limpar")
                }
            }
            .padding(.horizontal, 10).frame(minWidth: 120, maxWidth: 220).frame(height: 28)
            .background(Grafite.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Grafite.cardBorder, lineWidth: 1))
        }
    }

    private func chip(_ option: ServiceFilter, count: Int) -> some View {
        let selected = filter == option
        let service: HubService? = switch option {
        case .all: nil
        case .slack: .slack
        case .github: .github
        case .jira: .jira
        }
        return Button { filter = option } label: {
            HStack(spacing: 5) {
                if let service { ServiceLogo(service: service, size: 12, color: selected ? Grafite.onAccent : nil) }
                Text(service?.name ?? "Tudo")
                Text("\(count)").fontWeight(.semibold).monospacedDigit()
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Grafite.onAccent : Grafite.muted)
            .padding(.horizontal, 11).frame(height: 26)
            .background(Capsule().fill(selected ? Grafite.text : Grafite.card))
            .overlay(Capsule().stroke(selected ? .clear : Grafite.cardBorder, lineWidth: 1))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(service?.name ?? "Tudo"), \(count)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Destaque

    @ViewBuilder private func heroCard(_ state: HeroState) -> some View {
        HStack(alignment: .center, spacing: 16) {
            switch state {
            case .item(.slack(let item)):
                heroText(.slack, context: highlightContext(item), text: "“\(item.text)”")
                Button("Abrir no Slack") { slack.open(item) }.buttonStyle(GraphiteButtonStyle())
                Button("Marcar como visto") { slack.dismiss(item) }.buttonStyle(GraphiteButtonStyle(primary: false))
            case .item(.pr(let pr)):
                heroText(.github, context: highlightContext(pr) + " · " + prPlace(pr), text: pr.title)
                Button("Abrir no GitHub") { github.open(pr) }.buttonStyle(GraphiteButtonStyle())
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text(clearTitle(filter)).font(.system(size: 17, weight: .semibold)).foregroundStyle(Grafite.strong)
                    if filter == .all, let subtitle = clearSubtitle(slackConnected: slack.configured, githubConnected: !github.needsLogin) {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Grafite.muted)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(LinearGradient(colors: [Grafite.awakeBg, Grafite.card], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Grafite.awakeBorder, lineWidth: 1))
    }

    private func heroText(_ service: HubService, context: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ServiceLogo(service: service, size: 12)
                Text(context).lineLimit(1)
            }
            .font(.system(size: 11.5)).foregroundStyle(Grafite.muted)
            Text(text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Grafite.strong).lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Slack

    @ViewBuilder private func slackColumn(_ rows: [SlackItem]) -> some View {
        if !slack.configured {
            label(.slack, "Slack")
            if let who = connector.slack.connectedAs { ConnectedNote(name: who) }
            ConnectCard(service: .slack, connector: connector)
        } else {
            label(.slack, "Slack") {
                if !rows.isEmpty { Button("Marcar tudo como visto") { slack.markSeen(rows) }.buttonStyle(.link).foregroundStyle(Grafite.muted) }
            }
            problem(slack.error, slack.notice, invalid: "Token do Slack inválido.")
            if !slack.loaded {
                if slack.error == nil { Note("Carregando…") }
            } else if rows.isEmpty {
                Note(clearTitle(.slack))
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                row(.slack, first: index == 0, dim: isOld(item.ts.date), time: item.ts.date, action: { slack.open(item) }) {
                    HStack(spacing: 6) {
                        Text(item.userName).fontWeight(.semibold).foregroundStyle(Grafite.strong)
                        if !item.isDM { tag(slackPlace(item)) }
                    }
                    // A mensagem inteira, sem cortar: é o que o popover não mostra.
                    Text(marked(item.text)).foregroundStyle(Grafite.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: GitHub

    @ViewBuilder private func githubColumn(_ rows: [PullRequest], mine: [PullRequest]) -> some View {
        label(.github, "GitHub · Revisões") {
            if !rows.isEmpty { Text(rows.count == 1 ? "1 esperando você" : "\(rows.count) esperando você") }
        }
        problem(github.error, github.notice, invalid: "Token do gh inválido. Rode gh auth login.")
        if github.needsLogin {
            Note("Entre no GitHub pelo terminal:")
            Text("gh auth login").font(.system(size: 12)).textSelection(.enabled)
        } else if !github.loaded {
            if github.error == nil { Note("Carregando…") }
        } else {
            if rows.isEmpty { Note(clearTitle(.github)) }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, pr in
                row(.github, first: index == 0, dim: isOld(pr.updatedAt), time: pr.updatedAt, action: { github.open(pr) }) {
                    prTitle(pr)
                    // Um Text só (concatenado): quebra como uma frase, não em blocos lado a lado.
                    (Text(prPlace(pr) + " · " + pr.author) + (checksText(pr.checks).map { Text(" · ") + toned($0) } ?? Text("")))
                        .foregroundStyle(Grafite.muted)
                }
            }
            label(nil, "Seus PRs") {
                if !mine.isEmpty { Text(mine.count == 1 ? "1 aberto" : "\(mine.count) abertos") }
            }
            .padding(.top, 14)
            if mine.isEmpty { Note("Nenhum PR seu aberto.") }
            ForEach(Array(mine.enumerated()), id: \.element.id) { index, pr in
                row(.github, first: index == 0, dim: false, time: nil, action: { github.open(pr) }) {
                    prTitle(pr)
                    (Text(prPlace(pr) + " · " + approvalsText(pr.approvals ?? 0) + " · ") + toned(prStatusText(pr)))
                        .foregroundStyle(Grafite.muted)
                }
            }
        }
    }

    private func prTitle(_ pr: PullRequest) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marked(pr.title)).fontWeight(.semibold).foregroundStyle(Grafite.strong).fixedSize(horizontal: false, vertical: true)
            if pr.draft { tag("rascunho") }
        }
    }

    // MARK: Jira

    @ViewBuilder private func jiraColumn(mine: [JiraIssue], free: [JiraIssue]) -> some View {
        if !jira.configured {
            label(.jira, "Jira")
            if let who = connector.jira.connectedAs { ConnectedNote(name: who) }
            ConnectCard(service: .jira, connector: connector)
        } else {
            label(.jira, "Seus cards") { Text(sprintInfo) }
            problem(jira.error, jira.notice, invalid: "Token do Jira inválido.")
            if let key = jira.errorKey { Button("Abrir \(key)") { jira.open(key) }.buttonStyle(.link).foregroundStyle(Grafite.muted) }
            if !jira.loaded {
                if jira.error == nil { Note("Carregando…") }
            } else if jira.sprintIsEmpty {
                Note("Nenhuma sprint ativa em \(jira.project)")
            } else {
                if mine.isEmpty { Note(clearTitle(.jira)) }
                // Uma linha por card, com o status que muda pelo menu, como no popover (o Yago não quis colunas de kanban).
                ForEach(Array(mine.enumerated()), id: \.element.id) { index, issue in
                    row(.jira, first: index == 0, dim: false, time: nil, action: { jira.open(issue.key) }, trailing: {
                        StatusMenu(store: jira, issue: issue).id(issue.status)
                    }) {
                        Text(marked(issue.summary)).fontWeight(.semibold).foregroundStyle(Grafite.strong).fixedSize(horizontal: false, vertical: true)
                        Text(issue.key).foregroundStyle(Grafite.muted)
                    }
                }
                if !free.isEmpty {
                    let open = freeOpen || isSearching(query)
                    Button(freeCardsText(free.count) + (open ? " ▾" : " ▸")) { freeOpen.toggle() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Grafite.label).padding(.top, 8)
                    if open { freeList(free) }
                }
            }
        }
    }

    /// Livres agrupados como no popover: pai livre com "Pegar"; pai que não é livre, apagado; sub-tarefas recuadas.
    private func freeList(_ free: [JiraIssue]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groupFree(free)) { group in
                freeRow(group.head.summary, key: group.head.key, pick: group.headIssue != nil, indent: false)
                    .opacity(group.headIssue == nil ? 0.5 : 1)
                ForEach(group.subtasks) { sub in freeRow(sub.summary, key: sub.key, pick: true, indent: true) }
            }
        }
    }

    private func freeRow(_ summary: String, key: String, pick: Bool, indent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { jira.open(key) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(marked(summary)).foregroundStyle(Grafite.text).fixedSize(horizontal: false, vertical: true)
                    Text(key).font(.system(size: 10.5)).foregroundStyle(Grafite.label)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if pick {
                Button("Pegar") { Task { await jira.pick(key) } }
                    .buttonStyle(GraphiteButtonStyle(primary: false)).disabled(jira.busy.contains(key))
            }
        }
        .font(.system(size: 12))
        .padding(.vertical, 5).padding(.leading, indent ? 16 : 0)
    }

    private var sprintInfo: String {
        guard let sprint = jira.sprint else { return jira.project }
        guard let end = sprint.endDate else { return sprint.name }
        return "\(sprint.name) · \(sprintDaysText(daysLeft(until: end, now: Date(), calendar: .current)))"
    }

    // MARK: Peças

    private func label<Trailing: View>(_ service: HubService?, _ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack(spacing: 6) {
            if let service { ServiceLogo(service: service, size: 13) }
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Grafite.strong)
            Spacer(minLength: 8)
            trailing().font(.system(size: 11)).foregroundStyle(Grafite.muted)
        }
        .padding(.bottom, 8)
    }

    /// Linha da coluna: logo, o conteúdo em duas linhas, a hora (ou um controle) à direita e o fio entre linhas.
    private func row<Lines: View, Trailing: View>(_ service: HubService, first: Bool, dim: Bool, time: Date?, action: @escaping () -> Void,
                                                  @ViewBuilder trailing: () -> Trailing = { EmptyView() },
                                                  @ViewBuilder lines: () -> Lines) -> some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Grafite.cardBorder).frame(height: 1) }
            HStack(alignment: .top, spacing: 8) {
                Button(action: action) {
                    HStack(alignment: .top, spacing: 8) {
                        ServiceLogo(service: service, size: 13).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) { lines() }
                            .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        if let time { Text(relativeTime(time, now: Date())).font(.system(size: 10.5)).foregroundStyle(Grafite.label).fixedSize() }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                trailing()
            }
            .padding(.vertical, 8)
        }
        .opacity(dim ? 0.45 : 1)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5)).foregroundStyle(Grafite.muted)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Grafite.selected, in: RoundedRectangle(cornerRadius: 5))
    }

    private func toned(_ value: (text: String, ok: Bool?)) -> Text {
        Text(value.text).foregroundColor(value.ok.map { $0 ? Self.ok : Self.bad } ?? Grafite.muted)
    }

    /// Verde e vermelho dos checks (os do mockup, de fora do Grafite).
    private static let ok = Grafite.color(hex: "#3fb950") ?? .green
    private static let bad = Grafite.color(hex: "#f85149") ?? .red

    @ViewBuilder private func problem(_ error: APIError?, _ notice: String?, invalid: String) -> some View {
        if error != nil || notice != nil {
            Banner {
                if error == .unauthorized && notice == nil {
                    Text(invalid)
                    Button("Ajustes") { showSettings = true }.buttonStyle(.link).foregroundStyle(Grafite.muted)
                } else {
                    Text(String((notice ?? error?.userMessage ?? "").prefix(160)))
                }
            }
            .padding(.bottom, 6)
        }
    }

    /// Trechos achados pela busca com o fundo de destaque.
    private func marked(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for range in matchRanges(text, query: query) {
            if let r = Range(range, in: result) { result[r].backgroundColor = Grafite.accent.opacity(0.25) }
        }
        return result
    }

    private func footer(results: Int?) -> some View {
        HStack(spacing: 8) {
            Text(results.map(resultsText) ?? agoText([slack.updatedAt, jira.updatedAt, github.updatedAt].compactMap { $0 }.max()))
            Button(action: refresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Atualizar")
                .accessibilityLabel("Atualizar")
            Button { showSettings = true } label: { Label("Configurações", systemImage: "gearshape") }.buttonStyle(.plain)
            Spacer(minLength: 0)
            if shell.notificationsOff { PermissionNote(openPermissions: shell.openPermissions) }
        }
        .font(.system(size: 11)).foregroundStyle(Grafite.label)
    }
}
