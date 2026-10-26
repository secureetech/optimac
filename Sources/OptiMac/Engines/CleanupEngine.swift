import Foundation

/// Une catégorie de fichiers inutiles (caches, journaux, corbeille…).
struct CleanCategory: Identifiable {
    enum Mode { case contents, items }
    let id: String
    let name: String
    let detail: String
    let icon: String
    var items: [URL]
    var size: Int64
    var selected: Bool
    /// Incluse dans le nettoyage en un clic.
    let safe: Bool
    let mode: Mode
}

/// Nettoyage du disque : l'équivalent Mac du « Nettoyage de disque » de Windows.
enum CleanupEngine {
    private static var browserCacheDirs: [URL] {
        var dirs: [URL] = [
            FS.lib("Caches/com.apple.Safari"),
            FS.lib("Containers/com.apple.Safari/Data/Library/Caches"),
            FS.lib("Caches/Google/Chrome"),
            FS.lib("Caches/Firefox"),
            FS.lib("Caches/Microsoft Edge"),
            FS.lib("Caches/BraveSoftware"),
            FS.lib("Caches/com.operasoftware.Opera")
        ]
        for base in ["Google/Chrome", "Microsoft Edge", "BraveSoftware/Brave-Browser"] {
            let root = FS.lib("Application Support/\(base)")
            for profile in FS.children(root) where FS.isDir(profile) {
                for sub in ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage"] {
                    let u = profile.appendingPathComponent(sub)
                    if FS.exists(u) { dirs.append(u) }
                }
            }
        }
        return dirs.filter { FS.exists($0) }
    }

    static func scan() -> [CleanCategory] {
        var out: [CleanCategory] = []
        let browserDirs = browserCacheDirs
        let browserPaths = Set(browserDirs.map { $0.standardizedFileURL.path })

        // Caches des applications
        let caches = FS.children(FS.lib("Caches")).filter {
            let p = $0.standardizedFileURL.path
            return !browserPaths.contains(p)
                && !p.contains("com.secureetech.optimac")
                && !["Google", "Firefox", "Microsoft Edge", "BraveSoftware"].contains($0.lastPathComponent)
        }
        out.append(CleanCategory(id: "caches", name: "Caches des applications",
                                 detail: "Fichiers temporaires recréés automatiquement par les applications.",
                                 icon: "shippingbox", items: caches, size: FS.size(of: caches),
                                 selected: true, safe: true, mode: .contents))

        out.append(CleanCategory(id: "browsers", name: "Caches des navigateurs",
                                 detail: "Safari, Chrome, Firefox, Edge, Brave. Vos mots de passe et favoris ne sont pas touchés.",
                                 icon: "globe", items: browserDirs, size: FS.size(of: browserDirs),
                                 selected: true, safe: true, mode: .contents))

        let logs = [FS.lib("Logs")].filter(FS.exists)
        let logItems = logs.flatMap { FS.children($0) }.filter { !$0.lastPathComponent.contains("OptiMac") }
        out.append(CleanCategory(id: "logs", name: "Journaux et rapports de plantage",
                                 detail: "Historiques techniques des applications, inutiles au quotidien.",
                                 icon: "doc.text", items: logItems, size: FS.size(of: logItems),
                                 selected: true, safe: true, mode: .contents))

        // Fichiers temporaires de plus de 3 jours
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let limit = Date().addingTimeInterval(-3 * 86400)
        let tmpItems = FS.children(tmp).filter { (FS.modDate($0) ?? Date()) < limit }
        out.append(CleanCategory(id: "temp", name: "Fichiers temporaires",
                                 detail: "Fichiers laissés par des applications depuis plus de 3 jours.",
                                 icon: "clock.arrow.circlepath", items: tmpItems, size: FS.size(of: tmpItems),
                                 selected: true, safe: true, mode: .items))

        let trash = FS.home.appendingPathComponent(".Trash")
        let trashItems = FS.children(trash)
        out.append(CleanCategory(id: "trash", name: "Corbeille",
                                 detail: "Les fichiers déjà jetés dans la corbeille.",
                                 icon: "trash", items: trashItems, size: FS.size(of: trashItems),
                                 selected: true, safe: true, mode: .items))

        let mail = FS.lib("Containers/com.apple.mail/Data/Library/Mail Downloads")
        let mailItems = FS.children(mail)
        out.append(CleanCategory(id: "mail", name: "Pièces jointes Mail téléchargées",
                                 detail: "Copies des pièces jointes déjà ouvertes. Elles restent dans vos e-mails.",
                                 icon: "paperclip", items: mailItems, size: FS.size(of: mailItems),
                                 selected: true, safe: true, mode: .items))

        let iosUpd = [FS.lib("iTunes/iPhone Software Updates"), FS.lib("iTunes/iPad Software Updates")].filter(FS.exists)
        let iosUpdItems = iosUpd.flatMap { FS.children($0) }
        out.append(CleanCategory(id: "ios_updates", name: "Mises à jour iPhone / iPad",
                                 detail: "Fichiers d'installation d'iOS déjà utilisés.",
                                 icon: "iphone", items: iosUpdItems, size: FS.size(of: iosUpdItems),
                                 selected: true, safe: true, mode: .items))

        // Vieux installateurs dans Téléchargements (non cochés par défaut)
        let dl = FS.home.appendingPathComponent("Downloads")
        let old = Date().addingTimeInterval(-30 * 86400)
        let installers = FS.children(dl).filter {
            ["dmg", "pkg", "iso", "mpkg"].contains($0.pathExtension.lowercased()) && (FS.modDate($0) ?? Date()) < old
        }
        out.append(CleanCategory(id: "downloads", name: "Anciens installateurs",
                                 detail: "Fichiers .dmg et .pkg téléchargés il y a plus d'un mois.",
                                 icon: "arrow.down.circle", items: installers, size: FS.size(of: installers),
                                 selected: false, safe: false, mode: .items))

        // Sauvegardes iPhone (non cochées par défaut)
        let backups = FS.children(FS.lib("Application Support/MobileSync/Backup")).filter(FS.isDir)
        out.append(CleanCategory(id: "ios_backups", name: "Anciennes sauvegardes iPhone / iPad",
                                 detail: "Copies complètes de vos appareils. À supprimer seulement si vous n'en avez plus besoin.",
                                 icon: "externaldrive", items: backups, size: FS.size(of: backups),
                                 selected: false, safe: false, mode: .items))

        return out.filter { $0.size > 0 || !$0.items.isEmpty }
    }

    /// Nom lisible d'une sauvegarde iPhone.
    static func backupName(_ url: URL) -> String {
        let info = url.appendingPathComponent("Info.plist")
        if let d = NSDictionary(contentsOf: info) {
            let name = d["Device Name"] as? String ?? "Appareil"
            let date = d["Last Backup Date"] as? Date
            return "\(name) — \(Fmt.date(date))"
        }
        return url.lastPathComponent
    }

    /// Nettoie les catégories cochées, sans dépasser `limit` octets (version gratuite).
    static func clean(_ cats: [CleanCategory], limit: Int64?) -> Int64 {
        var freed: Int64 = 0
        for c in cats where c.selected {
            for item in c.items {
                if let limit, freed >= limit { return freed }
                switch c.mode {
                case .contents:
                    if FS.isDir(item) {
                        for child in FS.children(item) {
                            if let limit, freed >= limit { return freed }
                            freed += FS.remove(child)
                        }
                    } else {
                        freed += FS.remove(item)
                    }
                case .items:
                    freed += FS.remove(item)
                }
            }
        }
        return freed
    }
}
