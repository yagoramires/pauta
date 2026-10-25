import Foundation

/// Tokens do Jira e do Slack, num JSON em ~/Library/Application Support/Pauta com permissão só do
/// usuário (0600). Nunca no Keychain (com certificado local o macOS pediria a senha a cada build).
struct Credentials: Codable, Equatable {
    var jiraSite: String = ""
    var jiraEmail: String = ""
    var jiraToken: String = ""
    var jiraProject: String = ""
    var jiraBoardId: Int?
    var slackToken: String = ""

    static var url = AppPaths.support.appendingPathComponent("credentials.json")

    static func load() -> Credentials {
        guard let data = try? Data(contentsOf: url) else { return Credentials() }
        return (try? JSONDecoder().decode(Credentials.self, from: data)) ?? Credentials()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.writePrivately(data, to: Self.url, what: "credenciais")
    }

    /// Diretório 0700 e arquivo 0600, gravados de forma atômica (também usado pelo estado do Slack).
    static func writePrivately(_ data: Data, to url: URL, what: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                     attributes: [.posixPermissions: 0o700])
        // Escreve num temporário e troca, para outro processo nunca ler um arquivo pela metade.
        let temp = url.appendingPathExtension("tmp")
        guard manager.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            return debugLog("\(what): não consegui gravar")
        }
        _ = try? manager.replaceItemAt(url, withItemAt: temp)
        if !manager.fileExists(atPath: url.path) { try? manager.moveItem(at: temp, to: url) }
    }

    /// Valores colados costumam vir com espaço ou quebra de linha no fim.
    func trimmed() -> Credentials {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result = self
        result.jiraSite = clean(jiraSite); result.jiraEmail = clean(jiraEmail); result.jiraToken = clean(jiraToken)
        result.jiraProject = clean(jiraProject); result.slackToken = clean(slackToken)
        return result
    }

    var jiraReady: Bool { !jiraSite.isEmpty && !jiraEmail.isEmpty && !jiraToken.isEmpty }
    var slackReady: Bool { !slackToken.isEmpty }

    var jiraAuthorization: String {
        "Basic " + Data("\(jiraEmail):\(jiraToken)".utf8).base64EncodedString()
    }

    /// Site digitado sem "https://" ou com "/" no fim também vale; só https (o Basic e-mail:token não vai em texto puro).
    var jiraBase: URL? { Self.jiraBase(site: jiraSite) }

    static func jiraBase(site: String) -> URL? {
        var site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if !site.contains("://") { site = "https://" + site }
        while site.hasSuffix("/") { site.removeLast() }
        guard let url = URL(string: site), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Mesmo Jira (site, usuário, token, projeto e board)? Mudou só o Slack, o Jira não precisa recomeçar.
    func sameJira(as other: Credentials) -> Bool {
        jiraSite == other.jiraSite && jiraEmail == other.jiraEmail && jiraToken == other.jiraToken
            && jiraProject == other.jiraProject && jiraBoardId == other.jiraBoardId
    }

    /// Aplica por cima de `current` (o que está no disco agora) só os campos que `edited` mudou em relação a `base`
    /// (o que a tela carregou). Assim um formulário aberto há tempo não apaga o que outro popover gravou.
    static func merged(base: Credentials, edited: Credentials, over current: Credentials) -> Credentials {
        var result = current
        func apply<T: Equatable>(_ key: WritableKeyPath<Credentials, T>) {
            if edited[keyPath: key] != base[keyPath: key] { result[keyPath: key] = edited[keyPath: key] }
        }
        apply(\.jiraSite); apply(\.jiraEmail); apply(\.jiraToken); apply(\.jiraProject)
        apply(\.jiraBoardId); apply(\.slackToken)
        return result
    }
}
