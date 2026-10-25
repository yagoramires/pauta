import AppKit

/// Os fluxos "Conectar Slack/Jira": abre a página certa, vigia a área de transferência (TokenCatcher), valida o token
/// na API e grava. Mora no AppDelegate (e não na tela) para o fluxo continuar quando o popover fecha: ao ir para o
/// navegador copiar o token, o popover fecha sozinho.
@MainActor
final class Connector: ObservableObject {
    struct Flow: Equatable {
        var waiting = false
        /// Última validação que falhou; o Pauta continua esperando.
        var error: String?
        /// "Conectado como X", por alguns segundos.
        var connectedAs: String?
    }

    @Published var slack = Flow()
    @Published var jira = Flow()

    private var catchers: [Service: TokenCatcher] = [:]
    private var validating: Set<Service> = []
    private var jiraInput: (email: String, site: String)?
    private let save: (Credentials) -> Void
    private let open: (URL) -> Void
    private let validateSlack: (String) async throws -> String
    private let validateJira: (Credentials) async throws -> String

    init(save: @escaping (Credentials) -> Void,
         open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         validateSlack: @escaping (String) async throws -> String = Connector.checkSlack,
         validateJira: @escaping (Credentials) async throws -> String = Connector.checkJira) {
        self.save = save
        self.open = open
        self.validateSlack = validateSlack
        self.validateJira = validateJira
    }

    func flow(_ service: Service) -> Flow { service == .slack ? slack : jira }

    private func update(_ service: Service, _ change: (inout Flow) -> Void) {
        if service == .slack { change(&slack) } else { change(&jira) }
    }

    func connectSlack() { start(.slack, page: slackManifestURL()) }

    func connectJira(email: String, site: String) {
        guard let input = jiraConnectInput(email: email, site: site) else {
            // Com um site válido qualquer, o defeito é o e-mail; senão é o site.
            let emailOK = jiraConnectInput(email: email, site: "https://example.com") != nil
            return update(.jira) { $0.error = emailOK ? "Informe o site do Jira (https)" : "Informe o e-mail do Jira" }
        }
        jiraInput = input
        start(.jira, page: jiraTokenPage)
    }

    private func start(_ service: Service, page: URL) {
        stop(service)
        update(service) { $0 = Flow(waiting: true) }
        let catcher = TokenCatcher(service: service)
        catcher.onToken = { [weak self] token, count in self?.validate(service, token, count) }
        catcher.onTimeout = { [weak self] in self?.timedOut(service) }
        catchers[service] = catcher
        catcher.start()
        open(page)
    }

    /// Cancelar, sucesso, prazo ou fechar o app.
    func stop(_ service: Service) {
        catchers[service]?.stop()
        catchers[service] = nil
    }

    func cancel(_ service: Service) {
        stop(service)
        update(service) { $0 = Flow() }
    }

    func cancelAll() { for service in [Service.slack, .jira] { cancel(service) } }

    /// Alguma vigia da área de transferência ligada (o selftest confere que o `stop()` desliga).
    var catching: Bool { !catchers.isEmpty }

    /// Desconectar: apaga só o token (o e-mail e o site do Jira ficam para a próxima vez).
    func disconnect(_ service: Service) {
        cancel(service)
        var credentials = Credentials.load()
        if service == .slack { credentials.slackToken = "" } else { credentials.jiraToken = "" }
        save(credentials)
    }

    private func timedOut(_ service: Service) {
        stop(service)
        update(service) { $0 = Flow(error: "Tempo esgotado (10 min). Clique em Conectar para tentar de novo.") }
    }

    private func validate(_ service: Service, _ token: String, _ count: Int) {
        guard !validating.contains(service), let catcher = catchers[service] else { return }
        validating.insert(service)
        Task {
            var edited = Credentials.load()
            let outcome: Result<String, Error>
            do {
                switch service {
                case .slack:
                    edited.slackToken = token
                    outcome = .success(try await validateSlack(token))
                case .jira:
                    guard let input = jiraInput else { validating.remove(service); return }
                    edited.jiraSite = input.site; edited.jiraEmail = input.email; edited.jiraToken = token
                    outcome = .success(try await validateJira(edited.trimmed()))
                }
            } catch {
                outcome = .failure(error)
            }
            // Livre já aqui: copiar outro token (ou recomeçar) não pode esperar o aviso de "conectado" sumir.
            validating.remove(service)
            // Cancelou (ou recomeçou) enquanto validava: este resultado não vale mais.
            guard catchers[service] === catcher else { return }
            switch outcome {
            case .failure(let error):
                update(service) { $0.error = connectErrorMessage(error, service: service) }
                debugLog("connect: \(service) não validou: \(error is APIError ? "\(error)" : "erro")")
            case .success(let who):
                // Relê o disco depois do await: nada gravado nesse meio-tempo se perde. `save` faz o trim e o refresh.
                var current = Credentials.load()
                if service == .slack { current.slackToken = edited.slackToken } else {
                    current.jiraSite = edited.jiraSite; current.jiraEmail = edited.jiraEmail; current.jiraToken = edited.jiraToken
                }
                save(current)
                catcher.clearIfUnchanged(count)
                stop(service)
                update(service) { $0 = Flow(connectedAs: who) }
                debugLog("connect: \(service) conectado")
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    update(service) { $0.connectedAs = nil }
                }
            }
        }
    }

    // MARK: Validação nas APIs reais

    /// `auth.test`; o nome vem do `users.info` (se faltar, o endereço do workspace).
    nonisolated static func checkSlack(_ token: String) async throws -> String {
        let client = SlackClient(token: token)
        let who = try await client.authTest()
        return (try? await client.userName(who.userId)) ?? who.teamURL.host ?? "Slack"
    }

    /// `GET /rest/api/3/myself` com Basic e-mail:token.
    nonisolated static func checkJira(_ credentials: Credentials) async throws -> String {
        let me = try await JiraClient(credentials).myself()
        return me.name.isEmpty ? credentials.jiraEmail : me.name
    }
}
