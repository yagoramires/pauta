import Foundation

enum StatusCategory: String {
    case todo = "new", inProgress = "indeterminate", done
}

struct ParentRef: Equatable {
    let key, summary: String
}

/// Concluídos (Concluído DEV/QA, Done) e cancelados não aparecem nas listas; o nome cobre "Cancelado" fora da categoria Done.
func isClosed(_ issue: JiraIssue) -> Bool {
    issue.category == .done
        || normalized(issue.status).contains("cancel")
}

struct JiraIssue: Equatable, Identifiable {
    let key, summary, status: String
    let category: StatusCategory
    let assigneeId: String?
    let parent: ParentRef?
    let isSubtask: Bool
    /// Sprint ativa do card (campo `customfield_10020`); nil se o card não está em nenhuma sprint ativa.
    var sprint: Sprint? = nil
    var id: String { key }
}

struct Transition: Equatable, Identifiable {
    let id, name, toStatus: String
}

struct Sprint: Equatable {
    let id: Int
    let name: String
    let endDate: Date?
    var boardId: Int? = nil
}

/// A Agile devolve "2026-10-30T20:00:00.000Z" (com ou sem fração).
func parseJiraDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}

enum JQL {
    /// Sem projeto nos ajustes: as sprints abertas de todos os projetos.
    static func sprint(_ project: String) -> String {
        (project.isEmpty ? "" : "project = \"\(project)\" AND ") + "sprint in openSprints()"
    }
    static func mine(_ project: String) -> String {
        sprint(project) + " AND assignee = currentUser() ORDER BY status, rank"
    }
    // shortcut: "livre" = qualquer status que não seja Done; trocar para `statusCategory = "To Do"` se vier ruído.
    static func free(_ project: String) -> String {
        sprint(project) + " AND assignee is EMPTY AND statusCategory != Done ORDER BY rank"
    }
}

/// Card livre (ou o pai de sub-tarefas livres). `headIssue != nil` quer dizer que o pai também está livre (tem "Pegar").
struct FreeGroup: Equatable, Identifiable {
    let head: ParentRef
    let headIssue: JiraIssue?
    let subtasks: [JiraIssue]
    var id: String { head.key }
}

/// Só sub-tarefa entra no grupo do pai. Card comum também tem `parent` (o Epic), mas é sempre cabeça do próprio grupo.
func groupFree(_ free: [JiraIssue]) -> [FreeGroup] {
    var order: [String] = []
    var heads: [String: (ref: ParentRef, issue: JiraIssue?)] = [:]
    var subtasks: [String: [JiraIssue]] = [:]
    for issue in free {
        if issue.isSubtask, let parent = issue.parent {
            if heads[parent.key] == nil { order.append(parent.key); heads[parent.key] = (parent, nil) }
            subtasks[parent.key, default: []].append(issue)
        } else {
            if heads[issue.key] == nil { order.append(issue.key) }
            heads[issue.key] = (ParentRef(key: issue.key, summary: issue.summary), issue)
        }
    }
    return order.map { FreeGroup(head: heads[$0]!.ref, headIssue: heads[$0]!.issue, subtasks: subtasks[$0] ?? []) }
}

/// Dias de calendário até o fim da sprint (fim hoje ou já passado = 0).
func daysLeft(until end: Date, now: Date, calendar: Calendar) -> Int {
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
    return max(0, days)
}

// MARK: - Decoding (API v3)

extension JiraIssue {
    private struct Raw: Decodable {
        struct Status: Decodable {
            struct Category: Decodable { let key: String }
            let id, name: String
            let statusCategory: Category
        }
        struct Fields: Decodable {
            struct Assignee: Decodable { let accountId: String }
            struct Parent: Decodable {
                struct Fields: Decodable { let summary: String }
                let key: String
                let fields: Fields
            }
            struct IssueType: Decodable { let subtask: Bool }
            /// Formato inesperado do campo vira "sem sprint" em vez de derrubar a busca inteira.
            struct Sprints: Decodable {
                struct Entry: Decodable {
                    let id: Int
                    let name: String?
                    let state: String?
                    let boardId: Int?
                    let endDate: String?
                }
                let entries: [Entry]
                init(from decoder: Decoder) throws { entries = (try? [Entry](from: decoder)) ?? [] }
            }
            let summary: String
            let status: Status
            let assignee: Assignee?
            let parent: Parent?
            let issuetype: IssueType?
            // shortcut: id do campo Sprint fixo (o padrão do Jira Cloud); ler de /rest/api/3/field se algum site usar outro.
            let customfield_10020: Sprints?
        }
        let key: String
        let fields: Fields

        var issue: JiraIssue {
            JiraIssue(key: key, summary: fields.summary, status: fields.status.name,
                      category: StatusCategory(rawValue: fields.status.statusCategory.key) ?? .todo,
                      assigneeId: fields.assignee?.accountId,
                      parent: fields.parent.map { ParentRef(key: $0.key, summary: $0.fields.summary) },
                      isSubtask: fields.issuetype?.subtask ?? false,
                      sprint: fields.customfield_10020?.entries.first { $0.state == "active" }.map {
                          Sprint(id: $0.id, name: $0.name ?? "Sprint", endDate: $0.endDate.flatMap(parseJiraDate), boardId: $0.boardId)
                      })
        }
    }

    private struct RawPage: Decodable {
        let issues: [Raw]
        let nextPageToken: String?
    }

    static func decode(_ data: Data) throws -> JiraIssue {
        try JSONDecoder().decode(Raw.self, from: data).issue
    }

    /// Uma página de `search/jql`.
    static func decodePage(_ data: Data) throws -> (issues: [JiraIssue], next: String?) {
        let page = try JSONDecoder().decode(RawPage.self, from: data)
        return (page.issues.map(\.issue), page.nextPageToken)
    }
}
