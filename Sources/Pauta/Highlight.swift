import Foundation

/// O que ocupa o destaque do popover: a coisa mais recente que espera por você (Slack ou PR).
enum Highlight: Equatable {
    case slack(SlackItem), pr(PullRequest)

    var id: String {
        switch self {
        case .slack(let item): return item.id
        case .pr(let pr): return pr.id
        }
    }
}

enum HeroState: Equatable { case loading, item(Highlight), clear }

/// O mais recente entre Slack e PRs; no empate exato, o Slack.
func pickHighlight(slack: [SlackItem], prs: [PullRequest]) -> Highlight? {
    let s = slack.max { $0.ts < $1.ts }
    let p = prs.max { $0.updatedAt < $1.updatedAt }
    switch (s, p) {
    case (nil, nil): return nil
    case (let s?, nil): return .slack(s)
    case (nil, let p?): return .pr(p)
    case (let s?, let p?): return p.updatedAt > s.ts.date ? .pr(p) : .slack(s)
    }
}

/// nil = conectado mas ainda não carregou; desconectado = [].
func heroState(slack: [SlackItem]?, prs: [PullRequest]?) -> HeroState {
    if let item = pickHighlight(slack: slack ?? [], prs: prs ?? []) { return .item(item) }
    return slack == nil || prs == nil ? .loading : .clear
}

/// Entrada do destaque por serviço: desconectado = []; nil = ainda desconhecido (não carregou, ou falhou sem itens).
func heroInput<T>(connected: Bool, loaded: Bool, failed: Bool, items: [T]) -> [T]? {
    if !connected { return [] }
    if !loaded || (failed && items.isEmpty) { return nil }
    return items
}

func highlightContext(_ item: SlackItem, now: Date = Date()) -> String {
    let ago = agoShort(item.ts.date, now: now)
    if item.isDM { return "\(item.userName), na DM, \(ago)" }
    let channel = "#\(item.channelName ?? "canal")"
    return item.threadTs == nil ? "\(item.userName), em \(channel), \(ago)"
                                : "\(item.userName), numa thread em \(channel), \(ago)"
}

func highlightContext(_ pr: PullRequest, now: Date = Date()) -> String {
    "de \(pr.author), atualizado \(agoShort(pr.updatedAt, now: now))"
}

/// Mais de 24 h.
func isOld(_ date: Date, now: Date = Date()) -> Bool { now.timeIntervalSince(date) > 86_400 }

/// O subtítulo do "Ninguém esperando você." só fala do que está conectado.
func clearSubtitle(slackConnected: Bool, githubConnected: Bool) -> String? {
    switch (slackConnected, githubConnected) {
    case (true, true): "Slack e revisões em dia."
    case (true, false): "Slack em dia."
    case (false, true): "Revisões em dia."
    case (false, false): nil
    }
}

func sectionCount(_ count: Int, highlighted: Bool) -> String { highlighted ? "mais \(count)" : "\(count)" }

func sprintDaysText(_ days: Int) -> String {
    days <= 0 ? "termina hoje" : days == 1 ? "falta 1 dia" : "faltam \(days) dias"
}

func freeCardsText(_ count: Int) -> String {
    count == 1 ? "1 card livre no projeto" : "\(count) cards livres no projeto"
}

/// `failed` = `error != nil || notice != nil`. Limpa (conectado, carregado, sem erro, sem linhas) some.
func showsSection(connected: Bool, loaded: Bool, failed: Bool, rows: Int) -> Bool {
    !connected || !loaded || failed || rows > 0
}
