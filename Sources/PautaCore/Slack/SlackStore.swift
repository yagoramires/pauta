import AppKit

/// Quais itens já foram avisados por notificação. Na primeira vez (`primed == false`) só aprende o que existe,
/// para não disparar tudo que já estava não lido quando o Pauta foi aberto.
struct NotifyLedger: Codable {
    static let limit = 2000

    var notified: Set<String> = []
    var primed = false

    mutating func fresh(_ items: [SlackItem]) -> [SlackItem] {
        var result: [SlackItem] = []
        for item in items where notified.insert(item.id).inserted { result.append(item) }
        if notified.count > Self.limit {
            // Descarta os mais antigos por ts.
            let oldest = notified.sorted { idTS($0) < idTS($1) }.prefix(notified.count - Self.limit)
            notified.subtract(oldest)
        }
        defer { primed = true }
        return primed ? result : []
    }
}

/// O id de um item é "canal:ts".
private func idTS(_ id: String) -> SlackTS { SlackTS(id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "") }

/// Vistos mais antigos que isso saem do arquivo, a não ser que a busca ainda os devolva (senão voltariam à lista).
func pruneSeen(_ ids: Set<String>, keeping candidates: Set<String>, now: Date, maxAge: TimeInterval = 14 * 86400) -> Set<String> {
    ids.filter { candidates.contains($0) || now.timeIntervalSince(idTS($0).date) <= maxAge }
}

/// Com o app do Slack instalado, o deep link `slack://` (abre direto no app); sem ele, o `permalink` (navegador) ou,
/// sem permalink (DM vinda do history), o cliente web na conversa.
// shortcut: resposta de thread abre no canal, não na thread (falta `thread_ts` no deep link); incluir se incomodar.
func slackOpenURL(permalink: URL?, team: String?, channel: String, ts: String, appInstalled: Bool) -> URL? {
    if !appInstalled { return permalink ?? URL(string: "https://app.slack.com/client" + (team.map { "/\($0)/\(channel)" } ?? "")) }
    var components = URLComponents()
    components.scheme = "slack"
    components.host = "channel"
    components.queryItems = (team.map { [URLQueryItem(name: "team", value: $0)] } ?? [])
        + [URLQueryItem(name: "id", value: channel), URLQueryItem(name: "message", value: ts)]
    return components.url
}

/// "DM" ou "#canal" (canal privado/grupo sem nome conhecido vira "#canal").
func slackPlace(_ item: SlackItem) -> String { item.isDM ? "DM" : "#\(item.channelName ?? "canal")" }

func notificationTitle(_ item: SlackItem) -> String {
    item.isDM ? "\(item.userName) · DM" : "\(item.userName) em \(slackPlace(item))"
}

func relativeTime(_ date: Date, now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    return seconds < 60 ? "agora" : seconds < 3600 ? "\(seconds / 60) min" : seconds < 86400 ? "\(seconds / 3600) h" : "\(seconds / 86400) d"
}

/// O que sobrevive entre aberturas do app: vistos, ledger de notificações e o workspace a que pertencem.
struct SlackState: Codable {
    var seen = Seen()
    var ledger = NotifyLedger()
    var teamId: String?
    /// Quando o ledger aprendeu o que já existia: nada anterior a isso é "novo" para notificar.
    var primedAt: Date?
}

/// Só avisa o que chegou depois de o ledger ser iniciado e há pouco: DMs antigas reveladas pelo rodízio entram no
/// ledger, mas não viram uma rajada de notificações velhas.
let notifyMaxAge: TimeInterval = 15 * 60

/// Tira a marcação do Slack do texto: menções, canais, links e escapes. `name` resolve ids de usuário (nil = desconhecido).
func cleanSlackText(_ text: String, me: String?, name: (String) -> String?) -> String {
    guard let regex = try? NSRegularExpression(pattern: "<([^<>]+)>") else { return text }
    var result = text as NSString
    for match in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
        let inner = result.substring(with: match.range(at: 1))
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let target = parts[0], label = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
        let replacement: String
        switch target.first {
        case "@":
            let id = String(target.dropFirst())
            replacement = id == me ? "@você" : "@" + (name(id) ?? label ?? "alguém")
        case "#": replacement = "#" + (label ?? "canal")
        case "!":
            let word = String(target.dropFirst())
            replacement = ["here", "channel", "everyone"].contains(word) ? "@" + word : (label ?? "@" + (word.split(separator: "^").first.map(String.init) ?? word))
        default: replacement = label ?? target
        }
        result = result.replacingCharacters(in: match.range, with: replacement) as NSString
    }
    return (result as String).replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
}

/// Ids de usuário citados no texto (`<@U123>`), para o cliente resolver os nomes.
func mentionedUserIds(_ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "<@([A-Z0-9]+)") else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
}

/// Estado do popover do Slack: não lidas, erro e o que já foi visto/notificado. A UI só lê; as ações passam por aqui.
@MainActor
final class SlackStore: ObservableObject {
    @Published var items: [SlackItem] = []
    @Published var error: APIError?
    /// Aviso leve (ex.: esperando o limite do Slack); não é erro, a lista antiga continua valendo.
    @Published var notice: String?
    @Published var updatedAt: Date?
    /// Já houve uma busca com sucesso (distingue "carregando" de "nada novo").
    @Published var loaded = false
    /// Sem credenciais o popover mostra os ajustes.
    @Published var configured: Bool

