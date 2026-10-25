import AppKit

/// Testes sem XCTest (só CommandLineTools): `Pauta --selftest` roda tudo e imprime "selftest ok".
enum SelfTest {
    static func run() {
        apiErrorMapping()
        credentialsRoundTrip()
        jqlStrings()
        groupFreeCases()
        daysLeftCases()
        issueDecoding()
        freeStillFreeCases()
        transitionNotices()
        tsOrdering()
        unreadFilter()
        slackErrorMapping()
        retryAfterParsed()
        threadFromPermalinkCase()
        dedupeAndSubtypes()
        pickIMsCases()
        notifierFirstRunIsSilent()
        seenRemovesItem()
        notifyAgeGuard()
        cleanText()
        seenPruning()
        slackTexts()
        pollerAndSettingsRules()
        tokenPatterns()
        connectInputsAndTexts()
        slackManifestLink()
        MainActor.assumeIsolated { tokenCatcherPoll() }
        pullRequestDecoding()
        githubStoreFlow()
        barSegmentRules()
        legacyFolderMigration()
        highlightRules()
        MainActor.assumeIsolated { prefsRules() }
        filterRules()
        MainActor.assumeIsolated { jiraStoreRules() }
    }

    /// Falha ao carregar transições não vira erro do Jira inteiro (faixa e triângulo); a busca da sprint pede 1 card só.
    @MainActor private static func jiraStoreRules() {
        let move = Transition(id: "21", name: "Fazer", toStatus: "Em andamento")
        let broken = JiraStore(client: nil, transitions: { _ in throw APIError.server("boom") })
        precondition(block { await broken.transitions(for: "X-1") } == nil && broken.error == nil && broken.notice == nil)
        let working = JiraStore(client: nil, transitions: { _ in [move] })
        precondition(block { await working.transitions(for: "X-1") } == [move] && working.error == nil)
        let probe = JiraClient.searchBody(JQL.sprint("ACME"), limit: 1, token: nil)
        precondition(probe["maxResults"] as? Int == 1 && probe["jql"] as? String == JQL.sprint("ACME") && probe["nextPageToken"] == nil)
        let page = JiraClient.searchBody(JQL.mine("ACME"), limit: 100, token: "tok")
        precondition(page["maxResults"] as? Int == 100 && page["nextPageToken"] as? String == "tok")
    }

    private static func issue(_ key: String, status: String = "Tarefas pendentes", category: StatusCategory = .todo,
                              parent: ParentRef? = nil, subtask: Bool = false) -> JiraIssue {
        JiraIssue(key: key, summary: "resumo \(key)", status: status, category: category, assigneeId: nil,
                  parent: parent, isSubtask: subtask)
    }

    private static func filterRules() {
        func jira(_ key: String, _ summary: String, parent: ParentRef? = nil, subtask: Bool = false) -> JiraIssue {
            JiraIssue(key: key, summary: summary, status: "Tarefas pendentes", category: .todo, assigneeId: nil,
                      parent: parent, isSubtask: subtask)
        }
        let dm = SlackItem(channel: "D1", ts: SlackTS("100.1"), threadTs: nil, userId: "U2", userName: "Marina Duarte",
                           text: "O checkout caiu de novo", isDM: true, channelName: nil, permalink: nil)
        let mentionInFrontend = SlackItem(channel: "C1", ts: SlackTS("100.2"), threadTs: nil, userId: "U3", userName: "Rafael Lima",
                                          text: "oi", isDM: false, channelName: "frontend", permalink: nil)
        let pr4821 = PullRequest(repo: "o/web-app", number: 4821, title: "Ajusta layout do menu", author: "marina-duarte",
                                 updatedAt: Date(timeIntervalSince1970: 0), url: URL(string: "https://github.com/o/r/pull/4821")!, draft: false)
        let issue1287 = jira("ACME-1287", "Botão de voltar some no checkout")
        let free1 = jira("ACME-1300", "Erro 500 no checkout sem cupom")
        let sub1 = jira("ACME-1301", "Ajustar cupom", parent: ParentRef(key: "ACME-1300", summary: free1.summary), subtask: true)
        let orphanSub = jira("ACME-1400", "Trocar ícones do menu lateral", parent: ParentRef(key: "ACME-1399", summary: "Menu"), subtask: true)

        precondition(matches("BOTAO", ["Botão de voltar some no checkout"]))
        precondition(matches("checkout botão", ["Botão de voltar some no checkout"]))
        precondition(!matches("checkout cupom", ["Botão de voltar some no checkout"]))
        precondition(matches("  ", ["qualquer"]))
        precondition(matches("frontend", searchFields(mentionInFrontend)))
        precondition(matches("4821", searchFields(pr4821)) && matches("marina", searchFields(pr4821)))
        precondition(matches("acme-1287", searchFields(issue1287)))
        let v = visibleItems(slack: [dm, mentionInFrontend], prs: [pr4821], mine: [issue1287], free: [free1, sub1],
                             prefs: Prefs(), query: "checkout")
        precondition(v.slack == [dm] && v.prs.isEmpty && v.mine == [issue1287] && v.free == [free1])
        precondition(pillCounts(v) == [.all: 3, .slack: 1, .github: 0, .jira: 2])
        var noFree = Prefs(); noFree.freeCards = false
        precondition(visibleItems(slack: [], prs: [], mine: [], free: [free1], prefs: noFree, query: "").free.isEmpty)
        var dmsOnly = Prefs(); dmsOnly.channelMentions = false
        precondition(visibleItems(slack: [dm, mentionInFrontend], prs: [], mine: [], free: [], prefs: dmsOnly, query: "").slack == [dm])
        // sub-tarefa livre cujo pai não é livre: o grupo sai com headIssue == nil (título apagado)
        let g = groupFree(visibleItems(slack: [], prs: [], mine: [], free: [orphanSub], prefs: Prefs(), query: "ícones").free)
        precondition(g.count == 1 && g[0].headIssue == nil && g[0].subtasks == [orphanSub])
        let text = "Botão de voltar some no checkout"
        precondition(matchRanges(text, query: "botao").map { String(text[$0]) } == ["Botão"])
        precondition(matchRanges(text, query: "").isEmpty)
        precondition(matchRanges(text, query: "voltar bot").map { String(text[$0]) } == ["Bot", "voltar"]) // ordenado, sem sobreposição
        precondition(clearTitle(.slack) == "Nada no Slack." && clearTitle(.github) == "Nenhum PR esperando você.")
        precondition(clearTitle(.all) == "Ninguém esperando você.")
        precondition(resultsText(1) == "1 resultado" && resultsText(3) == "3 resultados")
        // "Nada com…" só quando todo serviço do filtro está pronto (conectado, carregado, sem erro nem aviso).
        let none: [ServiceFilter: Int] = [.all: 0, .slack: 0, .github: 0, .jira: 0]
        let allReady: Set<ServiceFilter> = [.slack, .github, .jira]
        precondition(showsNoResults(filter: .all, query: "zzz", counts: none, ready: allReady))
        precondition(!showsNoResults(filter: .all, query: "zzz", counts: none, ready: [.github, .jira])) // Slack carregando
        precondition(showsNoResults(filter: .github, query: "zzz", counts: none, ready: [.github]))
        precondition(!showsNoResults(filter: .jira, query: "zzz", counts: none, ready: [.slack, .github])) // Jira com erro
        precondition(!showsNoResults(filter: .all, query: " ", counts: none, ready: allReady))
        precondition(!showsNoResults(filter: .slack, query: "oi", counts: [.slack: 1], ready: allReady))
        // Reticências no começo só quando a linha não cabe.
        let title = "Botão de voltar some no checkout"
        precondition(searchExcerptStart(title, firstMatch: matchRanges(title, query: "checkout").first, budget: 38) == nil)
        let message = "Oi, quando puder dá uma olhada no deploy de ontem, acho que o checkout caiu"
        let cut = searchExcerptStart(message, firstMatch: matchRanges(message, query: "checkout").first, budget: 28)
        precondition(cut.map { String(message[$0...]) } == "acho que o checkout caiu")
        precondition(searchExcerptStart(message, firstMatch: matchRanges(message, query: "oi").first, budget: 28) == nil)
        precondition(searchExcerptStart(message, firstMatch: nil, budget: 28) == nil)
        // "Ver mais": 4 linhas e o resto escondido; na busca tudo à mostra, sem botão.
        let six = Array(1...6)
        precondition(visibleRows(six, showAll: false, query: "") == ([1, 2, 3, 4], 2))
        precondition(visibleRows(six, showAll: true, query: "") == (six, 2))
        precondition(visibleRows(six, showAll: false, query: "x") == (six, 0))
        precondition(visibleRows([1, 2], showAll: false, query: "") == ([1, 2], 0))
    }

