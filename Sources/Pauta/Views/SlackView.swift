import SwiftUI

/// Seção do Slack: não lidas (DMs e menções), sem a que está no destaque. Sem token, só o "Conectar Slack".
/// Conectada, carregada, sem erro e sem linhas, a seção some.
struct SlackView: View {
    @ObservedObject var store: SlackStore
    @ObservedObject var connector: Connector
    /// As mensagens visíveis (já com preferências e busca aplicadas).
    var items: [SlackItem]
    var highlightedId: String?
    /// Durante a busca: trechos marcados e todas as linhas, sem "ver mais".
    var query: String
    var openSettings: () -> Void
    @ViewState private var showAll: Bool

    init(store: SlackStore, connector: Connector, items: [SlackItem], highlightedId: String? = nil, query: String = "",
         openSettings: @escaping () -> Void = {}, showAll: Bool = false) {
        self.store = store
        self.connector = connector
        self.items = items
        self.highlightedId = highlightedId
        self.query = query
        self.openSettings = openSettings
        _showAll = ViewState(wrappedValue: showAll)
    }

    private var rows: [SlackItem] { items.filter { $0.id != highlightedId } }

    var body: some View {
        // Group (e não VStack): seção escondida não ocupa o espaçamento da pilha do popover.
        Group {
            if !store.configured {
                VStack(alignment: .leading, spacing: 4) {
                    ServiceTitle(.slack)
                    if let who = connector.slack.connectedAs { ConnectedNote(name: who) }
                    ConnectCard(service: .slack, connector: connector)
                }
            } else if showsSection(connected: true, loaded: store.loaded, failed: store.error != nil || store.notice != nil,
                                   rows: rows.count) {
                connected
            }
        }
        .motion(connector.slack.connectedAs)
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("Slack") {
                if !rows.isEmpty {
                    Button("Marcar tudo como visto") { store.markSeen(items) }.buttonStyle(.link).foregroundStyle(.secondary)
                    Text(sectionCount(rows.count, highlighted: rows.count < items.count))
                }
            }
            if let who = connector.slack.connectedAs { ConnectedNote(name: who) }
            banner
            content
        }
    }

    @ViewBuilder private var banner: some View {
        if store.error != nil || store.notice != nil {
            Banner {
                if store.error == .unauthorized && store.notice == nil {
                    Text("Token do Slack inválido.")
                    Button("Ajustes", action: openSettings).buttonStyle(.link).foregroundStyle(.secondary)
                } else {
                    Text(String((store.notice ?? store.error?.userMessage ?? "").prefix(120)))
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !store.loaded {
            if store.error == nil { Note("Carregando…") }
        } else if !rows.isEmpty {
            list
        }
    }

    private var list: some View {
        let (shown, hidden) = visibleRows(rows, showAll: showAll, query: query)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { item in
                CompactRow(service: .slack, name: item.userName.split(separator: " ").first.map(String.init),
                           text: item.text, query: query, dim: isOld(item.ts.date), action: { store.open(item) }) {
                    Text(agoShort(item.ts.date)).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize()
                }
            }
            if hidden > 0 {
                Button(showAll ? "Ver menos" : "Ver mais \(hidden)") { showAll.toggle() }
                    .buttonStyle(.link).foregroundStyle(.secondary).font(.callout).padding(.top, 4)
            }
        }
    }
}
