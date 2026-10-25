import AppKit
import NeyKit
import PautaCore
import UserNotifications

/// Pauta dentro do NeyHub. Linka só PautaCore e NeyKit (nunca NeyKitApp). O NeyHub chama tudo na main.
final class PautaEntry: NSObject, NeyPlugin {
    private var made: PautaApp?

    @MainActor private var app: PautaApp {
        if let made { return made }
        let app = PautaApp(defaults: AppDefaults.forApp("local.pauta"), hosted: true, version: PluginLocation.version(dso: #dsohandle))
        made = app
        return app
    }

    var contractVersion: Int { neyPluginContractVersion }

    func start(host: NeyHost) {
        MainActor.assumeIsolated {
            app.onOpenPermissions = { host.openPermissions() }
            // Opcional no contrato v1: NeyHub antigo sem showScreen só abre o link.
            if host.responds(to: #selector(NeyHost.showScreen(id:))) {
                app.onShowScreen = { host.showScreen?(id: "local.pauta") }
            }
            app.start()
        }
    }

    func stop() { MainActor.assumeIsolated { app.stop() } }
    func setMenuBarVisible(_ visible: Bool) { MainActor.assumeIsolated { app.setMenuBarVisible(visible) } }
    func makeScreen() -> NSViewController? { MainActor.assumeIsolated { app.makeScreen() } }
    func makeSettings() -> NSViewController { MainActor.assumeIsolated { app.makeSettings() } }
    func notificationCategories() -> Set<UNNotificationCategory> { MainActor.assumeIsolated { app.notificationCategories() } }
    func handleNotification(identifier: String, actionIdentifier: String) {
        MainActor.assumeIsolated { app.handleNotification(identifier: identifier, actionIdentifier: actionIdentifier) }
    }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(PautaEntry()).toOpaque()
}
