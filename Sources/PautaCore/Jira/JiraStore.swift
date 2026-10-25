import AppKit

/// Um card só continua livre se ninguém virou responsável desde a última busca.
func freeStillFree(_ fresh: JiraIssue) -> Bool { fresh.assigneeId == nil }

/// Texto para a falha de uma transição: só diz "pede campos" quando o corpo do erro fala de campo/tela.
func transitionFailureNotice(body: String) -> String {
    let text = body.lowercased()
    let needsFields = ["field", "screen", "required", "campo", "tela", "obrigat"].contains { text.contains($0) }
    return needsFields ? "Essa transição pede campos, abra no Jira" : "Não foi possível mudar o status, abra no Jira"
}

/// Estado do popover do Jira: listas, sprint, erro. A UI só lê; as ações passam por aqui.
@MainActor
final class JiraStore: ObservableObject {
    @Published var mine: [JiraIssue] = []
    @Published var free: [JiraIssue] = []
    @Published var sprint: Sprint?
    @Published var error: APIError?
    /// Mensagem própria (ex.: "Alguém já pegou X"); a faixa mostra isto antes do texto do `error`.
    @Published var notice: String?
    /// Card que o erro menciona (transição que pede campos): a faixa oferece abri-lo no Jira.
    @Published var errorKey: String?
    @Published var updatedAt: Date?
    @Published var busy: Set<String> = []
    /// Já houve uma busca com sucesso (distingue "carregando" de "lista vazia").
    @Published var loaded = false
    /// A busca na sprint aberta voltou vazia: aí sim "nenhuma sprint ativa" (o `sprint` abaixo só dá nome e prazo).
    @Published var sprintIsEmpty = false
    /// Sem credenciais o popover mostra os ajustes.
    @Published var configured: Bool

    var freeCount: Int { free.count }
    var project: String { credentials.jiraProject }

    private var client: JiraClient?
    private var credentials: Credentials
    /// Do `myself()`, buscado uma vez só.
    private var accountId: String?
    private var boardId: Int?
    /// Muda ao reconfigurar: uma busca iniciada antes disso é descartada.
    private var epoch = 0
    /// Busca em andamento; quem chama `refresh()` no meio dela só espera por ela.
    private var inflight: Task<Void, Never>?
    /// Só o selftest troca: as transições de um card sem passar pelo cliente.
    private let fetchTransitions: ((String) async throws -> [Transition])?

    init(client: JiraClient?, credentials: Credentials = Credentials(),
         transitions: ((String) async throws -> [Transition])? = nil) {
        self.client = client
        self.credentials = credentials
        fetchTransitions = transitions
        configured = client != nil
    }

    /// Depois de salvar os ajustes: se algo do Jira mudou, cliente novo e tudo do site/usuário anterior some.
    func reconfigure(_ c: Credentials) {
        // Mudou só o Slack: não apaga a lista nem o "atualizado há".
        guard !c.sameJira(as: credentials) else { return }
        credentials = c
        client = c.jiraReady ? JiraClient(c) : nil
        configured = client != nil
        accountId = nil; boardId = nil
        epoch += 1
        inflight = nil
        mine = []; free = []; sprint = nil; sprintIsEmpty = false
        error = nil; notice = nil; errorKey = nil; updatedAt = nil; loaded = false
    }

    func open(_ key: String) {
        if let base = credentials.jiraBase { NSWorkspace.shared.open(base.appendingPathComponent("browse/\(key)")) }
    }

    /// Uma busca por vez (duas juntas gravariam por cima uma da outra). `fresh`: depois de uma ação,
    /// espera a busca em andamento (que pode ter começado antes da ação) e faz outra.
    func refresh(fresh: Bool = false) async {
        guard client != nil else { return }
        while let running = inflight {
            await running.value
            if !fresh { return }
        }
        let version = epoch
        let task = Task { await load(); if epoch == version { inflight = nil } }
        inflight = task
        await task.value
    }

    private func load() async {
        guard let client else { return }
        let ticket = epoch
        let project = credentials.jiraProject
        do {
            // Em paralelo. A da sprint só pergunta se ela tem algum card (1 resultado, sem paginar).
            async let mineSearch = client.search(JQL.mine(project))
            async let freeSearch = client.search(JQL.free(project))
            async let probeSearch = client.search(JQL.sprint(project), limit: 1)
            let (mine, free, probe) = try await (mineSearch, freeSearch, probeSearch)
            // A sprint vem dos próprios cards; só sem ela cai no palpite do board.
            var sprint = (probe + mine + free).lazy.compactMap(\.sprint).first
            var board = credentials.jiraBoardId ?? sprint?.boardId
            if board == nil { board = try await guessBoard(client) }
            if sprint == nil, let board {
                // Kanban (sem sprint) responde com erro do servidor: vira "sem sprint".
                do { sprint = try await client.activeSprint(board: board) } catch APIError.server(_) {}
            }
            guard epoch == ticket else { return }
            self.mine = mine.filter { !isClosed($0) }; self.free = free.filter { !isClosed($0) }; self.sprint = sprint; sprintIsEmpty = probe.isEmpty
            error = nil; notice = nil; errorKey = nil; updatedAt = Date(); loaded = true
        } catch {
            guard epoch == ticket else { return }
            fail(error)
        }
    }

    func pick(_ key: String) async {
        guard let client, !busy.contains(key) else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            let fresh = try await client.issue(key)
            if freeStillFree(fresh) {
                try await client.assign(key, accountId: try await me(client))
                await refresh(fresh: true)
            } else {
                await refresh(fresh: true)
                notice = "Alguém já pegou \(key)"
            }
        } catch {
            fail(error)
        }
    }

    func transition(_ key: String, to transition: Transition) async {
        guard let client, !busy.contains(key) else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await client.transition(key, to: transition.id)
            await refresh(fresh: true)
        } catch APIError.server(let body) {
            debugLog("jira: transição de \(key) falhou: \(body)")
            notice = transitionFailureNotice(body: body)
            errorKey = key
        } catch {
            fail(error)
        }
    }

    /// nil = não carregou (o menu tenta de novo). A falha só vai pro log: não é erro do Jira inteiro (faixa e triângulo).
    func transitions(for key: String) async -> [Transition]? {
        do {
            if let fetchTransitions { return try await fetchTransitions(key) }
            guard let client else { return nil }
            return try await client.transitions(key)
        } catch {
            debugLog("jira: transições de \(key) não carregaram: \(error)")
            return nil
        }
    }

    private func me(_ client: JiraClient) async throws -> String {
        if let accountId { return accountId }
        let id = try await client.myself().accountId
        guard !id.isEmpty else { throw APIError.server("resposta inesperada do Jira") }
        accountId = id
        return id
    }

    /// Sem board nos ajustes nem sprint nos cards: o primeiro board do projeto.
    private func guessBoard(_ client: JiraClient) async throws -> Int? {
        if boardId == nil { boardId = try await client.boards(project: credentials.jiraProject).first?.id }
        return boardId
    }

    /// Qualquer erro que não seja `APIError` (ex.: JSON diferente do esperado) vira mensagem para a UI.
    private func fail(_ e: Error) {
        error = e as? APIError ?? .server("resposta inesperada do Jira")
        notice = nil; errorKey = nil
        debugLog("jira: \(e)")
    }
}
