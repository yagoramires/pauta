import AppKit
import UserNotifications

/// Notificações do macOS para DMs/menções novas. O `UNUserNotificationCenter` só é tocado aqui dentro e só no app de
/// verdade (fora de um .app ele trava): `--selftest` e `--snapshots` nunca chamam `start`/`post`.
enum Notifier {
    static let slackBundleId = "com.tinyspeck.slackmacgap"
    /// Mais que isso de uma vez vira um resumo, para uma rajada não encher a tela.
    static let maxIndividual = 5

    static var slackRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == slackBundleId }
    }

    /// Clique numa notificação: canal, ts e permalink do item (nil, nil, nil no resumo, que só abre o Slack).
    nonisolated(unsafe) static var onOpen: (String?, String?, URL?) -> Void = { _, _, _ in }
    private static let delegate = Delegate()

    /// No lançamento do app: sem isto o clique numa notificação não chega aqui. Não pede permissão.
    static func start() { UNUserNotificationCenter.current().delegate = delegate }

    /// Só avisa com o Slack fechado (o app dele já avisa sozinho).
    static func postIfSlackClosed(_ items: [SlackItem]) { if !slackRunning { post(items) } }

    static func post(_ items: [SlackItem]) {
        // Fora de um .app (binário solto) o UNUserNotificationCenter trava.
        guard !items.isEmpty, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        // A permissão só é pedida aqui, na primeira vez que há algo para avisar (depois disso o pedido volta na hora).
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return debugLog("notificações negadas pelo usuário") }
            for item in items.prefix(maxIndividual) {
                let content = UNMutableNotificationContent()
                content.title = notificationTitle(item)
                content.body = item.text
                content.sound = .default
                content.userInfo = ["channel": item.channel, "ts": item.ts.raw, "permalink": item.permalink?.absoluteString ?? ""]
                // O id do item como identificador: a mesma mensagem nunca vira duas notificações.
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
            }
            if items.count > maxIndividual {
                let content = UNMutableNotificationContent()
                content.title = "Slack"
                content.body = "+\(items.count - maxIndividual) mensagens novas"
                content.sound = .default
                center.add(UNNotificationRequest(identifier: "resumo-\(UUID().uuidString)", content: content, trigger: nil))
            }
        }
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list, .sound])
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            let info = response.notification.request.content.userInfo
            let channel = info["channel"] as? String, ts = info["ts"] as? String
            let link = (info["permalink"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            DispatchQueue.main.async {
                Notifier.onOpen(channel, ts, link)
                completionHandler()
            }
        }
    }
}
