import AppKit

/// Passou mais de `after` segundos da última atualização boa (ou nunca atualizou)?
func isStale(_ updatedAt: Date?, now: Date = Date(), after: TimeInterval = 15) -> Bool {
    updatedAt.map { now.timeIntervalSince($0) > after } ?? true
}

/// Dispara os `refresh()` dos três stores a cada intervalo (2 min por padrão, ajustável) e ao acordar o Mac. Chamada repetida é segura: os stores
/// já juntam buscas em andamento (uma por vez), então aqui só se dispara.
@MainActor
final class Poller {
    private let jira: JiraStore
    private let slack: SlackStore
    private let github: GitHubStore
    private var interval: TimeInterval
    private var timer: Timer?
    private var wake: NSObjectProtocol?

    init(jira: JiraStore, slack: SlackStore, github: GitHubStore, interval: TimeInterval = 120) {
        self.jira = jira
        self.slack = slack
        self.github = github
        self.interval = interval
    }

    /// Só leitura: o intervalo do timer em uso (nil antes do `start()`).
    var timerInterval: TimeInterval? { timer?.timeInterval }

    private func schedule() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow(reason: "timer") }
        }
        timer.tolerance = 10
        self.timer = timer
    }

    /// Troca o intervalo; antes do `start()` só guarda o valor.
    func setInterval(minutes: Int) {
        interval = TimeInterval(minutes * 60)
        if timer != nil { schedule() }
    }

    func start() {
        guard timer == nil else { return }
        schedule()
        wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow(reason: "acordou") }
        }
        refreshNow(reason: "início")
    }

    /// Desinstalar no NeyHub: sem timer nem observador do acordar. Uma busca já em andamento só termina.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
        wake = nil
    }

    /// Os três em paralelo.
    func refreshNow(reason: String = "manual") {
        debugLog("poller: rodada (\(reason)) · jira \(jira.configured ? "ativo" : "sem credenciais") · slack \(slack.configured ? "ativo" : "sem credenciais") · github")
        Task { await jira.refresh() }
        Task { await slack.refresh() }
        Task { await github.refresh() }
    }

    /// Ao abrir o popover: só o que tiver mais de 15 s desde a última atualização.
    func popoverOpened() {
        if isStale(jira.updatedAt) { Task { await jira.refresh() } }
        if isStale(slack.updatedAt) { Task { await slack.refresh() } }
        if isStale(github.updatedAt) { Task { await github.refresh() } }
    }
}
