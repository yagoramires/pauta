import SwiftUI

/// "Conectar Slack/Jira": o botão e, enquanto o Pauta espera o token, os passos curtos. Usado na seção desconectada
/// e nos ajustes.
struct ConnectCard: View {
    let service: Service
    @ObservedObject var connector: Connector
    @ViewState private var email: String
    @ViewState private var site: String

    init(service: Service, connector: Connector) {
        self.service = service
        self.connector = connector
        _email = ViewState(wrappedValue: "")
        _site = ViewState(wrappedValue: defaultJiraSite)
    }

    private var flow: Connector.Flow { connector.flow(service) }
    private var name: String { service == .slack ? "Slack" : "Jira" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if flow.waiting { waiting } else { idle }
            if let error = flow.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Uma leitura do disco por aparição (e não a cada redesenho do pai): e-mail e site do último salvo.
        .onAppear {
            guard service == .jira, email.isEmpty else { return }
            let saved = Credentials.load()
            email = saved.jiraEmail
            if !saved.jiraSite.isEmpty { site = saved.jiraSite }
        }
    }

    @ViewBuilder private var idle: some View {
        Text(service == .slack ? "DMs e menções que você ainda não leu." : "Seus cards e os cards livres da sprint.")
            .font(.caption).foregroundStyle(.secondary)
        if service == .jira {
            VStack(alignment: .leading, spacing: 8) {
                LabeledField(label: "Seu e-mail do Jira") { TextField("voce@empresa.com", text: $email).inputBox() }
                LabeledField(label: "Site do Jira") { TextField("https://… (endereço do seu Jira)", text: $site).inputBox() }
            }
        }
        Button("Conectar \(name)") {
            if service == .slack { connector.connectSlack() } else { connector.connectJira(email: email, site: site) }
        }
        .buttonStyle(GraphiteButtonStyle())
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Aguardando você copiar o token…").font(.callout)
                Button("(cancelar)") { connector.cancel(service) }.buttonStyle(.link).foregroundStyle(.secondary).font(.callout)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(connectSteps(service).enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if service == .slack {
                Text(slackApprovalNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "Conectado como X" logo depois de conectar.
struct ConnectedNote: View {
    var name: String

    var body: some View {
        Label("Conectado como \(name)", systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(.secondary)
            .transition(.opacity)
    }
}