    private static func jqlStrings() {
        let sprint = "project = \"ACME\" AND sprint in openSprints()"
        precondition(JQL.sprint("ACME") == sprint && JQL.sprint("") == "sprint in openSprints()")
        precondition(JQL.mine("ACME") == sprint + " AND assignee = currentUser() ORDER BY status, rank")
        precondition(JQL.free("ACME") == sprint + " AND assignee is EMPTY AND statusCategory != Done ORDER BY rank")
        precondition(isClosed(issue("D", status: "Concluído DEV", category: .done)))
        precondition(isClosed(issue("Q", status: "Concluído QA", category: .done)))
        precondition(isClosed(issue("X", status: "Cancelado", category: .inProgress)))
        precondition(!isClosed(issue("E", status: "Em andamento", category: .inProgress)))
    }

    private static func groupFreeCases() {
        let c = ParentRef(key: "C", summary: "resumo C")
        let a = issue("A"), b = issue("B")
        let b1 = issue("B-1", parent: ParentRef(key: "B", summary: "resumo B"), subtask: true)
        let b2 = issue("B-2", parent: ParentRef(key: "B", summary: "resumo B"), subtask: true)
        let c1 = issue("C-1", parent: c, subtask: true)
        // Bug livre com Epic de pai: não é sub-tarefa, então fica sozinho e o Epic não vira grupo.
        let bug = issue("BUG", parent: ParentRef(key: "EPIC", summary: "um epic"))
        let free = [a, b, b1, b2, c1, bug]
        precondition(free.count == 6)
        let groups = groupFree(free)
        precondition(groups.map(\.id) == ["A", "B", "C", "BUG"])
        precondition(groups[0].headIssue == a && groups[0].subtasks.isEmpty)
        precondition(groups[1].headIssue == b && groups[1].subtasks == [b1, b2])
        precondition(groups[2].headIssue == nil && groups[2].head == c && groups[2].subtasks == [c1])
        precondition(groups[3].headIssue == bug && groups[3].subtasks.isEmpty
                     && groups[3].head == ParentRef(key: "BUG", summary: "resumo BUG"))
        // Sub-tarefa vinda antes do pai livre entra no grupo do pai, que mantém a posição da primeira aparição.
        let early = groupFree([b1, a, b])
        precondition(early.map(\.id) == ["B", "A"] && early[0].headIssue == b && early[0].subtasks == [b1])
    }

    private static func freeStillFreeCases() {
        let taken = JiraIssue(key: "T-1", summary: "s", status: "Done", category: .todo, assigneeId: "x", parent: nil, isSubtask: false)
        precondition(!freeStillFree(taken))
        precondition(freeStillFree(issue("T-2")))
    }

    private static func transitionNotices() {
        let fields = "Field 'resolution' is required"
        precondition(transitionFailureNotice(body: fields) == "Essa transição pede campos, abra no Jira")
        precondition(transitionFailureNotice(body: "Transition screen requires input") == "Essa transição pede campos, abra no Jira")
        let soft = "Não foi possível mudar o status, abra no Jira"
        precondition(transitionFailureNotice(body: "Internal Server Error") == soft)
        precondition(transitionFailureNotice(body: "") == soft)
    }

