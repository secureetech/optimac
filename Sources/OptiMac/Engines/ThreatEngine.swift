import Foundation
import AppKit

struct Threat: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case check = 0, medium = 1, high = 2
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
        var label: String {
            switch self { case .high: return "Élevé"; case .medium: return "Moyen"; case .check: return "À vérifier" }
        }
    }
    enum Kind: String { case launchItem, app, profile, extensionItem, cron, hosts, process, file, proxy }

    let id: String
    let name: String
    let type: String
    let location: String
    let severity: Severity
    let kind: Kind
    let paths: [URL]
    let needsAdmin: Bool
    var detail: String = ""
}

struct QuarantineItem: Codable, Identifiable {
    let id: String
    let name: String
    let original: String
    let stored: String
    let date: Date
}

/// Analyse anti-malware pour Mac. Elle ouvre réellement les fichiers : programmes cachés ou non signés,
/// scripts dangereux (règles de contenu), empreintes connues, faux installateurs, adwares, agents de
/// lancement, profils, extensions, tâches planifiées, fichier hosts, proxy et prise en main à distance.
/// Les logiciels SecureeTech et l'assistance SecureeTech sont en liste blanche (voir Whitelist).
enum ThreatEngine {
    static let adwarePatterns = [
        "mackeeper", "advanced mac cleaner", "advancedmaccleaner", "mac auto fixer", "macautofixer", "mac cleanup pro",
        "smart mac booster", "mac tonic", "mactonic", "mac booster", "macbooster", "mac mechanic", "mac speedup",
        "pirrit", "genieo", "shlayer", "bundlore", "adload", "vsearch", "searchmine", "search baron", "searchbaron",
        "weknow", "chumsearch", "spigot", "installcore", "crossrider", "mughthesec", "operatorsearch", "safefinder",
        "search marquis", "searchmarquis", "bing redirect", "akamaihd", "zako", "trovi", "conduit", "mindspark",
        "myshopcoupon", "shopper helper", "mac file opener", "mac.optimizer", "maccleanerpro", "launchhelper",
        "isearch", "searchpulse", "searchalgo", "chill tab", "chilltab", "spaceship", "tabsearch", "results-hub"
    ]

    /// Familles d'adwares recherchées à l'intérieur même des programmes non signés.
    static let adwareFamilies = ["pirrit", "genieo", "bundlore", "adload", "shlayer", "mughthesec", "vsearch", "crossrider"]

    static let remoteTools = [
        ("AnyDesk", "anydesk"), ("TeamViewer", "teamviewer"), ("RustDesk", "rustdesk"), ("UltraViewer", "ultraviewer"),
        ("Splashtop", "splashtop"), ("LogMeIn", "logmein"), ("ConnectWise / ScreenConnect", "screenconnect"),
        ("ConnectWise Control", "connectwise"), ("Zoho Assist", "zohoassist"), ("Supremo", "supremo"),
        ("AeroAdmin", "aeroadmin"), ("Ammyy Admin", "ammyy"), ("ISL Light", "isl light"), ("GoTo Resolve", "gotoresolve"),
        ("GoToAssist", "gotoassist"), ("Remote Utilities", "remote utilities"), ("Chrome Remote Desktop", "chromoting"),
        ("DWService", "dwagent"), ("HopToDesk", "hoptodesk"), ("Getscreen", "getscreen"), ("RemotePC", "remotepc"),
        ("Iperius Remote", "iperius"), ("BeAnywhere", "beanywhere"), ("NinjaOne", "ninjarmm"), ("Atera", "atera"),
        ("MeshCentral", "meshagent")
    ]

    private static var extraNames: [String] = []

    static func isAdware(_ s: String) -> Bool {
        let l = s.lowercased()
        return adwarePatterns.contains { l.contains($0) } || extraNames.contains { l.contains($0) }
    }

