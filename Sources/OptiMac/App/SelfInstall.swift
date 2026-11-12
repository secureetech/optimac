import AppKit

/// Installation dans le dossier Applications. Lancé depuis l'image disque (.dmg) ou depuis Téléchargements,
/// OptiMac ne peut ni apparaître dans les Applications ni se relancer au démarrage du Mac :
/// il propose donc de s'installer lui-même, puis redémarre depuis Applications.
enum SelfInstall {
    static let target = URL(fileURLWithPath: "/Applications/OptiMac.app")

    static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(FS.home.appendingPathComponent("Applications").path + "/")
    }

    /// Renvoie vrai si OptiMac s'est installé et va se relancer (il faut alors arrêter le démarrage en cours).
    static func offerIfNeeded() -> Bool {
        guard !isInstalled, Bundle.main.bundleURL.pathExtension == "app" else { return false }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Installer OptiMac sur ce Mac ?"
        a.informativeText = "OptiMac va se copier dans le dossier Applications. Il apparaîtra alors dans vos applications et se lancera à chaque démarrage du Mac pour veiller sur lui."
        a.addButton(withTitle: "Installer")
        a.addButton(withTitle: "Plus tard")
        guard a.runModal() == .alertFirstButtonReturn else { return false }

        let source = Bundle.main.bundleURL
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        if (try? fm.copyItem(at: source, to: target)) == nil {
            // Dossier Applications protégé : même copie avec le mot de passe du Mac.
            Shell.admin(["rm -rf \(Shell.quote(target.path))", "cp -R \(Shell.quote(source.path)) \(Shell.quote(target.path))",
                         "chown -R \(getuid()) \(Shell.quote(target.path))"],
                        prompt: "OptiMac s'installe dans le dossier Applications.")
        }
        guard fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/OptiMac").path) else {
            let e = NSAlert()
            e.messageText = "Installation impossible"
            e.informativeText = "Glissez l'icône OptiMac sur le dossier Applications, puis ouvrez OptiMac depuis Applications."
            e.runModal()
            return false
        }
        // Sans cette étiquette de téléchargement, macOS ouvre la copie sans nouvel avertissement.
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
        Shell.run("/usr/bin/open", ["-n", target.path, "--args", "--fresh"])
        return true
    }
}
