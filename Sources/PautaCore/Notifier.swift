import AppKit
import UserNotifications

/// O pedaço do UNUserNotificationCenter que o Pauta usa; o selftest troca por um falso (nunca posta aviso de verdade).
protocol NotifyCenter: AnyObject {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate)
    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void)
    func authorization(_ done: @escaping (UNAuthorizationStatus) -> Void)
    func post(_ request: UNNotificationRequest)
    func removeDelivered(_ identifiers: [String])
}

extension UNUserNotificationCenter: NotifyCenter {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) { self.delegate = delegate }
    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void) { requestAuthorization(options: [.alert, .sound], completionHandler: done) }
    func authorization(_ done: @escaping (UNAuthorizationStatus) -> Void) { getNotificationSettings { done($0.authorizationStatus) } }
    func post(_ request: UNNotificationRequest) { add(request) }
    func removeDelivered(_ identifiers: [String]) { removeDeliveredNotifications(withIdentifiers: identifiers) }
}

/// Id da notificação → permalink da mensagem, em `avisos.json`. No NeyHub o toque chega só com o id (sem o userInfo),
/// e pode chegar depois de reiniciar: o link precisa estar no disco. Até 200; os mais antigos saem primeiro.
struct NoticeLinks: Codable, Equatable {
    static let limit = 200

    struct Entry: Codable, Equatable { var id: String, link: String }
    var entries: [Entry] = []

    /// "" = mensagem sem permalink (DM vinda do history): ainda abre a conversa pelo canal e ts do id.
    mutating func add(_ id: String, link: URL?) {
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, link: link?.absoluteString ?? ""))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
    }

    func link(for id: String) -> String? { entries.last { $0.id == id }?.link }

    static func load(_ url: URL) -> NoticeLinks {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(NoticeLinks.self, from: $0) } ?? NoticeLinks()
    }

    func save(_ url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Credentials.writePrivately(data, to: url, what: "avisos")
    }
}

/// Notificações do macOS para DMs/menções novas. O `UNUserNotificationCenter` só é tocado aqui dentro e só no app de
/// verdade (fora de um .app ele trava): `--selftest` passa um centro falso e `--snapshots` nunca chama `start`/`post`.
@MainActor
final class Notifier {
    nonisolated static let slackBundleId = "com.tinyspeck.slackmacgap"
    /// Mais que isso de uma vez vira um resumo, para uma rajada não encher a tela.
    static let maxIndividual = 5
    /// No NeyHub o centro é de todos os plugins e ele roteia o toque por esse prefixo.
    nonisolated static let prefix = "local.pauta."

    static var slackRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == slackBundleId }
    }

    /// Dentro do NeyHub: ele é o delegate e quem pede a permissão.
    private let hosted: Bool
    private let injected: NotifyCenter?
    // Preguiçoso: fora de um .app (modo --snapshots) o sistema derruba o processo ao pedir o center.
    private lazy var center: NotifyCenter = injected ?? UNUserNotificationCenter.current()
    private let delegate = PautaNotifierDelegate()
    private let linksURL: URL
    private(set) var links: NoticeLinks
    /// Desinstalado no NeyHub: nada mais é avisado.
    private var stopped = false
    /// Toque numa notificação (avulso): o id já com o prefixo e a ação.
    var onOpen: (String, String) -> Void = { _, _ in }

    init(hosted: Bool, center: NotifyCenter? = nil, linksURL: URL) {
        self.hosted = hosted
        injected = center
        self.linksURL = linksURL
        links = NoticeLinks.load(linksURL)
    }

    /// No lançamento do app avulso: sem isto o clique numa notificação não chega aqui. Não pede permissão.
    func start() {
        stopped = false
        guard !hosted else { return }
        delegate.onResponse = { [weak self] id, action in MainActor.assumeIsolated { self?.onOpen(id, action) } }
        center.setDelegate(delegate)
    }

    /// Desinstalado no NeyHub: para de avisar. Os avisos na Central ficam: sair do NeyHub também chama stop(), e quem
    /// tira ao desinstalar é o NeyHub.
    func stop() { stopped = true }

    /// Hospedado: só consulta (quem pede é a tela de Permissões do NeyHub). `done` chega na main.
    func checkPermission(_ done: @escaping (Bool) -> Void) {
        guard !stopped else { return }
        center.authorization { status in
            let allowed = status == .authorized || status == .provisional
            DispatchQueue.main.async { done(allowed) }
        }
    }

    /// Só avisa com o Slack fechado (o app dele já avisa sozinho).
    func postIfSlackClosed(_ items: [SlackItem]) { if !Self.slackRunning { post(items) } }

    func post(_ items: [SlackItem]) {
        // Fora de um .app (binário solto) o UNUserNotificationCenter trava.
        guard !stopped, !items.isEmpty, injected != nil || hosted || Bundle.main.bundleIdentifier != nil else { return }
        var requests: [UNNotificationRequest] = []
        for item in items.prefix(Self.maxIndividual) {
            let content = UNMutableNotificationContent()
            content.title = notificationTitle(item)
            content.body = item.text
            content.sound = .default
            content.userInfo = ["channel": item.channel, "ts": item.ts.raw, "permalink": item.permalink?.absoluteString ?? ""]
            // O id do item como identificador: a mesma mensagem nunca vira duas notificações.
            let id = Self.prefix + item.id
            links.add(id, link: item.permalink)
            requests.append(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
        if items.count > Self.maxIndividual {
            let content = UNMutableNotificationContent()
            content.title = "Slack"
            content.body = "+\(items.count - Self.maxIndividual) mensagens novas"
            content.sound = .default
            requests.append(UNNotificationRequest(identifier: Self.prefix + "resumo-\(UUID().uuidString)", content: content, trigger: nil))
        }
        links.save(linksURL)
        let center = center
        // Hospedado a permissão é do NeyHub (tela Permissões): só posta.
        if hosted { return requests.forEach(center.post) }
        // A permissão só é pedida aqui, na primeira vez que há algo para avisar (depois disso o pedido volta na hora).
        center.requestAuthorization { granted, _ in
            guard granted else { return debugLog("notificações negadas pelo usuário") }
            requests.forEach(center.post)
        }
    }

    /// Aviso da 0.1.0 que ficou na Central (avulso): o identificador era "canal:ts", sem o prefixo.
    nonisolated static func normalized(_ identifier: String) -> String {
        identifier.hasPrefix(prefix) ? identifier : prefix + identifier
    }
}

final class PautaNotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onResponse: (String, String) -> Void = { _, _ in }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = Notifier.normalized(response.notification.request.identifier), action = response.actionIdentifier
        DispatchQueue.main.async {
            self.onResponse(identifier, action)
            completionHandler()
        }
    }
}
