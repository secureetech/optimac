import AppKit

/// Anti-arnaque : alerte dès qu'un logiciel de prise en main à distance s'ouvre sur ce Mac.
/// L'assistance SecureeTech (liste blanche) et les logiciels approuvés par l'utilisateur ne déclenchent rien.
@MainActor
final class RemoteWatch {
    private var settings: AppSettings?
    private var showing = false

    private var trusted: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "trustedRemoteTools") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "trustedRemoteTools") }
    }

    func start(settings: AppSettings) {
        self.settings = settings
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.check(app) }
        }
    }

    private func check(_ app: NSRunningApplication) {
        guard settings?.remoteAlert == true, !showing else { return }
        let text = (app.localizedName ?? "") + " " + (app.bundleIdentifier ?? "") + " " + (app.bundleURL?.lastPathComponent ?? "")
        guard let tool = ThreatEngine.remoteTool(in: text), !trusted.contains(tool) else { return }

        showing = true
        Sound.alert.play()
        ActivityLog.add("Alerte : \(tool) (prise en main à distance) vient de s'ouvrir")
        Notifier.post("Prise en main à distance détectée", "\(tool) vient de s'ouvrir sur votre Mac.")
        NSApp.activate(ignoringOtherApps: true)

        let a = NSAlert()
        a.alertStyle = .critical
        a.messageText = "Quelqu'un peut prendre le contrôle de votre Mac"
        a.informativeText = """
        « \(tool) » vient de s'ouvrir. Ce logiciel permet à une autre personne de voir votre écran et d'utiliser votre Mac à distance.

        Si un inconnu vous a demandé de l'ouvrir par téléphone (faux Microsoft, faux Apple, fausse banque…), raccrochez : c'est une arnaque.

        Un doute ? Appelez SecureeTech au \(Links.support).
        """
        a.addButton(withTitle: "Fermer \(tool) maintenant")
        a.addButton(withTitle: "C'est moi qui l'ai ouvert")
        a.addButton(withTitle: "Toujours autoriser \(tool)")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            app.forceTerminate()
            ActivityLog.add("\(tool) fermé par l'utilisateur après l'alerte")
        case .alertThirdButtonReturn:
            trusted.insert(tool)
        default:
            break
        }
        showing = false
    }
}
