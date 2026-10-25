import SwiftUI

/// Seção "Seus cards": os cards do usuário na sprint e, recolhidos, os livres do projeto. Sem token, só o "Conectar Jira".
/// Conectada, carregada, sem erro e sem cards, a seção some (menos com a sprint vazia: o aviso fica).
struct JiraView: View {
    @ObservedObject var store: JiraStore
    @ObservedObject var connector: Connector
    /// Seus cards e os livres visíveis (livres desligados = []; já com a busca aplicada).
    var mine: [JiraIssue]
    var free: [JiraIssue]
    /// Durante a busca os livres saem para uma seção "Livres" própria, aberta.
    var query: String
    var openSettings: () -> Void
    @ViewState private var freeOpen: Bool
    /// Grupos de sub-tarefas abertos; os snapshots começam com algum aberto (o ImageRenderer não clica).
    @ViewState private var expanded: Set<String>
    /// Na busca os grupos vêm abertos; os que o usuário fechar durante ela ficam aqui.
    @ViewState private var collapsedInSearch: Set<String> = []

    init(store: JiraStore, connector: Connector, mine: [JiraIssue], free: [JiraIssue], query: String = "",
         openSettings: @escaping () -> Void = {}, freeOpen: Bool = false, expanded: Set<String> = []) {
        self.store = store
        self.connector = connector
        self.mine = mine
        self.free = free
        self.query = query
        self.openSettings = openSettings
        _freeOpen = ViewState(wrappedValue: freeOpen)
        _expanded = ViewState(wrappedValue: expanded)
    }

    var body: some View {
        // Group (e não VStack): seção escondida não ocupa o espaçamento da pilha do popover.
        Group {
            if !store.configured {
                VStack(alignment: .leading, spacing: 4) {
                    ServiceTitle(.jira)
                    if let who = connector.jira.connectedAs { ConnectedNote(name: who) }
                    ConnectCard(service: .jira, connector: connector)
                }
            } else {
                // Na busca os livres saem para a seção própria, então "Seus cards" conta só os seus; o aviso, o erro e o
                // carregando aparecem como fora dela.
                let searching = isSearching(query)
                if showsSection(connected: true, loaded: store.loaded, failed: store.error != nil || store.notice != nil,
                                rows: mine.count + (searching ? 0 : free.count) + (store.sprintIsEmpty ? 1 : 0)) {
                    main
                }
                if searching && !free.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle("Livres") { Text("\(free.count)") }
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(groupFree(free)) { group in groupView(group) }
                        }
                    }
                }
            }
        }
        .motion(connector.jira.connectedAs)
        // Cada busca nova começa com os grupos abertos.
        .onChange(of: isSearching(query)) { _, now in if now { collapsedInSearch = [] } }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Seus cards") {
                Text(sprintInfo)
            }
            if let who = connector.jira.connectedAs { ConnectedNote(name: who) }
            banner
            content
        }
    }

    private var sprintInfo: String {
        guard let sprint = store.sprint else { return store.project }
        guard let end = sprint.endDate else { return sprint.name }
        return "\(sprint.name), \(sprintDaysText(daysLeft(until: end, now: Date(), calendar: .current)))"
    }

    @ViewBuilder private var banner: some View {
        if store.error != nil || store.notice != nil {
            Banner {
                if store.error == .unauthorized && store.notice == nil {
                    Text("Token do Jira inválido.")
                    Button("Ajustes", action: openSettings).buttonStyle(.link).foregroundStyle(.secondary)
                } else {
                    // O corpo de um erro de servidor pode ser longo: a faixa mostra o começo (o log guarda tudo).
                    Text(String((store.notice ?? store.error?.userMessage ?? "").prefix(120)))
                    if let key = store.errorKey { Button("Abrir \(key)") { store.open(key) }.buttonStyle(.link).foregroundStyle(.secondary) }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !store.loaded {
            if store.error == nil { Note("Carregando…") }
        } else if store.sprintIsEmpty {
            Note("Nenhuma sprint ativa em \(store.project)")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(mine) { issue in
                    CompactRow(service: .jira, text: issue.summary, query: query, trailingIsControl: true,
                               action: { store.open(issue.key) }) {
                        // Mudou de status: as transições possíveis são outras, então recomeça do zero.
                        StatusMenu(store: store, issue: issue).id(issue.status)
                    }
                }
                if !free.isEmpty && !isSearching(query) { freeSection }
            }
        }
    }

    // MARK: Livres

    private var freeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(freeCardsText(free.count) + (freeOpen ? " ▾" : " ▸")) { freeOpen.toggle() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.top, 4)
            if freeOpen {
                ForEach(groupFree(free)) { group in groupView(group) }
            }
        }
    }

    private func groupView(_ group: FreeGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let head = group.headIssue {
                freeRow(head)
            } else {
                CompactRow(service: .jira, text: group.head.summary, query: query, dim: true, action: { store.open(group.head.key) }) { EmptyView() }
            }
            if !group.subtasks.isEmpty {
                DisclosureGroup(isExpanded: binding(group.id)) {
                    ForEach(group.subtasks) { sub in freeRow(sub) }
                } label: {
                    Text(group.subtasks.count == 1 ? "1 sub-tarefa" : "\(group.subtasks.count) sub-tarefas")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.leading, 26)
            }
        }
    }

    private func freeRow(_ issue: JiraIssue) -> some View {
        CompactRow(service: .jira, text: issue.summary, query: query, trailingIsControl: true, action: { store.open(issue.key) }) {
            pegar(issue.key)
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        // Na busca as sub-tarefas achadas já vêm à mostra, mas o grupo ainda fecha.
        if isSearching(query) {
            return Binding(get: { !collapsedInSearch.contains(id) },
                           set: { if $0 { collapsedInSearch.remove(id) } else { collapsedInSearch.insert(id) } })
        }
        return Binding(get: { expanded.contains(id) },
                       set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })
    }

    private func pegar(_ key: String) -> some View {
        Button("Pegar") { Task { await store.pick(key) } }
            .buttonStyle(GraphiteButtonStyle(primary: false))
            .disabled(store.busy.contains(key))
    }
}

/// Pílula de status com menu de transições. As opções carregam ao passar o mouse na linha (antes de abrir o menu).
private struct StatusMenu: View {
    @ObservedObject var store: JiraStore
    let issue: JiraIssue
    @ViewState private var options: [Transition]?
    /// A última tentativa falhou; `options` continua nil para o próximo hover ou abertura tentar de novo.
    @ViewState private var failed = false

    var body: some View {
        Menu {
            if let options {
                ForEach(options) { option in
                    Button(option.name) { Task { await store.transition(issue.key, to: option) } }
                }
            } else if failed {
                Button("Não deu pra carregar") {}.disabled(true).task { await load() }
            } else {
                // Se o menu abrir antes do carregamento terminar, carrega aqui mesmo.
                Text("Carregando…").task { await load() }
            }
        } label: {
            HStack(spacing: 3) {
                Text(issue.status).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(store.busy.contains(issue.key))
        .onHover { if $0 { Task { await load() } } }
    }

    private func load() async {
        guard options == nil else { return }
        options = await store.transitions(for: issue.key)
        failed = options == nil
    }
}
