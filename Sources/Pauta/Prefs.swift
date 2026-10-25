import Foundation

enum Density: String, CaseIterable { case comfortable, compact }

/// Preferências de exibição e de avisos, guardadas no UserDefaults (nada sensível, ao contrário das credenciais).
struct Prefs: Equatable {
    var channelMentions = true      // "Menções em canais"
    var freeCards = true            // "Cards livres"
    var density: Density = .comfortable
    var refreshMinutes = 2          // só 1, 2 ou 5
    var slackNotifications = true   // "Notificações do Slack"

    static let refreshChoices = [1, 2, 5]

    static func load(_ defaults: UserDefaults = .standard) -> Prefs {
        var p = Prefs()
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        p.channelMentions = flag("prefs.channelMentions", p.channelMentions)
        p.freeCards = flag("prefs.freeCards", p.freeCards)
        p.slackNotifications = flag("prefs.slackNotifications", p.slackNotifications)
        p.density = defaults.string(forKey: "prefs.density").flatMap(Density.init(rawValue:)) ?? p.density
        let minutes = defaults.integer(forKey: "prefs.refreshMinutes")
        p.refreshMinutes = refreshChoices.contains(minutes) ? minutes : p.refreshMinutes
        return p
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(channelMentions, forKey: "prefs.channelMentions")
        defaults.set(freeCards, forKey: "prefs.freeCards")
        defaults.set(density.rawValue, forKey: "prefs.density")
        defaults.set(refreshMinutes, forKey: "prefs.refreshMinutes")
        defaults.set(slackNotifications, forKey: "prefs.slackNotifications")
    }
}

/// Dono das preferências: quem mexe em `prefs` grava na hora.
@MainActor
final class PrefsStore: ObservableObject {
    private let defaults: UserDefaults
    @Published var prefs: Prefs { didSet { prefs.save(defaults) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefs = Prefs.load(defaults)
    }
}

/// Sem as menções de canal quando "Menções em canais" está desligado (DMs ficam sempre).
func visibleSlack(_ items: [SlackItem], prefs: Prefs) -> [SlackItem] {
    prefs.channelMentions ? items : items.filter(\.isDM)
}

/// O que pode virar notificação: nada com as notificações desligadas.
func notifiable(_ items: [SlackItem], prefs: Prefs) -> [SlackItem] {
    prefs.slackNotifications ? visibleSlack(items, prefs: prefs) : []
}

/// Números da barra de menu já respeitando as preferências. Jira = seus cards + livres, como a pílula Jira.
func barCounts(slack: [SlackItem], mine: Int, freeCount: Int, prs: Int, prefs: Prefs) -> (slack: Int, jira: Int, github: Int) {
    (visibleSlack(slack, prefs: prefs).count, mine + (prefs.freeCards ? freeCount : 0), prs)
}
