import Foundation

/// Um PR que espera a revisão do usuário.
struct PullRequest: Identifiable, Equatable {
    var repo: String
    var number: Int
    var title: String
    var author: String
    var updatedAt: Date
    var url: URL
    var draft: Bool
    /// Só a GraphQL traz (a tela mostra): checks do último commit, aprovações e a decisão de revisão. nil = não veio.
    var checks: Checks? = nil
    var approvals: Int? = nil
    var reviewDecision: String? = nil

    var id: String { "\(repo)#\(number)" }
    /// Sem o dono ("web-app#2499"): cabe numa linha; o dono quase sempre é o mesmo.
    var shortId: String { "\(repo.split(separator: "/").last.map(String.init) ?? repo)#\(number)" }
}

/// O resumo dos checks do último commit (`statusCheckRollup`).
enum Checks: Equatable { case passing, failing(Int), pending }

/// O que a search REST não traz: os checks dos PRs para revisar (por id "dono/repo#n") e os PRs abertos do próprio
/// usuário (`author:@me`), com aprovações e checks.
struct PullDetails: Equatable {
    var checks: [String: Checks] = [:]
    var mine: [PullRequest] = []
}

/// Uma consulta GraphQL só, com o mesmo token do `gh`. Os contextos (até 50) contam quantos checks falharam.
// shortcut: lê só os 100 primeiros pedidos de revisão (a REST pagina até 300); os além disso ficam sem checks. Paginar com
// `after:` se a lista passar de 100.
let pullDetailsQuery = """
fragment checks on PullRequest { commits(last: 1) { nodes { commit { statusCheckRollup { state \
contexts(first: 50) { nodes { ... on CheckRun { conclusion } ... on StatusContext { state } } } } } } } }
query {
  review: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 100) {
    nodes { ... on PullRequest { number repository { nameWithOwner } ...checks } } }
  mine: search(query: "is:open is:pr author:@me archived:false sort:updated-desc", type: ISSUE, first: 50) {
    nodes { ... on PullRequest { number title url isDraft updatedAt repository { nameWithOwner } author { login } \
reviewDecision latestReviews(first: 20) { nodes { state } } ...checks } } }
}
"""

/// Resposta da `pullDetailsQuery` → checks e seus PRs. Pura, para testar sem rede. Nó que não é PR (vem `{}`) é pulado.
func decodePullDetails(_ data: Data) throws -> PullDetails {
    struct Response: Decodable {
        struct Message: Decodable { var message: String }
        struct Both: Decodable { var review: Search; var mine: Search }
        struct Search: Decodable { var nodes: [Node?] }
        struct Name: Decodable { var nameWithOwner: String }
        struct Login: Decodable { var login: String }
        struct State: Decodable { var state: String? }
        struct States: Decodable { var nodes: [State?] }
        struct Context: Decodable { var conclusion: String?; var state: String? }
        struct Contexts: Decodable { var nodes: [Context?] }
        struct Rollup: Decodable { var state: String; var contexts: Contexts? }
        struct Commit: Decodable { var statusCheckRollup: Rollup? }
        struct CommitNode: Decodable { var commit: Commit }
        struct Commits: Decodable { var nodes: [CommitNode?] }
        struct Node: Decodable {
            var number: Int?
            var title: String?
            var url: String?
            var isDraft: Bool?
            var updatedAt: String?
            var repository: Name?
            var author: Login?
            var reviewDecision: String?
            var latestReviews: States?
            var commits: Commits?
        }
        var data: Both?
        var errors: [Message]?
    }
    func checks(_ node: Response.Node) -> Checks? {
        guard let rollup = node.commits?.nodes.last??.commit.statusCheckRollup else { return nil }
        let bad: Set<String> = ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]
        let failed = (rollup.contexts?.nodes ?? []).filter { bad.contains($0?.conclusion ?? $0?.state ?? "") }.count
        if failed > 0 { return .failing(failed) }
        switch rollup.state {
        case "SUCCESS": return .passing
        // Falhou fora dos 50 contextos lidos: pelo menos um.
        case "FAILURE", "ERROR": return .failing(1)
        default: return .pending
        }
    }
    let response: Response
    do { response = try JSONDecoder().decode(Response.self, from: data) } catch { throw APIError.server("resposta inesperada do GitHub") }
    guard let both = response.data else { throw APIError.server(response.errors?.first?.message ?? "resposta inesperada do GitHub") }
    let clock = ISO8601DateFormatter()
    var result = PullDetails()
    for node in both.review.nodes.compactMap({ $0 }) {
        guard let number = node.number, let repo = node.repository?.nameWithOwner, let found = checks(node) else { continue }
        result.checks["\(repo)#\(number)"] = found
    }
    result.mine = both.mine.nodes.compactMap { $0 }.compactMap { node in
        guard let number = node.number, let repo = node.repository?.nameWithOwner, let url = node.url.flatMap(URL.init(string:)),
              let date = node.updatedAt.flatMap(clock.date(from:)) else { return nil }
        return PullRequest(repo: repo, number: number, title: node.title ?? "", author: node.author?.login ?? "?", updatedAt: date,
                           url: url, draft: node.isDraft ?? false, checks: checks(node),
                           approvals: (node.latestReviews?.nodes ?? []).filter { $0?.state == "APPROVED" }.count,
                           reviewDecision: node.reviewDecision)
    }
    return result
}

/// Resposta da search API (`/search/issues`) → PRs. Pura, para testar sem rede.
func decodePullRequests(_ data: Data) throws -> [PullRequest] { try decodePullRequestPage(data).items }

