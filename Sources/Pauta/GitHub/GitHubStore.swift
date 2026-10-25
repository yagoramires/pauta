import AppKit

/// Estado da seção do GitHub: PRs esperando a revisão. A UI só lê; as ações passam por aqui.
@MainActor
final class GitHubStore: ObservableObject {
    @Published var items: [PullRequest] = []
    @Published var error: APIError?
    /// Aviso leve (limite da API); a lista antiga continua valendo.
    @Published var notice: String?
    @Published var updatedAt: Date?
    /// Já houve uma busca com sucesso (distingue "carregando" de "nada para revisar").
    @Published var loaded = false
    /// Sem `gh` ou sem login: a seção ensina o `gh auth login`.
    @Published var needsLogin = false

    var count: Int { items.count }

    /// Só em memória; relido do `gh` quando a API devolve 401.
    private var token: String?
    private let readToken: () async -> String?
    private let search: (String) async throws -> [PullRequest]
    private var inflight: Task<Void, Never>?

    init(readToken: @escaping () async -> String? = GitHubToken.read,
         search: @escaping (String) async throws -> [PullRequest] = { try await GitHubClient().reviewRequests(token: $0) }) {
        self.readToken = readToken
        self.search = search
    }

    /// Uma busca por vez: quem chama no meio dela só espera por ela.
    func refresh() async {
        if let running = inflight { return await running.value }
        let task = Task { await load(); inflight = nil }
        inflight = task
        await task.value
    }

    private func load() async {
        do {
            if token == nil { token = await readToken() }
            guard let first = token else { return needsLogin(true) }
            let found: [PullRequest]
            do { found = try await search(first) } catch APIError.unauthorized {
                // Token velho (o usuário pode ter refeito o login): relê do gh e tenta uma vez mais.
                token = await readToken()
                guard let again = token else { return needsLogin(true) }
                found = try await search(again)
            }
            items = found
            needsLogin = false; error = nil; notice = nil; updatedAt = Date(); loaded = true
        } catch {
            fail(error)
        }
    }

    private func needsLogin(_ value: Bool) {
        needsLogin = value
        // updatedAt também aqui: senão cada abertura do popover dispara o gh de novo.
        items = []; error = nil; notice = nil; loaded = true; updatedAt = Date()
    }

    func open(_ pr: PullRequest) { NSWorkspace.shared.open(pr.url) }

    /// Limite da API mantém a lista e só avisa; o resto vira erro (inclusive JSON diferente do esperado).
    private func fail(_ e: Error) {
        debugLog("github: \(e)")
        if case .rateLimited(let seconds)? = e as? APIError {
            notice = "GitHub limitou as requisições (liberam em ~\(seconds) s), tento de novo na próxima atualização"
            return
        }
        error = e as? APIError ?? .server("resposta inesperada do GitHub")
        notice = nil
    }
}
