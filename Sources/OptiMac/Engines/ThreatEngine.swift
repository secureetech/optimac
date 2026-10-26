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
    enum Kind: String { case launchItem, app, profile, extensionItem, cron, hosts, process }

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

/// Analyse anti-malware pour Mac : adwares, faux optimiseurs, agents de lancement suspects,
/// profils de configuration, extensions qui détournent la recherche, tâches planifiées,
/// fichier hosts et logiciels de prise en main à distance.
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

    static let remoteTools = [
        ("AnyDesk", "anydesk"), ("TeamViewer", "teamviewer"), ("RustDesk", "rustdesk"), ("UltraViewer", "ultraviewer"),
        ("Splashtop", "splashtop"), ("LogMeIn", "logmein"), ("ConnectWise / ScreenConnect", "screenconnect"),
        ("ConnectWise Control", "connectwise"), ("Zoho Assist", "zohoassist"), ("Supremo", "supremo"),
        ("AeroAdmin", "aeroadmin"), ("Ammyy Admin", "ammyy"), ("ISL Light", "isl light"), ("GoTo Resolve", "gotoresolve"),
        ("GoToAssist", "gotoassist"), ("Remote Utilities", "remote utilities"), ("Chrome Remote Desktop", "chromoting"),
        ("DWService", "dwagent"), ("HopToDesk", "hoptodesk"), ("Getscreen", "getscreen"), ("RemotePC", "remotepc"),
        ("Iperius Remote", "iperius"), ("BeAnywhere", "beanywhere"), ("NinjaOne", "ninjarmm"), ("Atera", "atera")
    ]

    static func isAdware(_ s: String) -> Bool {
        let l = s.lowercased()
        return adwarePatterns.contains { l.contains($0) }
    }

    static func scan(full: Bool, step: @escaping (String, Double) -> Void, cancelled: @escaping () -> Bool) -> [Threat] {
        var out: [Threat] = []
        let ignored = Set(UserDefaults.standard.stringArray(forKey: "ignoredThreats") ?? [])
        let steps: [(String, () -> [Threat])] = [
            ("Agents de lancement", { launchItems(full: full) }),
            ("Applications installées", { apps() }),
            ("Profils de configuration", { profiles() }),
            ("Extensions des navigateurs", { browserExtensions() }),
            ("Tâches planifiées", { cron() }),
            ("Fichier hosts", { hosts() }),
            ("Processus actifs", { processes() }),
            ("Prise en main à distance", { remoteAccess() })
        ]
        for (i, s) in steps.enumerated() {
            if cancelled() { break }
            step(s.0, Double(i) / Double(steps.count))
            out.append(contentsOf: s.1())
            if full { Thread.sleep(forTimeInterval: 0.4) }
        }
        step("Terminé", 1)
        var seen = Set<String>()
        return out.filter { !ignored.contains($0.id) && seen.insert($0.id).inserted }
                  .sorted { $0.severity > $1.severity }
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

    private static func launchItems(full: Bool) -> [Threat] {
        var out: [Threat] = []
        for (dir, admin) in launchDirs {
            for plist in FS.children(dir) where plist.pathExtension == "plist" {
                let (label, program) = launchProgram(plist)
                if label.hasPrefix("com.apple.") { continue }
                let both = label + " " + program + " " + plist.lastPathComponent
                var sev: Threat.Severity?
                var why = ""
                if isAdware(both) {
                    sev = .high; why = "Logiciel publicitaire ou faux optimiseur connu"
                } else if program.hasPrefix("/tmp/") || program.hasPrefix("/private/tmp/") || program.hasPrefix("/Users/Shared/") {
                    sev = .high; why = "Programme lancé depuis un dossier temporaire"
                } else if program.split(separator: "/").contains(where: { $0.hasPrefix(".") && $0.count > 1 }) {
                    sev = .high; why = "Programme caché"
                } else if full, !program.isEmpty, FS.fm.fileExists(atPath: program), !isSigned(program) {
                    sev = .medium; why = "Programme non signé lancé automatiquement"
                }
                if let sev {
                    var paths = [plist]
                    if !program.isEmpty, FS.fm.fileExists(atPath: program), !program.hasPrefix("/System"), !program.hasPrefix("/usr") {
                        paths.append(URL(fileURLWithPath: program))
                    }
                    out.append(Threat(id: plist.path, name: label, type: admin ? "Démon système" : "Agent de lancement",
                                      location: plist.path.replacingOccurrences(of: FS.home.path, with: "~"),
                                      severity: sev, kind: .launchItem, paths: paths, needsAdmin: admin, detail: why))
                }
            }
        }
        return out
    }

    static func isSigned(_ path: String) -> Bool {
        let r = Shell.run("/usr/bin/codesign", ["-v", path], timeout: 15)
        return !r.err.contains("not signed at all")
    }

    // MARK: Applications

    private static func apps() -> [Threat] {
        var out: [Threat] = []
        for dir in [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications")] {
            for app in FS.children(dir) where app.pathExtension == "app" {
                let name = app.deletingPathExtension().lastPathComponent
                let bid = Bundle(url: app)?.bundleIdentifier ?? ""
                if isAdware(name + " " + bid) {
                    out.append(Threat(id: app.path, name: name, type: "Faux optimiseur / adware", location: app.path,
                                      severity: .high, kind: .app, paths: [app], needsAdmin: false,
                                      detail: "Logiciel connu pour afficher de fausses alertes ou de la publicité"))
                }
            }
        }
        // Dossiers d'adwares typiques dans Application Support
        for d in FS.children(FS.lib("Application Support")) where isAdware(d.lastPathComponent) {
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
        profileIdentifiers().map { id in
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

    // MARK: Tâches planifiées, hosts, processus

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

    private static func processes() -> [Threat] {
        let r = Shell.run("/bin/ps", ["-axo", "pid=,comm="], timeout: 15)
        var out: [Threat] = []
        for line in r.out.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(of: " ") else { continue }
            let path = String(t[sp...]).trimmingCharacters(in: .whitespaces)
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
            let n = app.deletingPathExtension().lastPathComponent.lowercased()
            if let tool = remoteTools.first(where: { n.contains($0.1) }) {
                out.append(Threat(id: app.path, name: tool.0, type: "Prise en main à distance", location: app.path,
                                  severity: .check, kind: .app, paths: [app], needsAdmin: false,
                                  detail: "Permet de contrôler ce Mac à distance. Supprimez-le si vous ne l'avez pas installé vous-même."))
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
