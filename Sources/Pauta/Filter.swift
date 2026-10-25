import Foundation

enum ServiceFilter: CaseIterable, Equatable { case all, slack, github, jira }

func normalized(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

private func words(_ query: String) -> [String] { query.split(whereSeparator: \.isWhitespace).map(String.init) }

/// Busca com algum termo (só espaços não conta: casa com tudo).
func isSearching(_ query: String) -> Bool { !words(query).isEmpty }

/// Query vazia (ou só espaços) casa com tudo; senão toda palavra precisa aparecer em algum campo, em qualquer ordem.
func matches(_ query: String, _ fields: [String]) -> Bool { matches(words: searchWords(query), fields) }

/// A query já quebrada e normalizada: o `visibleItems` faz isso uma vez só, não uma por item.
private func searchWords(_ query: String) -> [String] { words(query).map(normalized) }

private func matches(words: [String], _ fields: [String]) -> Bool {
    let haystack = normalized(fields.joined(separator: " "))
    return words.allSatisfy { haystack.contains($0) }
}

func searchFields(_ item: SlackItem) -> [String] { [item.userName, item.channelName ?? "", item.text] }
func searchFields(_ pr: PullRequest) -> [String] { [pr.title, pr.shortId, pr.author] }
func searchFields(_ issue: JiraIssue) -> [String] { [issue.key, issue.summary] }

struct VisibleItems: Equatable {
    var slack: [SlackItem]
    var prs: [PullRequest]
    var mine: [JiraIssue]
    var free: [JiraIssue]
}

/// O que as abas mostram: preferências ("menções em canais", "cards livres") e depois a busca.
func visibleItems(slack: [SlackItem], prs: [PullRequest], mine: [JiraIssue], free: [JiraIssue],
                  prefs: Prefs, query: String) -> VisibleItems {
    let w = searchWords(query)
    return VisibleItems(slack: visibleSlack(slack, prefs: prefs).filter { matches(words: w, searchFields($0)) },
                        prs: prs.filter { matches(words: w, searchFields($0)) },
                        mine: mine.filter { matches(words: w, searchFields($0)) },
                        free: prefs.freeCards ? free.filter { matches(words: w, searchFields($0)) } : [])
}

func pillCounts(_ v: VisibleItems) -> [ServiceFilter: Int] {
    let jira = v.mine.count + v.free.count
    return [.all: v.slack.count + v.prs.count + jira, .slack: v.slack.count, .github: v.prs.count, .jira: jira]
}

/// Trechos de `text` a destacar (ignorando acento e caixa): ordenados e sem sobreposição.
func matchRanges(_ text: String, query: String) -> [Range<String.Index>] {
    var found: [Range<String.Index>] = []
    for word in words(query) {
        var from = text.startIndex
        while from < text.endIndex,
              let r = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            found.append(r)
            from = r.upperBound
        }
    }
    var merged: [Range<String.Index>] = []
    for r in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        if let last = merged.last, r.lowerBound <= last.upperBound {
            merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
        } else {
            merged.append(r)
        }
    }
    return merged
}

/// Onde a linha passa a começar (umas palavras antes do primeiro trecho achado) para ele não sumir nas reticências do
/// fim; nil quando a linha cabe em `budget` caracteres ou o trecho já está perto do começo.
func searchExcerptStart(_ line: String, firstMatch: Range<String.Index>?, budget: Int) -> String.Index? {
    guard let first = firstMatch, line.count > budget, line.distance(from: line.startIndex, to: first.lowerBound) > 16
    else { return nil }
    let from = line.index(first.lowerBound, offsetBy: -12)
    return line[from..<first.lowerBound].firstIndex(of: " ").map { line.index(after: $0) } ?? first.lowerBound
}

/// "Nada com “x”." só quando todo serviço do filtro está pronto (conectado, carregado, sem erro nem aviso); senão cada
/// seção mostra o próprio carregando, erro ou conectar.
func showsNoResults(filter: ServiceFilter, query: String, counts: [ServiceFilter: Int], ready: Set<ServiceFilter>) -> Bool {
    let relevant: Set<ServiceFilter> = filter == .all ? [.slack, .github, .jira] : [filter]
    return isSearching(query) && counts[filter] == 0 && relevant.isSubset(of: ready)
}

func clearTitle(_ filter: ServiceFilter) -> String {
    switch filter {
    case .all: return "Ninguém esperando você."
    case .slack: return "Nada no Slack."
    case .github: return "Nenhum PR esperando você."
    case .jira: return "Nenhum card esperando você."
    }
}

func resultsText(_ count: Int) -> String { count == 1 ? "1 resultado" : "\(count) resultados" }