    nonisolated static let defaultStateURL = AppPaths.real.slackState

    var unreadCount: Int { items.count }
    var seenIds: Set<String> { state.seen.ids }
    /// Quem notifica: o app passa `Notifier.postIfSlackClosed`; selftest e snapshots passam um gravador/nada,
    /// para nunca chegarem ao UNUserNotificationCenter.
    private let notify: ([SlackItem]) -> Void

    private var client: SlackClient?
    private var token = ""
    private var state: SlackState
    private let stateURL: URL
    /// Muda ao reconfigurar: uma busca iniciada antes disso é descartada.
    private var epoch = 0
    private var inflight: Task<Void, Never>?
    /// Abrir link e achar o app do Slack; o selftest troca os dois (nunca abre nada de verdade).
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var slackApp: () -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Notifier.slackBundleId) }

    init(client: SlackClient?, stateURL: URL = SlackStore.defaultStateURL, notify: @escaping ([SlackItem]) -> Void) {
        self.client = client
        self.notify = notify
        self.stateURL = stateURL
        configured = client != nil
        state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(SlackState.self, from: $0) } ?? SlackState()
    }

    /// Depois de salvar os ajustes: se o token mudou, cliente novo e a lista some. Token igual não mexe em nada.
    func reconfigure(_ c: Credentials) {
        guard c.slackToken != token else { return }
        token = c.slackToken
        client = c.slackReady ? SlackClient(token: c.slackToken) : nil
        configured = client != nil
        epoch += 1
        inflight = nil
        items = []; error = nil; notice = nil; updatedAt = nil; loaded = false
    }

    /// Uma busca por vez (`fetchCandidates` não tem guarda própria): quem chama no meio dela só espera por ela.
    func refresh() async {
        guard client != nil else { return }
        if let running = inflight { return await running.value }
        let version = epoch
        let task = Task { await load(); if epoch == version { inflight = nil } }
        inflight = task
        await task.value
    }

    private func load() async {
        guard let client else { return }
        let ticket = epoch
        do {
            let result = try await client.fetchCandidates()
            guard epoch == ticket else { return }
            ingest(result)
        } catch {
            guard epoch == ticket else { return }
            fail(error)
        }
    }

    /// Aplica o resultado de uma busca: calcula as não lidas, atualiza o ledger (sempre) e só então decide notificar.
    func ingest(_ result: SlackClient.Round, now: Date = Date()) {
        // Outro workspace: ids e vistos antigos não valem, recomeça (rodada silenciosa).
        if let known = state.teamId, known != result.teamId { state = SlackState() }
        state.teamId = result.teamId
        state.seen.ids = pruneSeen(state.seen.ids, keeping: Set(result.items.map(\.id)), now: now)
        let unread = unreadItems(result.items, lastRead: result.lastRead, threadLastRead: result.threadLastRead,
                                 me: result.me, seen: state.seen.ids)
        let wasPrimed = state.ledger.primed
        let new = state.ledger.fresh(unread)
        if !wasPrimed { state.primedAt = now }
        // O ledger guarda todos; só notifica o que é mais novo que o priming e que 15 min atrás.
        let cutoff = max(state.primedAt ?? .distantPast, now.addingTimeInterval(-notifyMaxAge))
        let toPost = new.filter { $0.ts.date > cutoff }
        saveState()
        items = unread
        error = nil; notice = nil; updatedAt = now; loaded = true
        if !toPost.isEmpty { notify(toPost) }
    }

    /// Clicar no item (ou na notificação) abre no Slack e o marca como visto.
    func open(_ item: SlackItem) { openLink(channel: item.channel, ts: item.ts.raw, permalink: item.permalink) }

    /// Só marca como visto quando há o que abrir: senão o item sumiria sem o usuário ter visto a mensagem.
    func openLink(channel: String?, ts: String?, permalink: URL?) {
        guard let channel, let ts else { return openSlack() }
        guard let url = slackOpenURL(permalink: permalink, team: state.teamId, channel: channel, ts: ts, appInstalled: slackApp() != nil)
        else { return }
        let id = "\(channel):\(ts)"
        if let item = items.first(where: { $0.id == id }) { dismiss(item) } else { markSeen([id]) }
        open(url)
    }

    /// Abrir o .app pelo `open` é o mesmo que `openApplication`.
    func openSlack() {
        if let app = slackApp() { open(app) }
    }

    func dismiss(_ item: SlackItem) {
        markSeen([item.id])
        items.removeAll { $0.id == item.id }
    }

    /// "Marcar tudo como visto": só as mensagens que a tela mostra (menções escondidas pelo ajuste ficam).
    func markSeen(_ shown: [SlackItem]) {
        let ids = Set(shown.map(\.id))
        markSeen(ids)
        items.removeAll { ids.contains($0.id) }
    }

    private func markSeen(_ ids: Set<String>) {
        state.seen.ids.formUnion(ids)
        saveState()
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        Credentials.writePrivately(data, to: stateURL, what: "estado do slack")
    }

    /// Limite do Slack mantém a lista antiga e só avisa; qualquer outra falha (inclusive JSON diferente do esperado) vira erro.
    private func fail(_ e: Error) {
        debugLog("slack: \(e)")
        if case .rateLimited(let seconds)? = e as? APIError {
            notice = "Slack pediu pra esperar, tentando de novo em \(seconds) s"
            return
        }
        error = e as? APIError ?? .server("resposta inesperada do Slack")
        notice = nil
    }
}
