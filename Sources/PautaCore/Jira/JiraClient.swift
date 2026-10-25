import Foundation

/// Cliente do Jira Cloud (API v3 + Agile). Auth Basic `email:token`.
final class JiraClient {
    private let credentials: Credentials

    init(_ c: Credentials) { credentials = c }

    private func send(_ method: String = "GET", _ path: String, query: [String: String] = [:],
                      body: [String: Any]? = nil) async throws -> Data {
        guard let base = credentials.jiraBase,
              var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw APIError.transport("site do Jira inválido") }
        if !query.isEmpty { parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw APIError.transport("site do Jira inválido") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.jiraAuthorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await HTTP.send(request)
    }

    private static let fields = ["summary", "status", "assignee", "parent", "issuetype", "customfield_10020"]

    private func object(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.server("resposta inesperada")
        }
        return json
    }

    func myself() async throws -> (accountId: String, name: String) {
        let json = try object(await send("GET", "rest/api/3/myself"))
        return (json["accountId"] as? String ?? "", json["displayName"] as? String ?? "")
    }

    /// Corpo do `search/jql`; puro, para testar.
    static func searchBody(_ jql: String, limit: Int, token: String?) -> [String: Any] {
        var body: [String: Any] = ["jql": jql, "fields": fields, "maxResults": limit]
        if let token { body["nextPageToken"] = token }
        return body
    }

    /// Todas as páginas; com `limit`, só os primeiros `limit` cards (uma página, sem paginar).
    func search(_ jql: String, limit: Int? = nil) async throws -> [JiraIssue] {
        var result: [JiraIssue] = []
        var token: String?
        repeat {
            let page = try JiraIssue.decodePage(await send("POST", "rest/api/3/search/jql",
                                                           body: Self.searchBody(jql, limit: limit ?? 100, token: token)))
            result += page.issues
            token = limit == nil ? page.next : nil
        } while token != nil
        return result
    }

    func issue(_ key: String) async throws -> JiraIssue {
        try JiraIssue.decode(await send("GET", "rest/api/3/issue/\(key)", query: ["fields": Self.fields.joined(separator: ",")]))
    }

    func transitions(_ key: String) async throws -> [Transition] {
        let list = try object(await send("GET", "rest/api/3/issue/\(key)/transitions"))["transitions"] as? [[String: Any]]
        return (list ?? []).compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return Transition(id: id, name: name, toStatus: ($0["to"] as? [String: Any])?["name"] as? String ?? name)
        }
    }

    func transition(_ key: String, to id: String) async throws {
        _ = try await send("POST", "rest/api/3/issue/\(key)/transitions", body: ["transition": ["id": id]])
    }

    func assign(_ key: String, accountId: String) async throws {
        _ = try await send("PUT", "rest/api/3/issue/\(key)/assignee", body: ["accountId": accountId])
    }

    func boards(project: String) async throws -> [(id: Int, name: String)] {
        let values = try object(await send("GET", "rest/agile/1.0/board", query: project.isEmpty ? [:] : ["projectKeyOrId": project]))["values"] as? [[String: Any]]
        return (values ?? []).compactMap {
            guard let id = $0["id"] as? Int, let name = $0["name"] as? String else { return nil }
            return (id, name)
        }
    }

    func activeSprint(board: Int) async throws -> Sprint? {
        let values = try object(await send("GET", "rest/agile/1.0/board/\(board)/sprint", query: ["state": "active"]))["values"] as? [[String: Any]]
        guard let first = values?.first, let id = first["id"] as? Int else { return nil }
        return Sprint(id: id, name: first["name"] as? String ?? "Sprint", endDate: (first["endDate"] as? String).flatMap(parseJiraDate),
                      boardId: board)
    }
}

/// Só o `--dump jira` usa: o app não traduz colunas, então a busca não monta nem trava mapa de status.
extension JiraClient {
    /// Ids dos status por coluna, na ordem do board (a configuração só traz ids).
    func columnStatusIds(board: Int) async throws -> [[String]] {
        let config = try object(await send("GET", "rest/agile/1.0/board/\(board)/configuration"))
        let columns = (config["columnConfig"] as? [String: Any])?["columns"] as? [[String: Any]] ?? []
        return columns.map { ($0["statuses"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } }
    }

    /// id → nome de todos os status do site (`GET /rest/api/3/status`).
    func statusNames() async throws -> [String: String] {
        let all = try JSONSerialization.jsonObject(with: await send("GET", "rest/api/3/status")) as? [[String: Any]] ?? []
        return Dictionary(all.compactMap { status in
            (status["id"] as? String).flatMap { id in (status["name"] as? String).map { (id, $0) } }
        }) { first, _ in first }
    }
}

/// `Pauta --dump jira`: o que o Jira devolve, para conferir com o board no navegador. Nunca imprime o token.
enum JiraDump {
    static func run() async -> Int32 {
        let credentials = Credentials.load()
        guard credentials.jiraReady else { print("sem credenciais do Jira"); return 1 }
        let client = JiraClient(credentials)
        let project = credentials.jiraProject
        do {
            let me = try await client.myself()
            print("eu: \(me.name)")
            let boards = try await client.boards(project: project)
            print("boards: " + boards.map { "\($0.id) \($0.name)" }.joined(separator: " | "))
            if let board = credentials.jiraBoardId ?? boards.first?.id {
                var sprint: Sprint?
                // Kanban (sem sprint) responde com erro do servidor, como no JiraStore: vira "nenhuma".
                do { sprint = try await client.activeSprint(board: board) } catch APIError.server(_) {}
                print("sprint ativa (board \(board)): \(sprint?.name ?? "nenhuma") fim \(sprint?.endDate.map { "\($0)" } ?? "?")")
                let ids = try await client.columnStatusIds(board: board), names = try await client.statusNames()
                print("colunas: \(ids.map { $0.compactMap { names[$0] } })")
            }
            let mine = try await client.search(JQL.mine(project))
            let free = try await client.search(JQL.free(project))
            print("meus: \(mine.count) \(mine.prefix(5).map(\.key))")
            print("livres: \(free.count) \(free.prefix(5).map(\.key)), grupos: \(groupFree(free).count)")
            return 0
        } catch {
            print("erro: \((error as? APIError)?.userMessage ?? "\(error)")")
            return 1
        }
    }
}
