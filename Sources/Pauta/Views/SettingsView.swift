import SwiftUI

/// Board a gravar: um só vale sem perguntar; com vários mantém o já escolhido se ainda existir; senão nenhum
/// (o Jira usa o primeiro do projeto).
func boardChoice(_ boards: [(id: Int, name: String)], current: Int?) -> Int? {
    if boards.count == 1 { return boards[0].id }
    return boards.contains { $0.id == current } ? current : nil
}

/// Ajustes: conectar/desconectar Slack e Jira e, escondido em "Avançado", colar os tokens à mão. Salvar chama
/// `onSave` (o AppDelegate grava e reconfigura os stores; a tela segue os stores e o Connector).
struct SettingsView: View {
    @ObservedObject var slack: SlackStore
    @ObservedObject var jira: JiraStore
    @ObservedObject var connector: Connector
    @ObservedObject var prefs: PrefsStore
    var onSave: (Credentials) -> Void
    /// O que estava no disco ao abrir; serve de referência para saber o que o usuário mudou.
    @ViewState private var base: Credentials
    @ViewState private var draft: Credentials
    @ViewState private var advanced: Bool
    @ViewState private var boards: [(id: Int, name: String)] = []
    @ViewState private var boardsLoading = false
    @ViewState private var boardsError: String?

    init(slack: SlackStore, jira: JiraStore, connector: Connector, prefs: PrefsStore, advancedOpen: Bool = false,
         onSave: @escaping (Credentials) -> Void) {
        self.slack = slack; self.jira = jira; self.connector = connector; self.prefs = prefs; self.onSave = onSave
        _advanced = ViewState(wrappedValue: advancedOpen)
        let saved = Credentials.load()
        _base = ViewState(wrappedValue: saved)
        _draft = ViewState(wrappedValue: saved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ajustes").font(.system(size: 18, weight: .semibold)).tracking(-0.25)
            connection("Slack", .slack, connected: slack.configured)
            connection("Jira", .jira, connected: jira.configured)
            VStack(alignment: .leading, spacing: 4) {
                ServiceTitle(.github)
                Text("Usa o gh já logado no terminal (gh auth login).").font(.caption).foregroundStyle(.secondary)
            }
            display
            DisclosureGroup("Avançado (colar token manualmente)", isExpanded: $advanced) { manual.padding(.top, 8) }
                .font(.callout)
        }
        .padding(16)
        .task { if draft.jiraReady { await loadBoards() } }
        // Conectar/Desconectar gravam com a tela aberta: base e rascunho passam a partir do disco, sem perder o que foi digitado.
        .onChange(of: [slack.configured, jira.configured]) {
            let saved = Credentials.load()
            draft = Credentials.merged(base: base, edited: draft, over: saved)
            base = saved
        }
    }

    /// Preferências de exibição: gravam direto em `prefs.prefs`, sem botão de salvar.
    private var display: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Exibição")
            switchRow("Menções em canais", $prefs.prefs.channelMentions)
            switchRow("Cards livres", $prefs.prefs.freeCards)
            prefRow("Densidade") {
                Picker("", selection: $prefs.prefs.density) {
                    Text("Confortável").tag(Density.comfortable)
                    Text("Compacta").tag(Density.compact)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            prefRow("Atualizar a cada") {
                Picker("", selection: $prefs.prefs.refreshMinutes) {
                    ForEach(Prefs.refreshChoices, id: \.self) { Text("\($0) min").tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            switchRow("Notificações do Slack", $prefs.prefs.slackNotifications)
        }
    }

    private func prefRow<Control: View>(_ label: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 8)
            control()
        }
    }

    private func switchRow(_ label: String, _ isOn: Binding<Bool>) -> some View {
        prefRow(label) {
            Toggle("", isOn: isOn).toggleStyle(.switch).controlSize(.mini).tint(.primary).labelsHidden()
        }
    }

    private func connection(_ name: String, _ service: Service, connected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ServiceTitle(service: service == .slack ? .slack : .jira) {
                if connected {
                    HStack(spacing: 10) {
                        Label("Conectado", systemImage: "checkmark.circle.fill")
                        Button("Desconectar") { connector.disconnect(service) }.buttonStyle(.link).foregroundStyle(.secondary)
                    }
                }
            }
            if let who = connector.flow(service).connectedAs { ConnectedNote(name: who) }
            if !connected { ConnectCard(service: service, connector: connector) }
        }
    }

    /// Os campos manuais num cartão suave, como o resto do popover.
    private var manual: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(label: "Site Jira") { TextField("https://… (endereço do seu Jira)", text: $draft.jiraSite).inputBox() }
            LabeledField(label: "E-mail") { TextField("voce@empresa.com", text: $draft.jiraEmail).inputBox() }
            LabeledField(label: "API token") { SecureField("token do Jira", text: $draft.jiraToken).inputBox() }
            LabeledField(label: "Projeto") { TextField("chave, ex.: ABC (vazio = todos)", text: $draft.jiraProject).inputBox() }
            boardRow
            LabeledField(label: "Slack user token") { SecureField("xoxp-…", text: $draft.slackToken).inputBox() }
            HStack {
                Spacer()
                Button("Salvar") { onSave(Credentials.merged(base: base, edited: draft, over: Credentials.load())) }
                    .buttonStyle(GraphiteButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    /// Seletor de board quando o projeto tem mais de um; "Carregar boards" busca de novo.
    @ViewBuilder private var boardRow: some View {
        if draft.jiraReady {
            if boards.count > 1 {
                LabeledField(label: "Board") {
                    Picker("", selection: $draft.jiraBoardId) {
                        Text("Automático (primeiro)").tag(Int?.none)
                        ForEach(boards, id: \.id) { Text($0.name).tag(Int?.some($0.id)) }
                    }.labelsHidden()
                }
            }
            HStack {
                Button(boardsLoading ? "Carregando…" : "Carregar boards") { Task { await loadBoards() } }
                    .disabled(boardsLoading)
                    .buttonStyle(.link).foregroundStyle(.secondary)
                if boards.count == 1 { Text(boards[0].name).foregroundStyle(.secondary) }
            }
            .font(.caption)
            if let boardsError { Label(boardsError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func loadBoards() async {
        boardsLoading = true
        boardsError = nil
        defer { boardsLoading = false }
        do {
            let found = try await JiraClient(draft).boards(project: draft.jiraProject)
            guard !found.isEmpty else { boardsError = "Nenhum board no projeto \(draft.jiraProject)"; return }
            boards = found
            draft.jiraBoardId = boardChoice(found, current: draft.jiraBoardId)
        } catch {
            boardsError = (error as? APIError)?.userMessage ?? "Não consegui listar os boards"
        }
    }
}
