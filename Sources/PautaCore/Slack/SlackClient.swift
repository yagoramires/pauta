import Foundation

/// Cliente da Web API do Slack com user token (`xoxp-`). Chamadas POST form-encoded com `Authorization: Bearer`.
/// Mantém em memória caches e o rodízio de DMs; as chamadas async rodam fora do main actor e podem se
/// sobrepor, então todo o estado mutável só se mexe com a trava.
final class SlackClient {
    typealias Info = (lastRead: SlackTS?, latest: SlackTS?, name: String?)
    typealias IM = (id: String, userId: String?, isMPIM: Bool)
    /// Uma rodada: candidatos, `last_read` por canal e por thread (`slackThreadKey`), o usuário e o workspace.
    typealias Round = (items: [SlackItem], lastRead: [String: SlackTS], threadLastRead: [String: SlackTS], me: String, teamId: String)

    static let infoBudget = 40
    static let mentionChannelCap = 20
    static let threadCap = 20
    static let infoTTL: TimeInterval = 60
    static let imsTTL: TimeInterval = 600

    private let token: String
    private let lock = NSLock()
    private var userNames: [String: String] = [:]
    private var infoCache: [String: (info: Info, at: Date)] = [:]
    private var imsCache: (list: [IM], at: Date)?
    private var identity: (userId: String, teamId: String, teamURL: URL)?
    /// Último `latest` visto por DM: dá prioridade às conversas mais ativas.
    private var latestKnown: [String: SlackTS] = [:]
    private var rotation = 0
    private var nextAllowed: Date?
    /// Não lidas e `last_read` da última vez que cada DM foi consultada: a DM fora do rodízio desta rodada não some da lista.
    private var dmItems: [String: [SlackItem]] = [:]
    private var dmLastRead: [String: SlackTS] = [:]

    init(token: String) { self.token = token }

