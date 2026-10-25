import Foundation

/// Timestamp do Slack ("1712345678.000100"). Compara por (segundos, micros): "….1" e "….100000" são iguais.
struct SlackTS: Comparable, Hashable, Codable {
    let raw: String
    private let seconds: Int
    private let micros: Int

    init(_ raw: String) {
        self.raw = raw
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        seconds = parts.first.flatMap { Int($0) } ?? 0
        // A fração é decimal: completa à direita até 6 dígitos (".1" = 100000 µs).
        let fraction = parts.count > 1 ? String(parts[1].prefix(6)) : ""
        micros = Int(fraction.padding(toLength: 6, withPad: "0", startingAt: 0)) ?? 0
    }

    init(from decoder: Decoder) throws { self.init(try decoder.singleValueContainer().decode(String.self)) }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    static func == (a: SlackTS, b: SlackTS) -> Bool { a.seconds == b.seconds && a.micros == b.micros }
    func hash(into hasher: inout Hasher) { hasher.combine(seconds); hasher.combine(micros) }
    static func < (a: SlackTS, b: SlackTS) -> Bool { (a.seconds, a.micros) < (b.seconds, b.micros) }

    var date: Date { Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(micros) / 1_000_000) }
}

struct SlackItem: Equatable, Identifiable {
    let channel: String
    let ts: SlackTS
    let threadTs: SlackTS?
    let userId: String
    var userName: String
    let text: String
    let isDM: Bool
    var channelName: String?
    let permalink: URL?

    var id: String { "\(channel):\(ts.raw)" }
}

/// Ids de itens que o usuário já dispensou (clicou/marcou como lido no Pauta).
struct Seen: Codable { var ids: Set<String> = [] }

/// Chave de uma thread em `threadLastRead`: "canal:ts da mãe".
func slackThreadKey(_ channel: String, _ thread: SlackTS) -> String { "\(channel):\(thread.raw)" }

/// O `last_read` da thread que `conversations.replies` põe na mensagem-mãe (a primeira); só vem para quem segue a thread.
func slackThreadLastRead(_ json: [String: Any]) -> SlackTS? {
    ((json["messages"] as? [[String: Any]])?.first?["last_read"] as? String).flatMap { $0.isEmpty ? nil : SlackTS($0) }
}

/// O que é de outra pessoa, ainda não dispensado e mais novo que o último lido (sem ele, fica). Resposta em thread
/// compara com o `last_read` da thread quando ele é conhecido, senão com o do canal.
/// Do mais novo para o mais antigo. O mesmo id (menção dentro de DM vem da busca e do history) aparece uma vez,
/// preferindo a cópia com permalink.
func unreadItems(_ candidates: [SlackItem], lastRead: [String: SlackTS], threadLastRead: [String: SlackTS] = [:],
                 me: String, seen: Set<String>) -> [SlackItem] {
    var byId: [String: SlackItem] = [:]
    for item in candidates {
        guard item.userId != me, !seen.contains(item.id) else { continue }
        let thread = item.threadTs.flatMap { $0 == item.ts ? nil : threadLastRead[slackThreadKey(item.channel, $0)] }
        if let read = thread ?? lastRead[item.channel], item.ts <= read { continue }
        if byId[item.id] == nil || (byId[item.id]?.permalink == nil && item.permalink != nil) { byId[item.id] = item }
    }
    return byId.values.sorted { $0.ts > $1.ts }
}

/// Mensagens com `subtype` são ruído (entrou no canal, bot de sistema), menos anexo e resposta enviada também ao canal.
func slackKeepsSubtype(_ subtype: String?) -> Bool {
    subtype == nil || subtype == "file_share" || subtype == "thread_broadcast"
}

/// Quais DMs consultar nesta rodada (`info` custa uma chamada cada, o orçamento é `budget`). Primeiro as que já
/// têm não lidas guardadas (para notar que foram lidas no Slack), depois metade do que sobra pelas de `latest`
/// mais recente, e o resto em rodízio a partir de `cursor`, para toda DM ser consultada. Devolve o novo cursor.
func pickIMs(all: [String], latestKnown: [String: SlackTS], withUnread: Set<String>, cursor: Int,
             budget: Int) -> (ids: [String], cursor: Int) {
    guard budget > 0 else { return ([], cursor) }
    if all.count <= budget { return (all, cursor) }
    func byLatest(_ ids: [String]) -> [String] {
        ids.filter { latestKnown[$0] != nil }.sorted { latestKnown[$0]! > latestKnown[$1]! }
    }
    let pending = Array((byLatest(all.filter(withUnread.contains)) + all.filter { withUnread.contains($0) && latestKnown[$0] == nil })
        .prefix(budget))
    let others = all.filter { !pending.contains($0) }
    let left = budget - pending.count
    let recent = Array(byLatest(others).prefix(left / 2))
    let rest = others.filter { !recent.contains($0) }
    let take = min(left - recent.count, rest.count)
    guard take > 0 else { return (pending + recent, cursor) }
    let start = cursor % rest.count
    return (pending + recent + (0..<take).map { rest[(start + $0) % rest.count] }, (start + take) % rest.count)
}

/// O Slack responde 200 mesmo com erro: `ok:false` e o motivo em `error`.
func slackError(_ json: [String: Any]) -> APIError? {
    guard json["ok"] as? Bool != true else { return nil }
    let error = json["error"] as? String ?? "resposta inesperada do Slack"
    switch error {
    case "invalid_auth", "token_revoked", "not_authed", "account_inactive": return .unauthorized
    case "ratelimited": return .rateLimited(retryAfter: 30)
    default: return .server(error)
    }
}

/// O permalink de uma resposta em thread traz `?thread_ts=…`; a busca não devolve esse campo direto.
func threadFromPermalink(_ url: URL) -> SlackTS? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "thread_ts" }?.value.map(SlackTS.init)
}