    private static func daysLeftCases() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        precondition(daysLeft(until: date(24, 18), now: date(23, 9), calendar: calendar) == 1)
        precondition(daysLeft(until: date(23, 18), now: date(23, 9), calendar: calendar) == 0)
        precondition(daysLeft(until: date(22, 18), now: date(23, 9), calendar: calendar) == 0)
    }

    private static func issueDecoding() {
        let json = """
        {"issues":[
        {"id":"41136","key":"ACME-9643","fields":{"summary":"Ajustar espaçamento do header","issuetype":{"id":"10003","name":"Subtarefa","subtask":true},"parent":{"id":"40843","key":"ACME-9410","fields":{"summary":"Ajustes de DS - Sprint Puma","status":{"name":"Em andamento","id":"3","statusCategory":{"id":4,"key":"indeterminate"}}}},"status":{"name":"Tarefas pendentes","id":"10083","statusCategory":{"id":2,"key":"new"}},"assignee":null}},
        {"id":"40845","key":"ACME-9412","fields":{"summary":"Erro 500 ao salvar endereço","issuetype":{"id":"10004","name":"Bug","subtask":false},"parent":{"id":"35893","key":"ACME-6558","fields":{"summary":"Correções - 2º trimestre"}},"status":{"name":"Tarefas pendentes","id":"10083","statusCategory":{"id":2,"key":"new"}},"assignee":null}},
        {"id":"39109","key":"ACME-8510","fields":{"summary":"Tarefa de exemplo","issuetype":{"id":"10002","name":"Tarefa","subtask":false},"status":{"name":"Em andamento","id":"3","statusCategory":{"id":4,"key":"indeterminate"}},"assignee":{"accountId":"712020:abc","displayName":"Fulano"}}}
        ],"nextPageToken":"tok","isLast":false}
        """
        let page = try! JiraIssue.decodePage(Data(json.utf8))
        precondition(page.next == "tok" && page.issues.count == 3)
        precondition(page.issues.allSatisfy { $0.sprint == nil })
        // customfield_10020: a sprint ativa vem junto dos cards (as fechadas ficam de fora).
        let sprintJSON = #"{"issues":[{"key":"X-1","fields":{"summary":"s","status":{"id":"1","name":"Doing","statusCategory":{"key":"indeterminate"}},"customfield_10020":[{"id":300,"name":"Sprint Onça","state":"closed","boardId":14,"endDate":"2026-10-13T20:00:00.000Z"},{"id":321,"name":"Sprint Puma","state":"active","boardId":14,"endDate":"2026-10-27T20:00:00.000Z"}]}},{"key":"X-2","fields":{"summary":"s","status":{"id":"1","name":"Doing","statusCategory":{"key":"indeterminate"}},"customfield_10020":null}}]}"#
        let withSprint = try! JiraIssue.decodePage(Data(sprintJSON.utf8)).issues
        let active = withSprint[0].sprint
        precondition(active?.id == 321 && active?.name == "Sprint Puma" && active?.boardId == 14)
        precondition(active?.endDate == ISO8601DateFormatter().date(from: "2026-10-27T20:00:00Z"))
        precondition(withSprint[1].sprint == nil)
        precondition(page.issues[0] == JiraIssue(key: "ACME-9643", summary: "Ajustar espaçamento do header",
                                                 status: "Tarefas pendentes", category: .todo, assigneeId: nil,
                                                 parent: ParentRef(key: "ACME-9410", summary: "Ajustes de DS - Sprint Puma"),
                                                 isSubtask: true))
        // Card comum também tem parent (o Epic), mas não é sub-tarefa.
        precondition(page.issues[1].parent?.key == "ACME-6558" && !page.issues[1].isSubtask)
        precondition(page.issues[2].assigneeId == "712020:abc" && page.issues[2].category == .inProgress
                     && page.issues[2].parent == nil)
        // Uma issue avulsa (GET /issue/{key}) tem o mesmo formato de cada item.
        let single = try! JiraIssue.decode(Data(#"{"key":"X-1","fields":{"summary":"s","status":{"id":"1","name":"Done","statusCategory":{"key":"done"}}}}"#.utf8))
        precondition(single.category == .done && single.assigneeId == nil && !single.isSubtask)
    }

    private static func apiErrorMapping() {
        precondition(HTTP.error(status: 200, headers: [:], body: Data()) == nil)
        precondition(HTTP.error(status: 401, headers: [:], body: Data()) == .unauthorized)
        // 403 do Jira é falta de permissão (assign/transição), não token ruim: mudou de .unauthorized de propósito.
        precondition(HTTP.error(status: 403, headers: [:], body: Data()) == .forbidden)
        precondition(!APIError.forbidden.userMessage.isEmpty && APIError.forbidden != .unauthorized)
        precondition(HTTP.error(status: 429, headers: ["Retry-After": "12"], body: Data()) == .rateLimited(retryAfter: 12))
        precondition(HTTP.error(status: 429, headers: ["retry-after": "7"], body: Data()) == .rateLimited(retryAfter: 7))
        precondition(HTTP.error(status: 429, headers: [:], body: Data()) == .rateLimited(retryAfter: 30))
        precondition(HTTP.error(status: 500, headers: [:], body: Data("falhou".utf8)) == .server("falhou"))
        // O corpo do erro é truncado em 200 caracteres.
        precondition(HTTP.error(status: 502, headers: [:], body: Data(String(repeating: "x", count: 500).utf8))
            == .server(String(repeating: "x", count: 200)))
        precondition(!APIError.unauthorized.userMessage.isEmpty)
    }

    private static func credentialsRoundTrip() {
        precondition(!Credentials().jiraReady && !Credentials().slackReady)
        precondition(Credentials().jiraProject == "")
        let credentials = Credentials(jiraSite: "https://acme.example.com", jiraEmail: "a@b.c", jiraToken: "t",
                                      jiraProject: "ACME", jiraBoardId: 7, slackToken: "xoxp-1")
        precondition(try! JSONDecoder().decode(Credentials.self, from: JSONEncoder().encode(credentials)) == credentials)
        precondition(credentials.jiraReady && credentials.slackReady)
        // Falta o e-mail: ainda não dá pra falar com o Jira.
        var partial = credentials
        partial.jiraEmail = ""
        precondition(!partial.jiraReady)

        // Valores colados com espaço/quebra de linha são aparados antes de gravar.
        let pasted = Credentials(jiraSite: " https://acme.example.com\n", jiraEmail: "a@b.c ", jiraToken: "\tt\n",
                                 jiraProject: " ACME ", jiraBoardId: 7, slackToken: "xoxp-1\n")
        precondition(pasted.trimmed() == credentials)

        // Rascunho velho (sem o token do Slack) não apaga o que outro popover gravou; o que o usuário mudou vale.
        let stale = Credentials(jiraSite: "https://acme.example.com", jiraEmail: "", jiraToken: "")
        var edited = stale
        edited.jiraEmail = "a@b.c"; edited.jiraToken = "t"
        let onDisk = Credentials(jiraSite: stale.jiraSite, slackToken: "xoxp-1")
        let merged = Credentials.merged(base: stale, edited: edited, over: onDisk)
        precondition(merged.slackToken == "xoxp-1" && merged.jiraEmail == "a@b.c" && merged.jiraToken == "t")
        // Apagar um campo de propósito também vale.
        var cleared = onDisk
        cleared.slackToken = ""
        precondition(Credentials.merged(base: onDisk, edited: cleared, over: onDisk).slackToken.isEmpty)

        // Grava de verdade (numa pasta temporária): lê de volta e confere as permissões 0600/0700.
        let saved = Credentials.url
        defer { Credentials.url = saved }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pauta-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        Credentials.url = dir.appendingPathComponent("credentials.json")
        credentials.save()
        precondition(Credentials.load() == credentials)
        func mode(_ url: URL) -> Int { (try! FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue }
        precondition(mode(Credentials.url) == 0o600 && mode(dir) == 0o700)
    }

    private static func pollerAndSettingsRules() {
        let now = Date()
        precondition(isStale(nil, now: now) && isStale(now.addingTimeInterval(-16), now: now))
        precondition(!isStale(now.addingTimeInterval(-14), now: now))
        // Mudar só o Slack não conta como mudança do Jira; qualquer campo do Jira conta.
        let base = Credentials(jiraSite: "https://acme.example.com", jiraEmail: "a@b.c", jiraToken: "t", jiraBoardId: 7, slackToken: "xoxp-1")
        var other = base
        other.slackToken = "xoxp-2"
        precondition(base.sameJira(as: other))
        for change: (inout Credentials) -> Void in [{ $0.jiraSite = "x" }, { $0.jiraEmail = "x" }, { $0.jiraToken = "x" },
                                                   { $0.jiraProject = "X" }, { $0.jiraBoardId = 8 }, { $0.jiraBoardId = nil }] {
            var changed = base
            change(&changed)
            precondition(!base.sameJira(as: changed))
        }
        // Board: um só vale sem perguntar; vários mantêm o escolhido se ainda existir; zero não escolhe nada.
        precondition(boardChoice([(3, "A")], current: nil) == 3 && boardChoice([(3, "A")], current: 9) == 3)
        precondition(boardChoice([(3, "A"), (4, "B")], current: 4) == 4)
        precondition(boardChoice([(3, "A"), (4, "B")], current: 9) == nil && boardChoice([(3, "A"), (4, "B")], current: nil) == nil)
        precondition(boardChoice([], current: 4) == nil)
    }

    private static func tsOrdering() {
        precondition(SlackTS("1712345678.000100") < SlackTS("1712345678.1"))
        precondition(SlackTS("1712345679.000001") > SlackTS("1712345678.999999"))
        precondition(SlackTS("1712345678.1") == SlackTS("1712345678.100000"))
        precondition(Set([SlackTS("1712345678.1"), SlackTS("1712345678.100000")]).count == 1)
        precondition(SlackTS("1712345678").date == Date(timeIntervalSince1970: 1712345678))
    }

    @MainActor
    private static func prefsRules() {
        // Suíte de nome fixo, limpa antes e depois: não deixa um plist novo em ~/Library/Preferences a cada rodada.
        let suite = "pauta-selftest"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        precondition(Prefs.load(d) == Prefs())
        var p = Prefs(); p.channelMentions = false; p.refreshMinutes = 5; p.density = .compact; p.save(d)
        precondition(Prefs.load(d) == p)
        d.set(7, forKey: "prefs.refreshMinutes"); precondition(Prefs.load(d).refreshMinutes == 2)
        // PrefsStore grava a cada mudança.
        d.removePersistentDomain(forName: suite)
        let store = PrefsStore(defaults: d)
        store.prefs.freeCards = false
        precondition(Prefs.load(d).freeCards == false)
        let dm = slackItem("D1", "100.1"), mention = SlackItem(channel: "C1", ts: SlackTS("100.2"), threadTs: nil, userId: "U2",
                                                              userName: "U2", text: "oi", isDM: false, channelName: "geral", permalink: nil)
        precondition(visibleSlack([dm, mention], prefs: Prefs()) == [dm, mention])
        precondition(visibleSlack([dm, mention], prefs: p) == [dm])
        var off = Prefs(); off.slackNotifications = false
        precondition(notifiable([dm, mention], prefs: off).isEmpty)
        precondition(notifiable([dm, mention], prefs: p) == [dm])
        var noFree = Prefs(); noFree.freeCards = false
        // Jira da barra = seus cards + livres (igual à pílula Jira); "Cards livres" desligado tira só os livres.
        precondition(barCounts(slack: [dm, mention], mine: 3, freeCount: 6, prs: 3, prefs: Prefs()) == (2, 9, 3))
        precondition(barCounts(slack: [dm, mention], mine: 3, freeCount: 6, prs: 3, prefs: noFree) == (2, 3, 3))
        precondition(barCounts(slack: [], mine: 0, freeCount: 0, prs: 0, prefs: Prefs()) == (0, 0, 0))
        precondition(barCounts(slack: [dm, mention], mine: 3, freeCount: 6, prs: 3, prefs: p) == (1, 9, 3))
        // O $prefs avisa antes de gravar (willSet): a barra precisa usar o valor recebido, não o `store.prefs`.
        var seen: [(received: Bool, stored: Bool)] = []
        let watch = store.$prefs.dropFirst().sink { seen.append(($0.freeCards, store.prefs.freeCards)) }
        store.prefs.freeCards = true
        watch.cancel()
        precondition(seen.count == 1 && seen[0] == (true, false))
        // Poller: setInterval antes do start só guarda; depois do start troca o timer.
        let poller = Poller(jira: JiraStore(client: nil), slack: SlackStore(client: nil, notify: { _ in }), github: GitHubStore())
        poller.setInterval(minutes: 1)
        precondition(poller.timerInterval == nil)
        poller.start()
        precondition(poller.timerInterval == 60)
        poller.setInterval(minutes: 5)
        precondition(poller.timerInterval == 300)
    }

    private static func highlightRules() {
        precondition(clearSubtitle(slackConnected: true, githubConnected: true) == "Slack e revisões em dia.")
        precondition(clearSubtitle(slackConnected: true, githubConnected: false) == "Slack em dia.")
        precondition(clearSubtitle(slackConnected: false, githubConnected: true) == "Revisões em dia.")
        precondition(clearSubtitle(slackConnected: false, githubConnected: false) == nil)
        let now = Date(timeIntervalSince1970: 1_000_000)
        func slack(_ ts: Double, _ name: String, dm: Bool, channel: String?, thread: Bool = false) -> SlackItem {
            SlackItem(channel: dm ? "D1" : "C1", ts: SlackTS(String(Int(ts)) + ".0"),
                      threadTs: thread ? SlackTS("1.1") : nil, userId: name, userName: name, text: "oi",
                      isDM: dm, channelName: channel, permalink: nil)
        }
        func pull(_ updated: Date) -> PullRequest {
            PullRequest(repo: "o/r", number: 1, title: "t", author: "marina-duarte", updatedAt: updated,
                        url: URL(string: "https://github.com/o/r/pull/1")!, draft: false)
        }
        let t = now.timeIntervalSince1970
        let dm = slack(t - 120, "Marina Duarte", dm: true, channel: nil)
        let ch = slack(t - 1500, "Rafael Lima", dm: false, channel: "frontend")
        let th = slack(t - 7200, "Ana Souza", dm: false, channel: "design-system", thread: true)
        let pr = pull(now.addingTimeInterval(-1500))
        precondition(pickHighlight(slack: [ch, dm], prs: [pr]) == .slack(dm))
        precondition(pickHighlight(slack: [th], prs: [pr]) == .pr(pr))
        precondition(pickHighlight(slack: [], prs: []) == nil)
        precondition(pickHighlight(slack: [ch], prs: [pr]) == .slack(ch)) // empate exato: o Slack vence
        precondition(Highlight.slack(dm).id == dm.id && Highlight.pr(pr).id == pr.id)
        precondition(heroState(slack: nil, prs: nil) == .loading)
        precondition(heroState(slack: nil, prs: [pr]) == .item(.pr(pr)))
        precondition(heroState(slack: [], prs: nil) == .loading)
        precondition(heroState(slack: [], prs: []) == .clear)
        // heroInput: desconectado = []; sem carregar ou falha sem itens = nil (desconhecido); senão os itens.
        precondition(heroInput(connected: false, loaded: false, failed: true, items: [1]) == [])
        precondition(heroInput(connected: true, loaded: false, failed: false, items: [1]) == nil)
        precondition(heroInput(connected: true, loaded: true, failed: true, items: [Int]()) == nil)
        precondition(heroInput(connected: true, loaded: true, failed: true, items: [1]) == [1])
        precondition(heroInput(connected: true, loaded: true, failed: false, items: [Int]()) == [])
        precondition(highlightContext(dm, now: now) == "Marina Duarte, na DM, há 2 min")
        precondition(highlightContext(ch, now: now) == "Rafael Lima, em #frontend, há 25 min")
        precondition(highlightContext(th, now: now) == "Ana Souza, numa thread em #design-system, há 2 h")
        precondition(highlightContext(pr, now: now) == "de marina-duarte, atualizado há 25 min")
        let dmThread = slack(t - 120, "Marina Duarte", dm: true, channel: nil, thread: true)
        precondition(highlightContext(dmThread, now: now) == "Marina Duarte, na DM, há 2 min")
        precondition(highlightContext(slack(t - 120, "Rafael Lima", dm: false, channel: nil), now: now) == "Rafael Lima, em #canal, há 2 min")
        precondition(!isOld(now.addingTimeInterval(-86_400), now: now) && isOld(now.addingTimeInterval(-86_401), now: now))
        precondition(sectionCount(3, highlighted: true) == "mais 3" && sectionCount(2, highlighted: false) == "2")
        precondition(sprintDaysText(0) == "termina hoje" && sprintDaysText(1) == "falta 1 dia" && sprintDaysText(4) == "faltam 4 dias")
        precondition(freeCardsText(1) == "1 card livre no projeto" && freeCardsText(6) == "6 cards livres no projeto")
        precondition(showsSection(connected: false, loaded: false, failed: false, rows: 0))
        precondition(showsSection(connected: true, loaded: false, failed: false, rows: 0))
        precondition(showsSection(connected: true, loaded: true, failed: true, rows: 0))
        precondition(!showsSection(connected: true, loaded: true, failed: false, rows: 0))
        precondition(showsSection(connected: true, loaded: true, failed: false, rows: 1))
    }

    private static func slackItem(_ channel: String, _ ts: String, user: String = "U2") -> SlackItem {
        SlackItem(channel: channel, ts: SlackTS(ts), threadTs: nil, userId: user, userName: user, text: "oi",
                  isDM: true, channelName: nil, permalink: nil)
    }

    private static func unreadFilter() {
        let mine = slackItem("D1", "100.1", user: "ME")
        let seenItem = slackItem("D1", "101.1")
        let old = slackItem("D1", "50.1")
        let equal = slackItem("D1", "90.1")
        let newer = slackItem("D1", "120.1")
        let other = slackItem("D2", "10.1") // canal sem lastRead: fica
        let result = unreadItems([mine, seenItem, old, equal, newer, other], lastRead: ["D1": SlackTS("90.1")],
                                 me: "ME", seen: [seenItem.id])
        precondition(result == [newer, other])
        // Mais novo primeiro, mesmo vindo de canais diferentes.
        let a = slackItem("D1", "200.1"), b = slackItem("D2", "300.1"), c = slackItem("D3", "250.1")
        precondition(unreadItems([a, b, c], lastRead: [:], me: "ME", seen: []) == [b, c, a])
        // Resposta em thread: vale o `last_read` da thread; sem ele, o do canal. A mensagem-mãe usa sempre o do canal.
        func reply(_ ts: String, thread: String = "80.1") -> SlackItem {
            SlackItem(channel: "C1", ts: SlackTS(ts), threadTs: SlackTS(thread), userId: "U2", userName: "U2", text: "oi",
                      isDM: false, channelName: "dev", permalink: nil)
        }
        let threadRead = [slackThreadKey("C1", SlackTS("80.1")): SlackTS("95.1")]
        let atRead = reply("95.1"), afterRead = reply("96.1")
        precondition(unreadItems([atRead, afterRead], lastRead: ["C1": SlackTS("200.1")], threadLastRead: threadRead,
                                 me: "ME", seen: []) == [afterRead])
        let unknownThread = reply("150.1", thread: "140.1")
        precondition(unreadItems([unknownThread], lastRead: ["C1": SlackTS("200.1")], threadLastRead: threadRead, me: "ME", seen: []).isEmpty)
        precondition(unreadItems([unknownThread], lastRead: ["C1": SlackTS("100.1")], threadLastRead: threadRead, me: "ME", seen: []) == [unknownThread])
        let parent = reply("80.1")
        precondition(unreadItems([parent], lastRead: ["C1": SlackTS("70.1")], threadLastRead: [slackThreadKey("C1", SlackTS("80.1")): SlackTS("90.1")],
                                 me: "ME", seen: []) == [parent])
        // `conversations.replies` traz o `last_read` da thread na mensagem-mãe (só para quem segue a thread).
        precondition(slackThreadLastRead(["ok": true, "messages": [["ts": "80.1", "thread_ts": "80.1", "last_read": "95.1", "subscribed": true]]])
                     == SlackTS("95.1"))
        precondition(slackThreadLastRead(["ok": true, "messages": [["ts": "80.1", "thread_ts": "80.1", "subscribed": false]]]) == nil)
        precondition(slackThreadLastRead(["ok": true]) == nil)
    }

    private static func slackErrorMapping() {
        precondition(slackError(["ok": false, "error": "token_revoked"]) == .unauthorized)
        precondition(slackError(["ok": false, "error": "invalid_auth"]) == .unauthorized)
        precondition(slackError(["ok": false, "error": "ratelimited"]) == .rateLimited(retryAfter: 30))
        precondition(slackError(["ok": false, "error": "channel_not_found"]) == .server("channel_not_found"))
        precondition(slackError(["ok": true]) == nil)
    }

    private static func retryAfterParsed() {
        precondition(HTTP.error(status: 429, headers: ["Retry-After": "7"], body: Data()) == .rateLimited(retryAfter: 7))
    }

    private static func threadFromPermalinkCase() {
        let link = "https://x.slack.com/archives/C1/p1712345678000100?thread_ts=1712345600.000200&cid=C1"
        precondition(threadFromPermalink(URL(string: link)!) == SlackTS("1712345600.000200"))
        precondition(threadFromPermalink(URL(string: "https://x.slack.com/archives/C1/p1712345678000100")!) == nil)
    }

    private static func dedupeAndSubtypes() {
        // Menção dentro de DM vem da busca (com permalink) e do history (sem): uma cópia só, a com permalink.
        let link = URL(string: "https://x.slack.com/archives/D1/p1")!
        let fromHistory = slackItem("D1", "100.1")
        let fromSearch = SlackItem(channel: "D1", ts: fromHistory.ts, threadTs: nil, userId: "U2", userName: "U2", text: "oi",
                               isDM: true, channelName: nil, permalink: link)
        for order in [[fromHistory, fromSearch], [fromSearch, fromHistory]] {
            let result = unreadItems(order, lastRead: [:], me: "ME", seen: [])
            precondition(result.count == 1 && result[0].permalink == link)
        }
        precondition(slackKeepsSubtype(nil) && slackKeepsSubtype("file_share") && slackKeepsSubtype("thread_broadcast"))
        precondition(!slackKeepsSubtype("channel_join") && !slackKeepsSubtype("bot_message"))
    }

    private static func pickIMsCases() {
        let all = (1...100).map { "D\($0)" }
        let latest = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1, SlackTS("\(1000 + $0).1")) })
        // DM com não lida guardada entra sempre, mesmo sendo a mais antiga e com orçamento menor que o total.
        let pick = pickIMs(all: all, latestKnown: latest, withUnread: ["D1", "D2"], cursor: 0, budget: 10)
        precondition(pick.ids.count == 10 && pick.ids.contains("D1") && pick.ids.contains("D2"))
        precondition(Set(pick.ids).count == 10)
        // Com mais não lidas que o orçamento, o orçamento manda.
        precondition(pickIMs(all: all, latestKnown: [:], withUnread: Set(all), cursor: 0, budget: 5).ids.count == 5)
        // Rodízio: sem recentes nem não lidas, rodadas seguidas cobrem todas as DMs.
        var cursor = 0, covered = Set<String>()
        for _ in 0..<4 {
            let round = pickIMs(all: all, latestKnown: [:], withUnread: [], cursor: cursor, budget: 25)
            covered.formUnion(round.ids); cursor = round.cursor
        }
        precondition(covered.count == 100)
        precondition(pickIMs(all: ["A", "B"], latestKnown: [:], withUnread: [], cursor: 0, budget: 40).ids == ["A", "B"])
    }
    private static func notifierFirstRunIsSilent() {
        let a = slackItem("D1", "100.1"), b = slackItem("D1", "101.1"), c = slackItem("D1", "102.1")
        var ledger = NotifyLedger()
        precondition(ledger.fresh([a, b]).isEmpty)
        precondition(ledger.fresh([a, b, c]) == [c])
        precondition(ledger.fresh([a, b, c]).isEmpty)
        // Teto de 2000: sobram os mais novos por ts, e os antigos descartados não são esquecidos pela ordem de chegada.
        var big = NotifyLedger()
        _ = big.fresh([a])
        _ = big.fresh((0..<2100).map { slackItem("D2", "\(1000 + $0).1") })
        precondition(big.notified.count == 2000 && big.notified.contains(slackItem("D2", "3099.1").id))
        precondition(!big.notified.contains(a.id) && !big.notified.contains(slackItem("D2", "1000.1").id))
        let again = try! JSONDecoder().decode(NotifyLedger.self, from: JSONEncoder().encode(ledger))
        precondition(again.primed && again.notified == ledger.notified)
    }

    private static func tempState() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pauta-test-\(UUID().uuidString)/slack-state.json")
    }

    private static func fetched(_ items: [SlackItem], team: String = "T1") -> SlackClient.Round {
        (items, [:], [:], "ME", team)
    }

    private static func seenRemovesItem() {
        MainActor.assumeIsolated {
            let url = tempState()
            let a = slackItem("D1", "100.1"), b = slackItem("D1", "101.1"), c = slackItem("D1", "250.1")
            // O notify é sempre um gravador: o selftest nunca chega ao UNUserNotificationCenter.
            var posted: [[SlackItem]] = []
            let store = SlackStore(client: nil, stateURL: url, notify: { posted.append($0) })
            let t1 = Date(timeIntervalSince1970: 200), t2 = Date(timeIntervalSince1970: 300)
            store.ingest(fetched([a, b]), now: t1)
            precondition(posted.isEmpty && store.unreadCount == 2) // primeira rodada é silenciosa
            store.ingest(fetched([a, b, c]), now: t2)
            precondition(posted == [[c]] && store.unreadCount == 3)
            // markSeen só marca o que foi passado (o visível); depois os mesmos ids não voltam, nem depois de reabrir o app.
            store.markSeen([a])
            precondition(Set(store.items.map(\.id)) == [b.id, c.id] && store.seenIds.contains(a.id) && !store.seenIds.contains(b.id))
            store.markSeen(store.items)
            precondition(store.items.isEmpty)
            let all = [a, b, c]
            precondition(unreadItems(all, lastRead: [:], me: "ME", seen: store.seenIds).isEmpty)
            store.ingest(fetched(all), now: t2)
            precondition(store.items.isEmpty && posted.count == 1)
            var posted2: [[SlackItem]] = []
            let reopened = SlackStore(client: nil, stateURL: url, notify: { posted2.append($0) })
            precondition(unreadItems(all, lastRead: [:], me: "ME", seen: reopened.seenIds).isEmpty)
            // open dispensa só aquele item. 0600 no arquivo.
            let d = slackItem("D1", "301.1"), e = slackItem("D1", "302.1")
            reopened.ingest(fetched([d, e]), now: Date(timeIntervalSince1970: 310))
            precondition(posted2.count == 1 && posted2[0].count == 2) // já estava iniciado: os dois são novos
            reopened.dismiss(d)
            precondition(reopened.items == [e] && reopened.seenIds.contains(d.id))
            let mode = (try! FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
            precondition(mode == 0o600)
            // Outro workspace: vistos e ledger recomeçam (rodada silenciosa de novo).
            reopened.ingest(fetched([slackItem("D9", "400.1")], team: "T2"), now: Date(timeIntervalSince1970: 410))
            precondition(posted2.count == 1 && reopened.unreadCount == 1 && reopened.seenIds.isEmpty)
        }
    }

    /// DM antiga revelada depois do priming entra no ledger mas não notifica; só o que chegou depois do priming e há pouco.
    private static func notifyAgeGuard() {
        MainActor.assumeIsolated {
            var posted: [[SlackItem]] = []
            let store = SlackStore(client: nil, stateURL: tempState(), notify: { posted.append($0) })
            let prime = slackItem("D1", "990.1"), old = slackItem("D2", "50.1")
            let beforePriming = slackItem("D3", "995.1"), fresh = slackItem("D4", "1090.1")
            store.ingest(fetched([prime]), now: Date(timeIntervalSince1970: 1000))
            let later = Date(timeIntervalSince1970: 1100)
            store.ingest(fetched([prime, old, beforePriming, fresh]), now: later)
            precondition(posted == [[fresh]])
            // O que não foi avisado ficou no ledger: não volta como novo na rodada seguinte.
            store.ingest(fetched([prime, old, beforePriming, fresh]), now: later)
            precondition(posted == [[fresh]] && store.unreadCount == 4)
            // Mais velho que 15 min mesmo depois do priming: não avisa.
            store.ingest(fetched([prime, old, beforePriming, fresh, slackItem("D5", "1150.1")]), now: Date(timeIntervalSince1970: 1150 + 16 * 60))
            precondition(posted == [[fresh]])
        }
    }

    private static func cleanText() {
        let names = ["U2": "Ana"]
        func clean(_ s: String) -> String { cleanSlackText(s, me: "ME", name: { names[$0] }) }
        precondition(clean("oi <@ME> e <@U2>, <@U9>") == "oi @você e @Ana, @alguém")
        precondition(clean("<@U9|bob> viu") == "@bob viu")
        precondition(clean("veja <#C1|dev> e <#C2>") == "veja #dev e #canal")
        precondition(clean("<!here> <!channel> <!everyone>") == "@here @channel @everyone")
        precondition(clean("<!subteam^S1|@time-front> ok") == "@time-front ok")
        precondition(clean("<https://a.com/x?a=1&amp;b=2|o site> e <https://b.com>") == "o site e https://b.com")
        precondition(clean("a &lt; b &amp;&amp; c &gt; d") == "a < b && c > d")
        precondition(clean("sem marcação") == "sem marcação")
        precondition(mentionedUserIds("oi <@U1> <@U2|x> <#C1|d>") == ["U1", "U2"])
    }

    private static func seenPruning() {
        let now = Date(timeIntervalSince1970: 100 * 86400)
        let old = slackItem("D1", "\(Int(now.timeIntervalSince1970) - 15 * 86400).1")
        let recent = slackItem("D1", "\(Int(now.timeIntervalSince1970) - 13 * 86400).1")
        let stillCandidate = slackItem("D2", "\(Int(now.timeIntervalSince1970) - 20 * 86400).1")
        let ids: Set<String> = [old.id, recent.id, stillCandidate.id]
        // Antigo sai, recente fica, e antigo que a busca ainda devolve fica (senão voltaria para a lista).
        precondition(pruneSeen(ids, keeping: [stillCandidate.id], now: now) == [recent.id, stillCandidate.id])
    }

    private static func slackTexts() {
        let link = URL(string: "https://x.slack.com/archives/D1/p1")!
        // Com o app do Slack instalado o deep link vence o permalink; sem o app, vale o permalink.
        precondition(slackOpenURL(permalink: link, team: "T1", channel: "D1", ts: "1.2", appInstalled: false) == link)
        precondition(slackOpenURL(permalink: link, team: "T1", channel: "D1", ts: "1.2", appInstalled: true)?.absoluteString == "slack://channel?team=T1&id=D1&message=1.2")
        precondition(slackOpenURL(permalink: nil, team: "T1", channel: "D1", ts: "1.2", appInstalled: true)?.absoluteString == "slack://channel?team=T1&id=D1&message=1.2")
        // Sem o app e sem permalink: nunca `slack://` (nada abriria), e sim o cliente web.
        precondition(slackOpenURL(permalink: nil, team: "T1", channel: "D1", ts: "1.2", appInstalled: false)?.absoluteString == "https://app.slack.com/client/T1/D1")
        precondition(slackOpenURL(permalink: nil, team: nil, channel: "D1", ts: "1.2", appInstalled: false)?.absoluteString == "https://app.slack.com/client")
        let now = Date(timeIntervalSince1970: 100_000)
        precondition(relativeTime(now.addingTimeInterval(-30), now: now) == "agora")
        precondition(relativeTime(now.addingTimeInterval(-300), now: now) == "5 min")
        precondition(relativeTime(now.addingTimeInterval(-7300), now: now) == "2 h")
        precondition(relativeTime(now.addingTimeInterval(-3 * 86400), now: now) == "3 d")
        var item = slackItem("D1", "1.1")
        item.userName = "Ana"
        precondition(notificationTitle(item) == "Ana · DM")
        let channel = SlackItem(channel: "C1", ts: SlackTS("1.1"), threadTs: nil, userId: "U2", userName: "Ana", text: "oi",
                                isDM: false, channelName: "dev", permalink: nil)
        precondition(notificationTitle(channel) == "Ana em #dev")
    }

    // MARK: Conectar, GitHub e barra

    private static func tokenPatterns() {
        // Tokens falsos partidos em dois literais: varredores de segredo (ex.: o push protection do GitHub) não acusam.
        let slack = "xoxp" + "-1234567890-1234567890-1234567890-0123456789abcdef0123456789abcdef"
        let jira = "ATATT3xFfGF0abcDEF_ghi-jkl=mnopqrstuvwxyz0123456789"
        precondition(tokenKind(slack) == .slack && tokenKind("  \(slack)\n") == .slack)
        precondition(tokenKind(jira) == .jira && tokenKind("\t\(jira) ") == .jira)
        // Curto demais, outro tipo de token, prefixo errado, texto com sobra ou vários tokens: ignorado.
        for other in ["", "xoxp-123", "xoxb" + "-1234567890-1234567890-abcdefghijklmnop", "ATATT3x", "oi xoxp" + "-1234567890-1234567890-1234567890-abc",
                      "\(slack) \(slack)", "\(slack)\nmais", "ghp" + "_abcdefghijklmnopqrstuvwxyz0123456789", "a@b.c",
                      String(repeating: "x", count: 5000)] {
            precondition(tokenKind(other) == nil, "ignorar: \(other.prefix(12))")
        }
    }

    private static func connectInputsAndTexts() {
        precondition(jiraConnectInput(email: " a@b.c\n", site: "x.example.com")?.email == "a@b.c")
        // Sem site padrão: site vazio é recusado, nenhum pedido sai para um host vazio.
        precondition(defaultJiraSite.isEmpty && jiraConnectInput(email: "a@b.c", site: "") == nil)
        precondition(jiraConnectInput(email: "a@b.c", site: " https://x.example.com ")?.site == "https://x.example.com")
        precondition(jiraConnectInput(email: "", site: "") == nil && jiraConnectInput(email: "semarroba", site: "") == nil)
        precondition(jiraConnectInput(email: "a b@c.d", site: "") == nil)
        // Só https: http, outros esquemas e site sem host são recusados; sem esquema vira https.
        precondition(jiraConnectInput(email: "a@b.c", site: "http://x.example.com") == nil)
        precondition(jiraConnectInput(email: "a@b.c", site: "ftp://x.example.com") == nil)
        precondition(jiraConnectInput(email: "a@b.c", site: "https://") == nil)
        precondition(jiraConnectInput(email: "a@b.c", site: "HTTP://x.example.com") == nil)
        precondition(jiraConnectInput(email: "a@b.c", site: "x.example.com")?.site == "x.example.com")
        precondition(Credentials.jiraBase(site: "x.example.com/")?.absoluteString == "https://x.example.com")
        precondition(Credentials.jiraBase(site: " HTTPS://x.example.com ")?.host == "x.example.com")
        precondition(Credentials.jiraBase(site: "http://x.example.com") == nil && Credentials.jiraBase(site: "") == nil)
        precondition(Credentials(jiraSite: "http://x.example.com").jiraBase == nil)
        // Mensagens dizem o que fazer: o mesmo token não é tentado de novo, é preciso copiar outra vez.
        precondition(connectErrorMessage(APIError.unauthorized, service: .jira) == "e-mail ou token não bateram · cancele e confira o e-mail")
        precondition(connectErrorMessage(APIError.unauthorized, service: .slack).contains("Slack"))
        precondition(connectErrorMessage(APIError.unauthorized, service: .slack).hasSuffix("copie de novo para tentar"))
        precondition(connectErrorMessage(APIError.transport("x"), service: .slack) == APIError.transport("x").userMessage + " · copie de novo para tentar")
        precondition(connectErrorMessage(CocoaError(.fileNoSuchFile), service: .slack) == "não consegui validar o token · copie de novo para tentar")
        precondition(connectSteps(.slack).count == 3 && connectSteps(.jira).count == 3)
    }

    private static func slackManifestLink() {
        let url = slackManifestURL().absoluteString
        precondition(url.hasPrefix("https://api.slack.com/apps?new_app=1&manifest_yaml="))
        let value = String(url.dropFirst("https://api.slack.com/apps?new_app=1&manifest_yaml=".count))
        // Tudo que não é seguro numa query fica codificado, e decodificar devolve o manifesto inteiro.
        precondition(!value.contains(" ") && !value.contains("\n") && !value.contains("&") && !value.contains(":") && !value.contains("#"))
        precondition(value.contains("%3A") && value.contains("%0A") && value.contains("search%3Aread"))
        precondition(value.removingPercentEncoding == slackManifest)
        precondition(slackManifest.contains("im:history") && !slackManifest.contains("bot"))
    }

    @MainActor private static func tokenCatcherPoll() {
        // Tokens falsos partidos em dois literais: varredores de segredo (ex.: o push protection do GitHub) não acusam.
        let slack = "xoxp" + "-1234567890-1234567890-1234567890-0123456789abcdef"
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString(slack, forType: .string)   // já copiado antes de começar: não conta
        let catcher = TokenCatcher(service: .slack, pasteboard: board, timeout: 600)
        precondition(catcher.poll() == .idle)
        // Cópia que não é texto (imagem) é ignorada sem ler.
        board.clearContents(); board.setData(Data([1, 2, 3]), forType: .png)
        precondition(catcher.poll() == .idle)
        board.clearContents(); board.setString("receita de bolo", forType: .string)
        precondition(catcher.poll() == .idle)
        // Token de outro serviço é ignorado.
        board.clearContents(); board.setString("ATATT3xFfGF0abcDEF_ghi-jkl=mnopqrstuvwxyz0123456789", forType: .string)
        precondition(catcher.poll() == .idle)
        board.clearContents(); board.setString("  \(slack)\n", forType: .string)
        let count = board.changeCount
        precondition(catcher.poll() == .token(slack, changeCount: count))
        precondition(catcher.poll() == .idle)   // o mesmo conteúdo não dispara de novo
        // Outra cópia depois do token: não limpa.
        board.clearContents(); board.setString("outra coisa", forType: .string)
        catcher.clearIfUnchanged(count)
        precondition(board.string(forType: .string) == "outra coisa")
        // Sem cópia nova depois: limpa.
        board.clearContents(); board.setString(slack, forType: .string)
        catcher.clearIfUnchanged(board.changeCount)
        precondition(board.string(forType: .string) == nil)
        // Passou do prazo.
        precondition(catcher.poll(now: Date().addingTimeInterval(601)) == .expired)
    }

    private static let searchJSON = """
    {"total_count": 2, "incomplete_results": false, "items": [
      {"repository_url": "https://api.github.com/repos/acme/web-app", "number": 4821, "title": "feat: resumo do pedido",
       "user": {"login": "marina-duarte"}, "updated_at": "2026-10-24T12:30:00Z",
       "html_url": "https://github.com/acme/web-app/pull/4821", "draft": true, "state": "open"},
      {"repository_url": "https://api.github.com/repos/acme/infra", "number": 58, "title": "chore: node",
       "user": null, "updated_at": "2026-10-23T09:00:00Z", "html_url": "https://github.com/acme/infra/pull/58"}
    ]}
    """

    private static func pullRequestDecoding() {
        let prs = try! decodePullRequests(Data(searchJSON.utf8))
        precondition(prs.count == 2 && prs[0].id == "acme/web-app#4821" && prs[0].title == "feat: resumo do pedido")
        precondition(prs[0].author == "marina-duarte" && prs[0].draft && prs[0].shortId == "web-app#4821")
        precondition(prs[0].updatedAt == Date(timeIntervalSince1970: 1_792_845_000))
        precondition(prs[0].url.absoluteString == "https://github.com/acme/web-app/pull/4821")
        // Sem "draft" e sem autor (conta apagada): PR normal de "?".
        precondition(!prs[1].draft && prs[1].author == "?")
        precondition(try! decodePullRequests(Data(#"{"items": []}"#.utf8)).isEmpty)
        for bad in ["{}", "[]", "oi", #"{"items": [{"number": 1}]}"#] {
            precondition((try? decodePullRequests(Data(bad.utf8))) == nil, "recusar: \(bad)")
        }
        // 403 do GitHub: limite (retry-after ou remaining 0) vira rateLimited; outro 403 não é "sem permissão".
        let now = Date(timeIntervalSince1970: 1000)
        precondition(githubError(status: 403, headers: ["Retry-After": "42"], now: now) == .rateLimited(retryAfter: 42))
        precondition(githubError(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1090"], now: now) == .rateLimited(retryAfter: 90))
        precondition(githubError(status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "900"], now: now) == .rateLimited(retryAfter: 1))
        precondition(githubError(status: 403, headers: ["x-ratelimit-remaining": "0"], now: now) == .rateLimited(retryAfter: 60))
        let denied = githubError(status: 403, headers: ["x-ratelimit-remaining": "4999"], now: now)
        precondition(denied != nil && denied != .forbidden && !(denied!.userMessage.contains("sem permissão")))
        precondition(githubError(status: 200, headers: [:], now: now) == nil && githubError(status: 401, headers: [:], now: now) == nil)
        precondition(GitHubToken.candidates.count == 3 && GitHubToken.candidates[0].hasSuffix("/.local/bin/gh"))
    }

    /// Roda um trecho async no main actor girando o run loop (o selftest é síncrono).
    @MainActor private static func block<T>(_ body: @escaping @MainActor () async -> T) -> T {
        var result: T?
        Task { result = await body() }
        let limit = Date().addingTimeInterval(5)
        while result == nil && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return result!
    }

    private static func githubStoreFlow() {
        MainActor.assumeIsolated {
            let pr = try! decodePullRequests(Data(searchJSON.utf8))
            // Sem gh logado: pede o login, sem erro.
            let none = GitHubStore(readToken: { nil }, search: { _ in pr })
            block { await none.refresh() }
            precondition(none.needsLogin && none.error == nil && none.items.isEmpty && none.loaded && none.updatedAt != nil)
            // 401 relê o token do gh e tenta uma vez mais; o token usado nunca é guardado fora da memória.
            var reads = 0, used: [String] = []
            let stale = GitHubStore(readToken: { reads += 1; return reads == 1 ? "velho" : "novo" },
                                    search: { token in used.append(token); if token == "velho" { throw APIError.unauthorized }; return pr })
            block { await stale.refresh() }
            precondition(used == ["velho", "novo"] && reads == 2 && stale.items == pr && stale.error == nil && !stale.needsLogin)
            // Continua 401 com o token novo: erro de acesso, lista vazia.
            let denied = GitHubStore(readToken: { "x" }, search: { _ in throw APIError.unauthorized })
            block { await denied.refresh() }
            precondition(denied.error == .unauthorized && denied.items.isEmpty)
            // Limite: mantém a lista e só avisa.
            var limited = false
            let rate = GitHubStore(readToken: { "x" }, search: { _ in if limited { throw APIError.rateLimited(retryAfter: 9) }; return pr })
            block { await rate.refresh() }
            limited = true
            block { await rate.refresh() }
            precondition(rate.items == pr && rate.error == nil && rate.notice != nil)
            // Chamadas juntas viram uma busca só.
            var searches = 0
            let single = GitHubStore(readToken: { "x" }, search: { _ in searches += 1; try await Task.sleep(for: .milliseconds(50)); return pr })
            block { async let a: Void = single.refresh(); async let b: Void = single.refresh(); _ = await (a, b) }
            precondition(searches == 1)
            // Paginação: segue até uma página vir incompleta, chegar no total_count ou no teto de 300.
            func page(_ range: Range<Int>) -> [PullRequest] {
                range.map { PullRequest(repo: "o/r", number: $0, title: "t", author: "a", updatedAt: Date(timeIntervalSince1970: 0),
                                        url: URL(string: "https://github.com/o/r/pull/\($0)")!, draft: false) }
            }
            var asked: [Int] = []
            let two = block { try! await collectPullRequests { n in asked.append(n); return (n == 1 ? page(0..<100) : page(100..<150), 150) } }
            precondition(two.count == 150 && asked == [1, 2])
            asked = []
            let capped = block { try! await collectPullRequests { n in asked.append(n); return (page((n - 1) * 100..<n * 100), 5000) } }
            precondition(capped.count == 300 && asked == [1, 2, 3])
            asked = []
            let exact = block { try! await collectPullRequests { n in asked.append(n); return (page(0..<100), 100) } }
            precondition(exact.count == 100 && asked == [1])
            // A lista mudou entre as páginas e um PR veio duas vezes: fica um só.
            let shifted = block { try! await collectPullRequests { n in (n == 1 ? page(0..<100) : page(99..<120), 120) } }
            precondition(shifted.count == 120 && Set(shifted.map(\.id)).count == 120)
            precondition(try! decodePullRequestPage(Data(searchJSON.utf8)).total == 2)
        }
    }

    private static func legacyFolderMigration() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pauta-mig-\(UUID().uuidString)")
        let old = root.appendingPathComponent("Radar"), new = root.appendingPathComponent("Pauta")
        func mode(_ url: URL) -> Int { (try! fm.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue }
        // Sem pasta antiga: nada a fazer.
        precondition(!migrateLegacyFolder(from: old, to: new))
        try! fm.createDirectory(at: old, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fm.createFile(atPath: old.appendingPathComponent("credentials.json").path, contents: Data("{}".utf8), attributes: [.posixPermissions: 0o600])
        precondition(migrateLegacyFolder(from: old, to: new))
        precondition(!fm.fileExists(atPath: old.path))
        precondition(fm.fileExists(atPath: new.appendingPathComponent("credentials.json").path))
        precondition(mode(new) == 0o700 && mode(new.appendingPathComponent("credentials.json")) == 0o600)
        // Já migrado: não mexe de novo.
        precondition(!migrateLegacyFolder(from: old, to: new))
        // As duas existem: a antiga fica intacta, a nova vence.
        try! fm.createDirectory(at: old, withIntermediateDirectories: true)
        precondition(!migrateLegacyFolder(from: old, to: new) && fm.fileExists(atPath: old.path))
        try? fm.removeItem(at: root)
    }

    private static func barSegmentRules() {
        let base = appGlyph, warning = "exclamationmark.triangle"
        precondition(appGlyph == "checklist" && NSImage(systemSymbolName: appGlyph, accessibilityDescription: nil) != nil)
        // Sempre o mesmo símbolo; o número é o total dos três e some quando é 0.
        // Os três logos (SVG embutido) carregam.
        precondition(HubService.allCases.allSatisfy { Logos.image($0).size.width > 0 })
        let at = Date(timeIntervalSince1970: 100_000)
        precondition(agoShort(at.addingTimeInterval(-10), now: at) == "agora" && agoShort(at.addingTimeInterval(-7300), now: at) == "há 2 h")
        precondition(barState(slack: 0, jira: 0, github: 0, failed: false) == BarState(symbol: base, total: nil))
        precondition(barState(slack: 0, jira: 0, github: 5, failed: false) == BarState(symbol: base, total: 5))
        precondition(barState(slack: 3, jira: 2, github: 5, failed: false) == BarState(symbol: base, total: 10))
        // Erro troca o símbolo, não o total.
        precondition(barState(slack: 0, jira: 0, github: 0, failed: true) == BarState(symbol: warning, total: nil))
        precondition(barState(slack: 1, jira: 0, github: 2, failed: true) == BarState(symbol: warning, total: 3))
        // Detalhe por serviço no tooltip/VoiceOver.
        precondition(barDescription(slack: 3, jira: 2, github: 5, failed: false) == "Pauta: Slack 3, Jira 2, GitHub 5")
        precondition(barDescription(slack: 3, jira: 0, github: 1, failed: false) == "Pauta: Slack 3, GitHub 1")
        precondition(barDescription(slack: 0, jira: 0, github: 0, failed: false) == "Pauta: nada pendente")
        precondition(barDescription(slack: 2, jira: 0, github: 0, failed: true) == "Pauta: erro em algum serviço · Slack 2")
        precondition(barImage(BarState(symbol: base, total: 3), description: "x").accessibilityDescription == "x")
    }
}
