import SwiftUI

/// Seção "Revisões": PRs que esperam a revisão do usuário, sem o que está no destaque. O token vem do `gh` do terminal
/// (sem botão de conectar). Conectada, carregada, sem erro e sem linhas, a seção some.
struct GitHubView: View {
    @ObservedObject var store: GitHubStore
    /// Os PRs visíveis (já com a busca aplicada).
    var items: [PullRequest]
    var highlightedId: String?
    var query: String
    @ViewState private var showAll: Bool

    init(store: GitHubStore, items: [PullRequest], highlightedId: String? = nil, query: String = "", showAll: Bool = false) {
        self.store = store
        self.items = items
        self.highlightedId = highlightedId
        self.query = query
        _showAll = ViewState(wrappedValue: showAll)
    }

    private var rows: [PullRequest] { items.filter { $0.id != highlightedId } }

    var body: some View {
        if showsSection(connected: !store.needsLogin, loaded: store.loaded, failed: store.error != nil || store.notice != nil,
                        rows: rows.count) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle("Revisões") {
                    if !rows.isEmpty { Text(sectionCount(rows.count, highlighted: rows.count < items.count)) }
                }
                banner
                content
            }
        }
    }

    @ViewBuilder private var banner: some View {
        if store.error != nil || store.notice != nil {
            Banner {
                if store.error == .unauthorized && store.notice == nil {
                    Text("Token do gh inválido. Rode gh auth login.")
                } else {
                    Text(String((store.notice ?? store.error?.userMessage ?? "").prefix(120)))
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if store.needsLogin {
            VStack(alignment: .leading, spacing: 2) {
                Note("Entre no GitHub pelo terminal:")
                Text("gh auth login").font(.system(size: 12)).textSelection(.enabled)
            }
        } else if !store.loaded {
            if store.error == nil { Note("Carregando…") }
        } else if !rows.isEmpty {
            list
        }
    }

    private var list: some View {
        let (shown, hidden) = visibleRows(rows, showAll: showAll, query: query)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { pr in
                CompactRow(service: .github, text: pr.title, query: query, badge: pr.draft ? "rascunho" : nil, dim: isOld(pr.updatedAt),
                           action: { store.open(pr) }) {
                    Text(agoShort(pr.updatedAt)).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize()
                }
            }
            if hidden > 0 {
                Button(showAll ? "Ver menos" : "Ver mais \(hidden)") { showAll.toggle() }
                    .buttonStyle(.link).foregroundStyle(.secondary).font(.callout).padding(.top, 4)
            }
        }
    }
}