    private func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }

    // MARK: - HTTP

    private static let formAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Chama um método da API e confere `ok`. Qualquer falha que não seja `APIError` (JSON) vira erro genérico.
    private func call(_ method: String, _ params: [String: String] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? "")"
        }.joined(separator: "&").utf8)
        let data = try await HTTP.send(request)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw APIError.server("resposta inesperada do Slack")
        }
        if let error = slackError(json) { throw error }
        return json
    }

    private static func ts(_ any: Any?) -> SlackTS? {
        if let text = any as? String, !text.isEmpty { return SlackTS(text) }
        return ((any as? [String: Any])?["ts"] as? String).map(SlackTS.init)
    }

    // MARK: - Endpoints

    func authTest() async throws -> (userId: String, teamId: String, teamURL: URL) {
        let json = try await call("auth.test")
        guard let userId = json["user_id"] as? String, let teamId = json["team_id"] as? String,
              let url = (json["url"] as? String).flatMap(URL.init(string:))
        else { throw APIError.server("resposta inesperada do Slack") }
        locked { identity = (userId, teamId, url) }
        return (userId, teamId, url)
    }

    /// DMs e grupos de DM (paginado). Guarda a lista no cache de 10 min.
    func ims() async throws -> [IM] {
        var result: [IM] = []
        var cursor = ""
        repeat {
            var params = ["types": "im,mpim", "limit": "200", "exclude_archived": "true"]
            if !cursor.isEmpty { params["cursor"] = cursor }
            let json = try await call("users.conversations", params)
            for channel in json["channels"] as? [[String: Any]] ?? [] {
                guard let id = channel["id"] as? String else { continue }
                result.append((id, channel["user"] as? String, channel["is_mpim"] as? Bool ?? false))
            }
            cursor = (json["response_metadata"] as? [String: Any])?["next_cursor"] as? String ?? ""
        } while !cursor.isEmpty
        locked { imsCache = (result, Date()) }
        return result
    }

    func info(_ channel: String) async throws -> Info {
        let json = try await call("conversations.info", ["channel": channel])
        guard let object = json["channel"] as? [String: Any] else { throw APIError.server("resposta inesperada do Slack") }
        let info: Info = (Self.ts(object["last_read"]), Self.ts(object["latest"]), object["name"] as? String)
        locked {
            infoCache[channel] = (info, Date())
            if let latest = info.latest { latestKnown[channel] = latest }
        }
        return info
    }

    /// Mensagens novas depois de `after`. Ficam de fora as com `subtype` (menos `file_share`/`thread_broadcast`) e as minhas.
    func history(_ channel: String, after: SlackTS) async throws -> [SlackItem] {
        let json = try await call("conversations.history", ["channel": channel, "oldest": after.raw, "limit": "50"])
        let me = locked { identity?.userId }
        var items: [SlackItem] = []
        for message in json["messages"] as? [[String: Any]] ?? [] {
            guard slackKeepsSubtype(message["subtype"] as? String), let ts = message["ts"] as? String,
                  let user = message["user"] as? String, user != me else { continue }
            items.append(SlackItem(channel: channel, ts: SlackTS(ts), threadTs: Self.ts(message["thread_ts"]), userId: user,
                                   userName: try await displayName(user), text: try await clean(message["text"] as? String ?? ""),
                                   isDM: true, channelName: nil, permalink: nil))
        }
        return items
    }

    /// `last_read` da thread (`conversations.replies` com `ts` = mãe e `limit=1`); nil quando o usuário não segue a thread.
    func threadLastRead(_ channel: String, thread: SlackTS) async throws -> SlackTS? {
        slackThreadLastRead(try await call("conversations.replies", ["channel": channel, "ts": thread.raw, "limit": "1"]))
    }

    func mentions(of userId: String) async throws -> [SlackItem] {
        let json = try await call("search.messages", ["query": "<@\(userId)>", "sort": "timestamp", "sort_dir": "desc", "count": "50"])
        var items: [SlackItem] = []
        let matches = (json["messages"] as? [String: Any])?["matches"] as? [[String: Any]] ?? []
        for match in matches {
            guard slackKeepsSubtype(match["subtype"] as? String), let channel = match["channel"] as? [String: Any], let channelId = channel["id"] as? String,
                  let ts = match["ts"] as? String, let user = match["user"] as? String else { continue }
            let permalink = (match["permalink"] as? String).flatMap(URL.init(string:))
            let isDM = (channel["is_im"] as? Bool ?? false) || (channel["is_mpim"] as? Bool ?? false)
            items.append(SlackItem(channel: channelId, ts: SlackTS(ts),
                                   threadTs: Self.ts(match["thread_ts"]) ?? permalink.flatMap(threadFromPermalink),
                                   userId: user, userName: try await displayName(user), text: try await clean(match["text"] as? String ?? ""),
                                   isDM: isDM, channelName: isDM ? nil : channel["name"] as? String, permalink: permalink))
        }
        return items
    }

    func userName(_ id: String) async throws -> String {
        if let cached = locked({ userNames[id] }) { return cached }
        let json = try await call("users.info", ["user": id])
        let user = json["user"] as? [String: Any]
        let profile = user?["profile"] as? [String: Any]
        let name = [profile?["display_name"], profile?["real_name"], user?["real_name"], user?["name"]]
            .compactMap { $0 as? String }.first { !$0.isEmpty } ?? id
        locked { userNames[id] = name }
        return name
    }

    /// Nome para exibir: um usuário que não resolve (bot, conta apagada) cai no id; só limite e token ruim interrompem.
    private func displayName(_ id: String) async throws -> String {
        do { return try await userName(id) } catch let error as APIError {
            if error == .unauthorized || isRateLimited(error) { throw error }
            return id
        }
    }

    /// Texto sem a marcação do Slack; os nomes citados vêm do cache de usuários (id sem nome vira "@alguém").
    private func clean(_ text: String) async throws -> String {
        let me = locked { identity?.userId }
        var names: [String: String] = [:]
        for id in Set(mentionedUserIds(text)) where id != me {
            let name = try await displayName(id)
            if name != id { names[id] = name }
        }
        return cleanSlackText(text, me: me, name: { names[$0] })
    }

    private func isRateLimited(_ error: APIError) -> Bool {
        if case .rateLimited = error { return true }
        return false
    }

    // MARK: - Rodada

    private func cachedInfo(_ channel: String) async throws -> Info {
        if let hit = locked({ infoCache[channel] }), Date().timeIntervalSince(hit.at) < Self.infoTTL { return hit.info }
        return try await info(channel)
    }

    private func cachedIMs() async throws -> [IM] {
        if let hit = locked({ imsCache }), Date().timeIntervalSince(hit.at) < Self.imsTTL { return hit.list }
        return try await ims()
    }

    /// Ponto de entrada de cada atualização: junta menções (busca) e DMs (rodízio) e devolve candidatos, o `last_read`
    /// por canal e por thread de menção, o id do usuário e do workspace. Quem chama aplica `unreadItems(...)`.
    /// Limite de requisições: depois de um `.rateLimited`, lança o mesmo erro sem rede até passar o `retryAfter`.
    /// Se o limite estourar no meio das DMs, devolve o que já juntou; antes disso (auth, menções), lança.
    func fetchCandidates() async throws -> Round {
        if let until = locked({ nextAllowed }), until > Date() {
            throw APIError.rateLimited(retryAfter: Int(until.timeIntervalSinceNow.rounded(.up)))
        }
        do {
            return try await round()
        } catch let error as APIError {
            if case .rateLimited(let seconds) = error { locked { nextAllowed = Date().addingTimeInterval(TimeInterval(seconds)) } }
            throw error
        }
    }

    private func round() async throws -> Round {
        let who: (userId: String, teamId: String, teamURL: URL)
        if let known = locked({ identity }) { who = known } else { who = try await authTest() }

        var lastRead: [String: SlackTS] = [:]
        // shortcut: só os 20 canais de menção mais recentes têm `info`; menções mais antigas ficam de fora; subir o teto se faltar menção.
        var mentionItems: [SlackItem] = []
        var mentionChannels: [String] = []
        for item in try await mentions(of: who.userId) {
            if !mentionChannels.contains(item.channel) {
                guard mentionChannels.count < Self.mentionChannelCap else { continue }
                mentionChannels.append(item.channel)
            }
            mentionItems.append(item)
        }
        var names: [String: String] = [:]
        for channel in mentionChannels {
            do {
                let info = try await cachedInfo(channel)
                if let read = info.lastRead { lastRead[channel] = read }
                if let name = info.name { names[channel] = name }
            } catch let error as APIError {
                if error == .unauthorized || isRateLimited(error) { throw error }
                // Canal sem `info` (sem acesso): a menção fica sem `last_read`, então conta como não lida.
            }
        }
        mentionItems = mentionItems.map { var item = $0; item.channelName = item.channelName ?? names[item.channel]; return item }

        // Menção numa resposta de thread: o lido que vale é o da thread, não o do canal. Uma chamada por thread por rodada.
        // shortcut: só as 20 threads mais recentes; as outras usam o `last_read` do canal; subir o teto se sobrar menção lida.
        var threadReads: [String: SlackTS] = [:]
        var threads: [(channel: String, thread: SlackTS)] = []
        for item in mentionItems {
            guard let thread = item.threadTs, thread != item.ts, threads.count < Self.threadCap,
                  !threads.contains(where: { $0.channel == item.channel && $0.thread == thread }) else { continue }
            threads.append((item.channel, thread))
        }
        for (channel, thread) in threads {
            do {
                if let read = try await threadLastRead(channel, thread: thread) { threadReads[slackThreadKey(channel, thread)] = read }
            } catch let error as APIError {
                if error == .unauthorized || isRateLimited(error) { throw error }
                // Thread sem acesso ou apagada: fica com o `last_read` do canal.
            }
        }

        var stoppedBy: APIError?
        do {
            let all = try await cachedIMs()
            let ids = Set(all.map(\.id))
            locked { dmItems = dmItems.filter { ids.contains($0.key) }; dmLastRead = dmLastRead.filter { ids.contains($0.key) } }
            let picked = locked { () -> [IM] in
                let withUnread = Set(dmItems.filter { !$0.value.isEmpty }.keys)
                let pick = pickIMs(all: all.map(\.id), latestKnown: latestKnown, withUnread: withUnread,
                                        cursor: rotation, budget: Self.infoBudget - mentionChannels.count)
                rotation = pick.cursor
                return pick.ids.compactMap { id in all.first { $0.id == id } }
            }
            for im in picked {
                do {
                    let info = try await cachedInfo(im.id)
                    guard let read = info.lastRead else { locked { dmItems[im.id] = nil }; continue }
                    var unread: [SlackItem] = []
                    // shortcut: respostas em thread de DM sem menção não são rastreadas no v1 (só entram se a thread aparecer no
                    // history); se fizer falta, usar conversations.replies nas threads com latest_reply > last_read.
                    if info.latest.map({ $0 > read }) ?? true { unread = try await history(im.id, after: read) }
                    locked { dmLastRead[im.id] = read; dmItems[im.id] = unread }
                } catch let error as APIError {
                    if error == .unauthorized || isRateLimited(error) { throw error }
                    // DM que falhou sozinha (ex.: conta desativada): segue para a próxima.
                }
            }
        } catch let error as APIError {
            guard isRateLimited(error) else { throw error }
            stoppedBy = error
        }
        if case .rateLimited(let seconds)? = stoppedBy { locked { nextAllowed = Date().addingTimeInterval(TimeInterval(seconds)) } }

        let (dms, dmReads) = locked { (dmItems.values.flatMap { $0 }, dmLastRead) }
        lastRead.merge(dmReads) { mention, _ in mention }
        return (mentionItems + dms, lastRead, threadReads, who.userId, who.teamId)
    }
}

/// `Pauta --dump slack`: o que o Slack devolve, para conferir com o app. Nunca imprime o token.
enum SlackDump {
    static func run() async -> Int32 {
        let credentials = Credentials.load()
        guard credentials.slackReady else { print("sem credenciais do Slack"); return 1 }
        let client = SlackClient(token: credentials.slackToken)
        do {
            let ims = try await client.ims()
            let result = try await client.fetchCandidates()
            let mentions = try await client.mentions(of: result.me)
            print("DMs: \(ims.count) (grupos: \(ims.filter(\.isMPIM).count)), menções: \(mentions.count)")
            let unread = unreadItems(result.items, lastRead: result.lastRead, threadLastRead: result.threadLastRead, me: result.me, seen: [])
            print("não lidas: \(unread.count)")
            for item in unread {
                let place = item.isDM ? "DM" : "#\(item.channelName ?? item.channel)"
                print("  \(place) \(item.userName): \(item.text.replacingOccurrences(of: "\n", with: " ").prefix(40))")
            }
            return 0
        } catch {
            print("erro: \((error as? APIError)?.userMessage ?? "\(error)")")
            return 1
        }
    }
}
