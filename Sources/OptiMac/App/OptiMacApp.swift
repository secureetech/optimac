import SwiftUI
import AppKit
import UserNotifications

/// Point d'entrée d'OptiMac.
@main
@MainActor
enum OptiMacMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    let settings = AppSettings()
    let license = LicenseManager()
    let monitor = Monitor()
    let updater = Updater()
    lazy var model = Model(license: license, settings: settings)

    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var hourly: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        settings.applyAppearance()
        installErrorReporting()
        buildMenu()
        buildStatusItem()
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestPermission()

        // Lancement à l'ouverture de session (agent LaunchAgents, compatible macOS 11)
        if settings.launchAtLogin { StartupEngine.setLaunchAtLogin(true) }

        let atLogin = CommandLine.arguments.contains("--login")
        if !atLogin || settings.openWindowAtLogin {
            showWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        Task {
            await license.bootstrap()
            await updater.check()
            if let v = updater.latest {
                Notifier.post("Mise à jour d'OptiMac disponible", "La version \(v) est prête. Ouvrez OptiMac › Paramètres pour l'installer.")
            }
            if atLogin {
                if settings.notifStartup && !license.isPremium {
                    Notifier.post("OptiMac veille sur votre Mac", "Lancez une analyse pour voir ce qui peut être nettoyé.")
                }
                if license.isPremium && settings.autoClean == .startup { model.autoCleanNow() }
            }
            model.backgroundTick()
        }

        hourly = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.backgroundTick()
                await self?.license.heartbeat()
            }
        }
    }

    // MARK: Fenêtre

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let root = Themed { RootView() }
                .environmentObject(model)
                .environmentObject(license)
                .environmentObject(settings)
                .environmentObject(monitor)
                .environmentObject(updater)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.title = "OptiMac"
            w.minSize = NSSize(width: 1080, height: 720)
            w.contentView = NSHostingView(rootView: root)
            w.center()
            w.setFrameAutosaveName("OptiMacMain")
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // OptiMac reste actif dans la barre des menus (comme OptiPC dans la zone de notification).
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Notification cliquée → ouvrir la fenêtre
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showWindow() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: Icône dans la barre des menus (près de l'horloge)

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = Logo.image?.copy() as? NSImage {
            img.size = NSSize(width: 18, height: 18)
            item.button?.image = img
        } else {
            item.button?.title = "S"
        }
        item.button?.toolTip = "OptiMac"
        let menu = NSMenu()
        menu.addItem(withTitle: "Ouvrir OptiMac", action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Analyser mon Mac", action: #selector(menuScan), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Nettoyer maintenant", action: #selector(menuClean), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Libérer la mémoire", action: #selector(menuMemory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Être rappelé par un technicien", action: #selector(menuCallback), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Passer à Premium", action: #selector(menuPremium), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter OptiMac", action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func menuOpen() { showWindow() }
    @objc private func menuScan() { showWindow(); model.section = .home; model.startScan() }
    @objc private func menuClean() { showWindow(); model.section = .clean; model.loadCleanup() }
    @objc private func menuMemory() { model.freeMemory() }
    @objc private func menuCallback() { showWindow(); model.showCallback = true }
    @objc private func menuPremium() { showWindow(); model.premiumFeature = nil; model.showPremium = true }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuAbout() { showWindow(); model.section = .settings }
    @objc private func menuSettings() { showWindow(); model.section = .settings }

    // MARK: Menu de l'application

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "À propos d'OptiMac", action: #selector(menuAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Paramètres…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Masquer OptiMac", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quitter OptiMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Édition")
        edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let win = NSMenu(title: "Fenêtre")
        win.addItem(withTitle: "Réduire", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Fermer", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        NSApp.mainMenu = main
    }

    // MARK: Remontée des erreurs vers le serveur SecureeTech

    private func installErrorReporting() {
        NSSetUncaughtExceptionHandler { e in
            ErrorLog.write("Exception : \(e.name.rawValue) — \(e.reason ?? "")")
            ErrorReport.send("Exception : \(e.name.rawValue) — \(e.reason ?? "")", wait: true)
        }
    }
}

/// Envoi non bloquant des erreurs à api.secureetech.com (sans donnée personnelle).
enum ErrorReport {
    static func send(_ message: String, wait: Bool = false) {
        var req = URLRequest(url: LicenseManager.api.appendingPathComponent("/v1/error-report"))
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["product": "optimac", "version": SystemInfo.appVersion, "os": SystemInfo.osVersion,
                                   "machine_id": SystemInfo.machineID, "message": String(message.prefix(2000))]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
        if wait { _ = sem.wait(timeout: .now() + 3) }
    }
}