    /// Outil de prise en main à distance reconnu dans un nom, hors liste blanche SecureeTech.
    static func remoteTool(in text: String) -> String? {
        let l = text.lowercased()
        guard let tool = remoteTools.first(where: { l.contains($0.1) }) else { return nil }
        return Whitelist.contains(l) ? nil : tool.0
    }

    // MARK: Analyse

    private enum Zone { case loose, bundle, system }
    private struct Root { let label: String; let url: URL; let zone: Zone; let depth: Int? }

    private static func roots(full: Bool) -> [Root] {
        let h = FS.home
        var r = [
            Root(label: "Téléchargements", url: h.appendingPathComponent("Downloads"), zone: .loose, depth: full ? nil : 3),
            Root(label: "Dossier partagé", url: URL(fileURLWithPath: "/Users/Shared"), zone: .loose, depth: full ? nil : 4),
            Root(label: "Fichiers temporaires", url: URL(fileURLWithPath: "/private/tmp"), zone: .loose, depth: 4),
            Root(label: "Fichiers temporaires", url: URL(fileURLWithPath: "/private/var/tmp"), zone: .loose, depth: 4),
            Root(label: "Données des applications", url: FS.lib("Application Support"), zone: .loose, depth: full ? 6 : 2),
            Root(label: "Applications", url: URL(fileURLWithPath: "/Applications"), zone: .bundle, depth: full ? nil : 4)
        ]
        if full {
            r += [
                Root(label: "Bureau", url: h.appendingPathComponent("Desktop"), zone: .loose, depth: nil),
                Root(label: "Documents", url: h.appendingPathComponent("Documents"), zone: .loose, depth: 8),
                Root(label: "Applications de l'utilisateur", url: h.appendingPathComponent("Applications"), zone: .bundle, depth: nil),
                Root(label: "Bibliothèque de l'utilisateur", url: h.appendingPathComponent("Library"), zone: .system, depth: 5),
                Root(label: "Bibliothèque du Mac", url: URL(fileURLWithPath: "/Library/Application Support"), zone: .system, depth: 5),
                Root(label: "Outils système ajoutés", url: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), zone: .system, depth: 2),
                Root(label: "Programmes ajoutés", url: URL(fileURLWithPath: "/usr/local"), zone: .system, depth: 5),
                Root(label: "Programmes ajoutés", url: URL(fileURLWithPath: "/opt"), zone: .system, depth: 5)
            ]
        }
        return r.filter { FS.exists($0.url) }
    }

    static func scan(full: Bool, progress: ScanProgress, cancelled: @escaping () -> Bool) -> [Threat] {
        progress.set(local: 0, label: "Mise à jour de la base de signatures")
        Signatures.refresh()
        let sig = Signatures.load()
        extraNames = sig.names
        let ignored = Set(UserDefaults.standard.stringArray(forKey: "ignoredThreats") ?? [])

        var steps: [(String, () -> [Threat])] = [
            ("Agents de lancement", { launchItems(full: full, sig: sig, progress: progress) }),
            ("Applications installées", { apps(full: full, progress: progress, cancelled: cancelled) }),
            ("Processus actifs", { processes() }),
            ("Prise en main à distance", { remoteAccess() })
        ]
        for root in roots(full: full) {
            steps.append(("Analyse des fichiers : \(root.label)", { files(root, full: full, sig: sig, progress: progress, cancelled: cancelled) }))
        }
        steps += [
            ("Profils de configuration", { profiles() }),
            ("Extensions des navigateurs", { browserExtensions() }),
            ("Tâches planifiées", { cron() }),
            ("Fichier hosts", { hosts() }),
            ("Proxy internet", { proxy() })
        ]

        var out: [Threat] = []
        for (i, s) in steps.enumerated() {
            if cancelled() { break }
            progress.set(local: Double(i) / Double(steps.count), label: s.0)
            out.append(contentsOf: s.1())
        }
        progress.set(local: 1, label: "Terminé")
        var seen = Set<String>()
        return out.filter { !ignored.contains($0.id) && seen.insert($0.id).inserted }
                  .sorted { $0.severity > $1.severity }
    }

    // MARK: Fichiers

    private static let skippedDirs: Set<String> = ["node_modules", ".git", "Caches", "Photos Library.photoslibrary", "Mail", "Messages",
                                                   "MobileSync", "CloudStorage", "Mobile Documents", ".Trash", "Quarantaine"]
    private static let scriptExts: Set<String> = ["sh", "command", "tool", "bash", "zsh", "py", "pl", "rb", "scpt", "applescript", "js"]
    private static let installerExts: Set<String> = ["dmg", "pkg", "mpkg", "zip", "iso"]
    private static let machMagics: Set<UInt32> = [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA]

    private static func files(_ root: Root, full: Bool, sig: Signatures, progress: ScanProgress, cancelled: () -> Bool) -> [Threat] {
        var out: [Threat] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isExecutableKey, .fileSizeKey]
        let keySet = Set(keys)
        guard let en = FS.fm.enumerator(at: root.url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return [] }
        var n = 0
        for case let u as URL in en {
            if let d = root.depth, en.level > d { en.skipDescendants(); continue }
            n += 1
            if n % 64 == 0 && cancelled() { break }
            guard let v = try? u.resourceValues(forKeys: keySet) else { continue }
            if v.isDirectory == true {
                if skippedDirs.contains(u.lastPathComponent) { en.skipDescendants() }
                continue
            }
            guard v.isRegularFile == true else { continue }
            progress.tick(u.path)
            if let t = inspect(u, v, zone: root.zone, full: full, sig: sig) { out.append(t) }
        }
        return out
    }

    private static func shortPath(_ u: URL) -> String { u.path.replacingOccurrences(of: FS.home.path, with: "~") }

    private static func fileThreat(_ u: URL, _ name: String, _ sev: Threat.Severity, _ detail: String, type: String = "Fichier suspect") -> Threat {
        Threat(id: u.path, name: name, type: type, location: shortPath(u), severity: sev, kind: .file, paths: [u],
               needsAdmin: !FS.fm.isWritableFile(atPath: u.deletingLastPathComponent().path), detail: detail)
    }

    private static func inspect(_ u: URL, _ v: URLResourceValues, zone: Zone, full: Bool, sig: Signatures) -> Threat? {
        let name = u.lastPathComponent
        let lname = name.lowercased()
        let ext = u.pathExtension.lowercased()
        let size = v.fileSize ?? 0
        if Whitelist.contains(u.path) { return nil }

        // Faux installateurs téléchargés
        if zone == .loose, installerExts.contains(ext) {
            if isAdware(lname) {
                return fileThreat(u, name, .high, "Installateur d'un logiciel publicitaire ou d'un faux optimiseur connu.", type: "Installateur dangereux")
            }
            if lname.contains("flash") && (lname.contains("player") || lname.contains("install")) {
                return fileThreat(u, name, .high, "Flash Player n'existe plus depuis 2020 : ce fichier est un faux installateur.", type: "Faux installateur")
            }
            return nil
        }

        let isScriptExt = scriptExts.contains(ext)
        guard size > 0, size <= 60_000_000, v.isExecutable == true || isScriptExt else { return nil }
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        let head = (try? h.read(upToCount: 4)) ?? Data()
        var isMach = false
        if head.count == 4 {
            let magic = head.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            isMach = machMagics.contains(magic)
        }
        let isScript = isScriptExt || head.starts(with: [0x23, 0x21])
        guard isMach || isScript else { try? h.close(); return nil }
        let body = (try? h.read(upToCount: isMach ? 1_000_000 : 256_000)) ?? Data()
        try? h.close()

        // Empreinte connue
        if !sig.hashes.isEmpty, size <= 30_000_000, let hash = Signatures.sha256(u), let known = sig.hashes[hash] {
            return fileThreat(u, name, .high, "Malware connu : \(known).", type: "Malware")
        }

        // Programme caché (hors applications)
        if isMach, zone != .bundle, name.hasPrefix("."), name.count > 1 {
            return fileThreat(u, name, .high, "Programme caché : son nom commence par un point pour ne pas être vu.", type: "Programme caché")
        }
        guard zone == .loose else { return nil }

        if isScript {
            let text = String(decoding: head + body, as: UTF8.self).lowercased()
            if let r = sig.rules.first(where: { $0.matches(text) }) {
                return fileThreat(u, name, r.severity, r.detail, type: r.name)
            }
            return nil
        }

        // Programme (Mach-O) isolé, hors application : signature et contenu
        if u.path.contains(".app/Contents/") || u.path.contains(".framework/") { return nil }
        guard !isSigned(u.path) else { return nil }
        let text = String(decoding: body, as: UTF8.self).lowercased()
        if let fam = adwareFamilies.first(where: { text.contains($0) }) {
            return fileThreat(u, name, .high, "Programme non signé de la famille d'adwares « \(fam) ».", type: "Adware")
        }
        let p = u.path
        if p.hasPrefix("/private/tmp/") || p.hasPrefix("/private/var/tmp/") || p.hasPrefix("/Users/Shared/") {
            return fileThreat(u, name, .medium, "Programme non signé déposé dans un dossier temporaire ou partagé.", type: "Programme non signé")
        }
        if full {
            return fileThreat(u, name, .check, "Programme sans signature d'un éditeur. Supprimez-le si vous ne savez pas d'où il vient.", type: "Programme non signé")
        }
        return nil
    }

    // MARK: Agents et démons de lancement

    static var launchDirs: [(URL, Bool)] {
        [(FS.lib("LaunchAgents"), false),
         (URL(fileURLWithPath: "/Library/LaunchAgents"), true),
         (URL(fileURLWithPath: "/Library/LaunchDaemons"), true)]
    }

    static func launchProgram(_ plist: URL) -> (label: String, program: String) {
        guard let d = NSDictionary(contentsOf: plist) else { return (plist.deletingPathExtension().lastPathComponent, "") }
        let label = d["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
        let program = (d["Program"] as? String) ?? ((d["ProgramArguments"] as? [String])?.first ?? "")
        return (label, program)
    }

    private static func launchItems(full: Bool, sig: Signatures, progress: ScanProgress) -> [Threat] {
        var out: [Threat] = []
        for (dir, admin) in launchDirs {
            for plist in FS.children(dir) where plist.pathExtension == "plist" {
                progress.tick(plist.path)
                let (label, program) = launchProgram(plist)
                if label.hasPrefix("com.apple.") || Whitelist.contains(label, program, plist.lastPathComponent) { continue }
                let both = label + " " + program + " " + plist.lastPathComponent
                let command = ((NSDictionary(contentsOf: plist)?["ProgramArguments"] as? [String]) ?? []).joined(separator: " ").lowercased()
                var sev: Threat.Severity?
                var why = ""
                if isAdware(both) {
                    sev = .high; why = "Logiciel publicitaire ou faux optimiseur connu"
                } else if let r = sig.rules.first(where: { $0.matches(command) }) {
                    sev = .high; why = r.name
                } else if program.hasPrefix("/tmp/") || program.hasPrefix("/private/tmp/") || program.hasPrefix("/Users/Shared/") {
                    sev = .high; why = "Programme lancé depuis un dossier temporaire"
                } else if program.split(separator: "/").contains(where: { $0.hasPrefix(".") && $0.count > 1 }) {
                    sev = .high; why = "Programme caché"
                } else if !program.isEmpty, FS.fm.fileExists(atPath: program), !program.hasPrefix("/System"), !program.hasPrefix("/usr/bin"),
                          !program.hasPrefix("/bin"), !isSigned(program) {
                    sev = .check; why = "Programme non signé lancé automatiquement"
                }
                if let sev {
                    var paths = [plist]
                    if !program.isEmpty, FS.fm.fileExists(atPath: program), !program.hasPrefix("/System"), !program.hasPrefix("/usr"), !program.hasPrefix("/bin") {
                        paths.append(URL(fileURLWithPath: program))
                    }
                    out.append(Threat(id: plist.path, name: label, type: plist.path.contains("LaunchDaemons") ? "Démon système" : "Agent de lancement",
                                      location: plist.path.replacingOccurrences(of: FS.home.path, with: "~"),
                                      severity: sev, kind: .launchItem, paths: paths, needsAdmin: admin, detail: why))
                }
            }
        }
        return out
    }

    static func isSigned(_ path: String) -> Bool {
        let r = Shell.run("/usr/bin/codesign", ["-v", path], timeout: 20)
        return !r.err.contains("not signed at all")
    }

    // MARK: Applications

    private static func apps(full: Bool, progress: ScanProgress, cancelled: () -> Bool) -> [Threat] {
        var out: [Threat] = []
        for dir in [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications")] {
            for app in FS.children(dir) where app.pathExtension == "app" {
                if cancelled() { return out }
                progress.tick(app.path)
                let name = app.deletingPathExtension().lastPathComponent
                let bid = Bundle(url: app)?.bundleIdentifier ?? ""
                if Whitelist.contains(name, bid) || bid.hasPrefix("com.apple.") { continue }
                if isAdware(name + " " + bid) {
                    out.append(Threat(id: app.path, name: name, type: "Faux optimiseur / adware", location: app.path,
                                      severity: .high, kind: .app, paths: [app], needsAdmin: false,
                                      detail: "Logiciel connu pour afficher de fausses alertes ou de la publicité"))
                } else if full, !isSigned(app.path) {
                    out.append(Threat(id: app.path, name: name, type: "Application non signée", location: app.path,
                                      severity: .check, kind: .app, paths: [app], needsAdmin: false,
                                      detail: "Aucun éditeur n'a signé cette application. Supprimez-la si vous ne savez pas d'où elle vient."))
                }
            }
        }
        // Dossiers d'adwares typiques dans Application Support
        for d in FS.children(FS.lib("Application Support")) where isAdware(d.lastPathComponent) && !Whitelist.contains(d.lastPathComponent) {
            out.append(Threat(id: d.path, name: d.lastPathComponent, type: "Fichiers d'adware",
                              location: d.path.replacingOccurrences(of: FS.home.path, with: "~"),
                              severity: .high, kind: .app, paths: [d], needsAdmin: false))
        }
        return out
    }

    // MARK: Profils de configuration

    static func profileIdentifiers() -> [String] {
        let r = Shell.run("/usr/bin/profiles", ["-P"], timeout: 30)
        var ids: [String] = []
        for line in r.out.components(separatedBy: .newlines) {
            if let range = line.range(of: "profileIdentifier:") {
                let id = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !id.isEmpty { ids.append(id) }
            }
        }
        return Array(Set(ids))
    }

    private static func profiles() -> [Threat] {
        profileIdentifiers().filter { !Whitelist.contains($0) }.map { id in
            let sus = isAdware(id) || id.lowercased().contains("search") || id.lowercased().contains("safari") || id.lowercased().contains("chrome")
            return Threat(id: "profile:" + id, name: id, type: "Profil de configuration", location: "Réglages Système › Profils",
                          severity: sus ? .high : .medium, kind: .profile, paths: [], needsAdmin: true,
                          detail: "Un profil peut imposer une page d'accueil, un moteur de recherche ou un proxy")
        }
    }

    // MARK: Extensions de navigateurs

    static func chromiumProfiles() -> [(browser: String, url: URL)] {
        var out: [(String, URL)] = []
        for (name, base) in [("Chrome", "Google/Chrome"), ("Edge", "Microsoft Edge"), ("Brave", "BraveSoftware/Brave-Browser"), ("Opera", "com.operasoftware.Opera")] {
            let root = FS.lib("Application Support/\(base)")
            for p in FS.children(root) where FS.exists(p.appendingPathComponent("Preferences")) {
                out.append((name, p))
            }
        }
        return out
    }

    private static func browserExtensions() -> [Threat] {
        var out: [Threat] = []
        for (browser, profile) in chromiumProfiles() {
            for ext in FS.children(profile.appendingPathComponent("Extensions")) where FS.isDir(ext) {
                guard let ver = FS.children(ext).first(where: FS.isDir),
                      let data = try? Data(contentsOf: ver.appendingPathComponent("manifest.json")),
                      let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                let name = AppsEngine.resolveExtName(m["name"] as? String ?? ext.lastPathComponent, dir: ver)
                if Whitelist.contains(name) { continue }
                let overrides = m["chrome_settings_overrides"] != nil || (m["chrome_url_overrides"] as? [String: Any])?["newtab"] != nil
                if isAdware(name) || overrides {
                    out.append(Threat(id: ext.path, name: name, type: "Extension \(browser)",
                                      location: browser + " › Extensions", severity: isAdware(name) ? .high : .medium,
                                      kind: .extensionItem, paths: [ext], needsAdmin: false,
                                      detail: overrides ? "Modifie la page d'accueil, le nouvel onglet ou la recherche" : "Extension publicitaire connue"))
                }
            }
        }
        return out
    }

    // MARK: Tâches planifiées, hosts, proxy, processus

    private static func cron() -> [Threat] {
        let r = Shell.run("/usr/bin/crontab", ["-l"], timeout: 10)
        let lines = r.out.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty else { return [] }
        return [Threat(id: "cron", name: "\(lines.count) tâche(s) planifiée(s)", type: "Tâche planifiée (cron)",
                       location: "crontab", severity: lines.contains(where: isAdware) ? .high : .check, kind: .cron,
                       paths: [], needsAdmin: false, detail: lines.prefix(2).joined(separator: " · "))]
    }

    private static func hosts() -> [Threat] {
        guard let s = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else { return [] }
        let suspicious = s.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return false }
            let l = t.lowercased()
            if l.contains("localhost") || l.contains("broadcasthost") { return false }
            return ["apple.com", "google.", "bing.com", "microsoft.com", "icloud.com", "secureetech", "bank", "paypal", "update"].contains { l.contains($0) }
        }
        guard !suspicious.isEmpty else { return [] }
        return [Threat(id: "hosts", name: "Fichier hosts modifié", type: "Redirection de sites",
                       location: "/etc/hosts", severity: .high, kind: .hosts, paths: [], needsAdmin: true,
                       detail: suspicious.prefix(2).joined(separator: " · "))]
    }

    /// Un proxy actif fait passer toute la navigation par un autre ordinateur.
    private static func proxy() -> [Threat] {
        let r = Shell.run("/usr/sbin/scutil", ["--proxy"], timeout: 10)
        var on: [String] = []
        var server = ""
        for line in r.out.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: " : ")
            guard parts.count == 2 else { continue }
            let k = parts[0].trimmingCharacters(in: .whitespaces), val = parts[1].trimmingCharacters(in: .whitespaces)
            if ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable"].contains(k), val == "1" { on.append(k) }
            if ["HTTPProxy", "HTTPSProxy", "SOCKSProxy", "ProxyAutoConfigURLString"].contains(k), server.isEmpty { server = val }
        }
        guard !on.isEmpty else { return [] }
        let local = server.hasPrefix("127.") || server.contains("localhost")
        return [Threat(id: "proxy", name: "Proxy internet actif", type: "Navigation détournée",
                       location: server.isEmpty ? "Réglages réseau" : server, severity: local ? .high : .check, kind: .proxy,
                       paths: [], needsAdmin: true,
                       detail: "Toute la navigation passe par un intermédiaire. Normal en entreprise, anormal chez un particulier.")]
    }

    private static func processes() -> [Threat] {
        let r = Shell.run("/bin/ps", ["-axo", "pid=,comm="], timeout: 15)
        var out: [Threat] = []
        for line in r.out.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(of: " ") else { continue }
            let path = String(t[sp...]).trimmingCharacters(in: .whitespaces)
            if Whitelist.contains(path) { continue }
            if isAdware(path) || path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") {
                out.append(Threat(id: "proc:" + path, name: URL(fileURLWithPath: path).lastPathComponent, type: "Processus suspect",
                                  location: path, severity: .high, kind: .process, paths: [URL(fileURLWithPath: path)], needsAdmin: false))
            }
        }
        return out
    }

    private static func remoteAccess() -> [Threat] {
        var out: [Threat] = []
        let apps = FS.children(URL(fileURLWithPath: "/Applications")) + FS.children(FS.home.appendingPathComponent("Applications"))
        for app in apps where app.pathExtension == "app" {
            let bid = Bundle(url: app)?.bundleIdentifier ?? ""
            if let tool = remoteTool(in: app.deletingPathExtension().lastPathComponent + " " + bid) {
                out.append(Threat(id: app.path, name: tool, type: "Prise en main à distance", location: app.path,
                                  severity: .check, kind: .app, paths: [app], needsAdmin: false,
                                  detail: "Permet de contrôler ce Mac à distance. Supprimez-le si vous ne l'avez pas installé vous-même."))
            }
        }
        // Agent MeshCentral relié à un autre serveur que celui de SecureeTech
        if !Whitelist.meshIsSecureeTech {
            for dir in Whitelist.meshDirs where FS.exists(URL(fileURLWithPath: dir)) && !dir.lowercased().contains("secureetech") {
                out.append(Threat(id: dir, name: "MeshCentral (serveur inconnu)", type: "Prise en main à distance", location: dir,
                                  severity: .medium, kind: .app, paths: [URL(fileURLWithPath: dir)], needsAdmin: true,
                                  detail: "Agent de prise en main relié à un serveur qui n'est pas celui de SecureeTech."))
            }
        }
        return out
    }

    // MARK: Actions

    static var quarantineDir: URL {
        let u = FS.supportDir.appendingPathComponent("Quarantaine")
        FS.ensureDir(u)
        return u
    }
    static var quarantineIndex: URL { quarantineDir.appendingPathComponent("index.json") }

    static func loadQuarantine() -> [QuarantineItem] {
        guard let d = try? Data(contentsOf: quarantineIndex) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([QuarantineItem].self, from: d)) ?? []
    }

    static func saveQuarantine(_ items: [QuarantineItem]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(items) { try? d.write(to: quarantineIndex, options: .atomic) }
    }

    /// Neutralise puis met en quarantaine (restaurable) ou supprime les menaces.
    static func remove(_ threats: [Threat], quarantine: Bool) -> Int {
        var adminCmds: [String] = []
        var done = 0
        var q = loadQuarantine()
        let uid = getuid()
        for t in threats {
            switch t.kind {
            case .profile:
                let id = String(t.id.dropFirst("profile:".count))
                adminCmds.append("/usr/bin/profiles -R -p \(Shell.quote(id))")
                done += 1
            case .cron:
                if quarantine {
                    let r = Shell.run("/usr/bin/crontab", ["-l"])
                    try? r.out.write(to: quarantineDir.appendingPathComponent("crontab-\(Int(Date().timeIntervalSince1970)).txt"), atomically: true, encoding: .utf8)
                }
                Shell.run("/usr/bin/crontab", ["-r"])
                done += 1
            case .hosts:
                adminCmds.append("cp /etc/hosts /etc/hosts.optimac-sauvegarde")
                adminCmds.append("grep -vE 'apple\\.com|google\\.|bing\\.com|microsoft\\.com|icloud\\.com|secureetech|bank|paypal|update' /etc/hosts.optimac-sauvegarde > /etc/hosts")
                adminCmds.append("dscacheutil -flushcache; killall -HUP mDNSResponder")
                done += 1
            case .proxy:
                let services = Shell.run("/usr/sbin/networksetup", ["-listallnetworkservices"], timeout: 10).out
                    .components(separatedBy: .newlines).dropFirst().filter { !$0.isEmpty && !$0.hasPrefix("*") }
                for svc in services {
                    for flag in ["-setwebproxystate", "-setsecurewebproxystate", "-setsocksfirewallproxystate", "-setautoproxystate"] {
                        adminCmds.append("/usr/sbin/networksetup \(flag) \(Shell.quote(svc)) off")
                    }
                }
                done += 1
            case .process:
                for p in t.paths { Shell.run("/usr/bin/pkill", ["-9", "-f", p.path]) }
                done += 1
            default:
                if t.kind == .launchItem, let plist = t.paths.first {
                    if t.needsAdmin {
                        adminCmds.append("launchctl bootout system \(Shell.quote(plist.path))")
                    } else {
                        Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", plist.path])
                    }
                }
                for p in t.paths {
                    for app in NSWorkspace.shared.runningApplications where app.bundleURL == p || app.executableURL == p {
                        app.forceTerminate()
                    }
                    Shell.run("/usr/bin/pkill", ["-9", "-f", p.path])
                    if quarantine {
                        let dest = quarantineDir.appendingPathComponent(UUID().uuidString + "-" + p.lastPathComponent)
                        var moved = (try? FS.fm.moveItem(at: p, to: dest)) != nil
                        if !moved && (t.needsAdmin || !FS.fm.isWritableFile(atPath: p.deletingLastPathComponent().path)) {
                            adminCmds.append("mv \(Shell.quote(p.path)) \(Shell.quote(dest.path)); chown -R \(uid) \(Shell.quote(dest.path))")
                            moved = true
                        }
                        if moved {
                            q.append(QuarantineItem(id: UUID().uuidString, name: t.name, original: p.path, stored: dest.path, date: Date()))
                        }
                    } else if FS.remove(p) == 0 && FS.exists(p) {
                        adminCmds.append("chflags -R nouchg,noschg \(Shell.quote(p.path)); rm -rf \(Shell.quote(p.path))")
                    }
                }
                done += 1
            }
        }
        if !adminCmds.isEmpty {
            Shell.admin(adminCmds, prompt: "OptiMac doit supprimer des éléments dangereux protégés par macOS.")
        }
        saveQuarantine(q)
        return done
    }

    static func restore(_ item: QuarantineItem) {
        let src = URL(fileURLWithPath: item.stored), dst = URL(fileURLWithPath: item.original)
        if (try? FS.fm.moveItem(at: src, to: dst)) == nil {
            Shell.admin(["mv \(Shell.quote(src.path)) \(Shell.quote(dst.path))"])
        }
        saveQuarantine(loadQuarantine().filter { $0.id != item.id })
    }

    static func purge(_ item: QuarantineItem) {
        FS.remove(URL(fileURLWithPath: item.stored))
        saveQuarantine(loadQuarantine().filter { $0.id != item.id })
    }

    static func ignore(_ ids: [String]) {
        var s = Set(UserDefaults.standard.stringArray(forKey: "ignoredThreats") ?? [])
        ids.forEach { s.insert($0) }
        UserDefaults.standard.set(Array(s), forKey: "ignoredThreats")
    }

    static func clearIgnored() { UserDefaults.standard.removeObject(forKey: "ignoredThreats") }
}