/// Uma página da search API: os PRs e o `total_count` (nil se não vier).
func decodePullRequestPage(_ data: Data) throws -> (items: [PullRequest], total: Int?) {
    struct Page: Decodable {
        struct Item: Decodable {
            struct User: Decodable { var login: String }
            var repository_url: String
            var number: Int
            var title: String
            var user: User?
            var updated_at: String
            var html_url: String
            var draft: Bool?
        }
        var items: [Item]
        var total_count: Int?
    }
    let clock = ISO8601DateFormatter()
    do {
        let page = try JSONDecoder().decode(Page.self, from: data)
        return (try page.items.map { item in
            // ".../repos/dono/nome" → "dono/nome"
            let repo = item.repository_url.split(separator: "/").suffix(2).joined(separator: "/")
            guard let url = URL(string: item.html_url), let date = clock.date(from: item.updated_at) else {
                throw APIError.server("resposta inesperada do GitHub")
            }
            return PullRequest(repo: repo, number: item.number, title: item.title, author: item.user?.login ?? "?",
                               updatedAt: date, url: url, draft: item.draft ?? false)
        }, page.total_count)
    } catch let error as APIError {
        throw error
    } catch {
        throw APIError.server("resposta inesperada do GitHub")
    }
}

/// O GitHub responde o limite de requisições com 403 (ou 429): `retry-after` ou `x-ratelimit-remaining: 0`.
/// Qualquer outro 403 é recusa de acesso, que não é "sem permissão" do Jira. Puro, para testar.
func githubError(status: Int, headers: [String: String], now: Date = Date()) -> APIError? {
    guard status == 403 else { return nil }
    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name }?.value.trimmingCharacters(in: .whitespaces)
    }
    if let wait = header("retry-after").flatMap({ Int($0) }) { return .rateLimited(retryAfter: max(wait, 1)) }
    if header("x-ratelimit-remaining") == "0" {
        let reset = header("x-ratelimit-reset").flatMap { Double($0) }
        return .rateLimited(retryAfter: reset.map { max(Int($0 - now.timeIntervalSince1970), 1) } ?? 60)
    }
    return .server("GitHub recusou o acesso (403), confira o login do gh")
}

/// O token vem do `gh` que já está logado no terminal; guardado só em memória.
enum GitHubToken {
    /// O app aberto pelo Finder não tem PATH: procura nos lugares de sempre.
    static var candidates: [String] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/gh").path,
         "/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    }

    /// `gh auth token`; nil sem `gh` ou sem login. Nunca imprime nem loga o token.
    static func read() async -> String? {
        await Task.detached {
            for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["auth", "token"]
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                guard (try? process.run()) != nil else { continue }
                // Se travar (ex.: pedido do chaveiro), não prende a atualização para sempre.
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if process.isRunning { process.terminate() } }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0, !token.isEmpty, !token.contains(where: \.isWhitespace) { return token }
            }
            return nil
        }.value
    }
}

/// Junta as páginas (`page` 1, 2, …, 100 PRs cada) até uma vir incompleta, chegar no `total_count` ou no teto.
/// Sem repetidos: se a lista mudar entre as páginas, um PR pode vir duas vezes.
func collectPullRequests(cap: Int = 300, page: (Int) async throws -> (items: [PullRequest], total: Int?)) async throws -> [PullRequest] {
    var result: [PullRequest] = []
    var ids = Set<String>()
    var number = 1
    while true {
        let next = try await page(number)
        result += next.items.filter { ids.insert($0.id).inserted }
        if next.items.count < GitHubClient.pageSize || result.count >= cap || next.total.map({ result.count >= $0 }) == true { break }
        number += 1
    }
    return Array(result.prefix(cap))
}

/// Cliente da search API do GitHub.
struct GitHubClient {
    static let pageSize = 100

    func reviewRequests(token: String) async throws -> [PullRequest] {
        try await collectPullRequests { try await page($0, token: token) }
    }

    private func page(_ number: Int, token: String) async throws -> (items: [PullRequest], total: Int?) {
        var parts = URLComponents(string: "https://api.github.com/search/issues")!
        parts.queryItems = [URLQueryItem(name: "q", value: "is:open is:pr review-requested:@me archived:false"),
                            URLQueryItem(name: "sort", value: "updated"),
                            URLQueryItem(name: "per_page", value: "\(Self.pageSize)"),
                            URLQueryItem(name: "page", value: "\(number)")]
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return try decodePullRequestPage(try await HTTP.send(request, mapError: { status, headers, _ in githubError(status: status, headers: headers) }))
    }

    /// Checks das revisões e seus PRs abertos (`pullDetailsQuery`).
    func details(token: String) async throws -> PullDetails {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": pullDetailsQuery])
        return try decodePullDetails(try await HTTP.send(request, mapError: { status, headers, _ in githubError(status: status, headers: headers) }))
    }
}

/// `Pauta --dump github`: os PRs que o GitHub devolve. Nunca imprime o token.
enum GitHubDump {
    static func run() async -> Int32 {
        guard let token = await GitHubToken.read() else { print("sem gh logado (gh auth login)"); return 1 }
        do {
            let prs = try await GitHubClient().reviewRequests(token: token)
            print("PRs para revisar: \(prs.count)")
            for pr in prs { print("  \(pr.id) \(pr.title)") }
            let mine = try await GitHubClient().details(token: token).mine
            print("Seus PRs abertos: \(mine.count)")
            for pr in mine { print("  \(pr.id) \(pr.title) · \(prStatusText(pr).text)") }
            return 0
        } catch {
            print("erro: \((error as? APIError)?.userMessage ?? "\(error)")")
            return 1
        }
    }
}
