import Foundation
import AppKit

struct AppItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var size: Int64
    let isAppStore: Bool
    let feedURL: String?
    var lastUsed: Date?
    var runningInMenuBar: Bool = false
    var update: String?
    var updateLink: URL?
    static func == (a: AppItem, b: AppItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Leftover: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let needsAdmin: Bool
}

struct ExtensionItem: Identifiable, Hashable {
    let id: String
    let name: String
    let browser: String
    let path: URL?
    let pluginID: String?
}

/// Applications : liste, désinstallation complète (avec les restes), suppression forcée
/// des logiciels récalcitrants (y compris ceux affichés près de l'horloge), mises à jour, extensions.
enum AppsEngine {
    static func list() -> [AppItem] {
        var out: [AppItem] = []
        let menuBarIDs = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .accessory }.compactMap { $0.bundleIdentifier })
        for dir in [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications/Utilities")] {
            for app in FS.children(dir, includeHidden: false) where app.pathExtension == "app" {
                guard let b = Bundle(url: app) else { continue }
                let bid = b.bundleIdentifier ?? ""
                if bid.hasPrefix("com.apple.") || bid == Bundle.main.bundleIdentifier { continue }
                let info = b.infoDictionary ?? [:]
                let ver = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? ""
                let mas = FS.exists(app.appendingPathComponent("Contents/_MASReceipt/receipt"))
                let last = (try? app.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
                out.append(AppItem(url: app, name: app.deletingPathExtension().lastPathComponent, bundleID: bid, version: ver,
                                   size: 0, isAppStore: mas, feedURL: info["SUFeedURL"] as? String, lastUsed: last,
                                   runningInMenuBar: menuBarIDs.contains(bid)))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func withSizes(_ apps: [AppItem]) -> [AppItem] {
        apps.map { var a = $0; a.size = FS.size(of: a.url); return a }
    }

    // MARK: Restes laissés dans la Bibliothèque

    static func leftovers(for app: AppItem) -> [Leftover] {
        let bid = app.bundleID.lowercased()
        let name = app.name.lowercased().replacingOccurrences(of: " ", with: "")
        let userDirs = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers", "Saved Application State",
                        "Logs", "HTTPStorages", "WebKit", "LaunchAgents", "Cookies", "Application Scripts"].map { FS.lib($0) }
        let sysDirs = ["/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/LaunchAgents",
                       "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Logs"].map { URL(fileURLWithPath: $0) }
        var out: [Leftover] = []
        func matches(_ u: URL) -> Bool {
            let n = u.lastPathComponent.lowercased()
            let compact = n.replacingOccurrences(of: " ", with: "")
            if !bid.isEmpty && n.contains(bid) { return true }
            if name.count >= 4 && (compact == name || compact.hasPrefix(name + ".") || compact.hasPrefix(name + "-")) { return true }
            if u.pathExtension == "plist", u.path.contains("Launch") {
                let (label, program) = ThreatEngine.launchProgram(u)
                if program.hasPrefix(app.url.path) { return true }
                if !bid.isEmpty && label.lowercased().contains(bid) { return true }
            }
            return false
        }
        for d in userDirs {
            for c in FS.children(d) where matches(c) { out.append(Leftover(url: c, size: FS.size(of: c), needsAdmin: false)) }
        }
        for d in sysDirs {
            for c in FS.children(d) where matches(c) { out.append(Leftover(url: c, size: FS.size(of: c), needsAdmin: true)) }
        }
        return out
    }

    /// Désinstallation. En mode forcé : fermeture de force (même dans la barre des menus),
    /// arrêt des agents qui la relancent, retrait des éléments d'ouverture, suppression des
    /// fichiers protégés avec le mot de passe administrateur.
    @discardableResult
    static func uninstall(_ app: AppItem, leftovers: [Leftover], force: Bool) -> Bool {
        let uid = getuid()
        var admin: [String] = []

        // 1. Fermer l'application et tout ce qui vient de son dossier
        for r in NSWorkspace.shared.runningApplications where r.bundleIdentifier == app.bundleID || (r.bundleURL?.path.hasPrefix(app.url.path) ?? false) {
            if force { r.forceTerminate() } else { r.terminate() }
        }
        if force {
            Shell.run("/usr/bin/pkill", ["-9", "-f", app.url.path])
            if !app.bundleID.isEmpty { Shell.run("/usr/bin/pkill", ["-9", "-f", app.bundleID]) }
        }

        // 2. Agents de lancement qui la relancent
        for l in leftovers where l.url.pathExtension == "plist" && l.url.path.contains("Launch") {
            if l.needsAdmin {
                admin.append("launchctl bootout system \(Shell.quote(l.url.path))")
            } else {
                Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", l.url.path])
            }
        }
        if force && !app.bundleID.isEmpty {
            Shell.run("/bin/launchctl", ["remove", app.bundleID])
        }

        // 3. Élément d'ouverture (ouverture à la connexion)
        let escaped = app.name.replacingOccurrences(of: "\"", with: "")
        Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to delete (every login item whose name is \"\(escaped)\")"], timeout: 10)

        // 4. Fichiers
        var ok = true
        for target in [app.url] + leftovers.map(\.url) {
            if !FS.exists(target) { continue }
            let isApp = target == app.url
            let moved = isApp ? FS.trash(target) : (FS.remove(target) > 0 || !FS.exists(target))
            if !moved {
                if force || leftovers.first(where: { $0.url == target })?.needsAdmin == true || isApp {
                    admin.append("chflags -R nouchg,noschg \(Shell.quote(target.path)); rm -rf \(Shell.quote(target.path))")
                } else {
                    ok = false
                }
            }
        }
        if !admin.isEmpty {
            let r = Shell.admin(admin, prompt: "OptiMac doit supprimer « \(app.name) » et ses fichiers protégés.")
            ok = ok && r.ok
        }
        return ok && !FS.exists(app.url)
    }

    // MARK: Applications dans la barre des menus (près de l'horloge)

    struct MenuBarApp: Identifiable {
        var id: Int32 { pid }
        let pid: Int32
        let name: String
        let bundleID: String
        let url: URL?
        let icon: NSImage?
    }

    static func menuBarApps() -> [MenuBarApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .accessory && !($0.bundleIdentifier ?? "").hasPrefix("com.apple.") && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { MenuBarApp(pid: $0.processIdentifier, name: $0.localizedName ?? "Application", bundleID: $0.bundleIdentifier ?? "",
                              url: $0.bundleURL, icon: $0.icon) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Mises à jour

    static func checkUpdates(_ apps: [AppItem]) async -> [AppItem] {
        var out = apps
        for i in out.indices {
            let a = out[i]
            if a.isAppStore, !a.bundleID.isEmpty,
               let u = URL(string: "https://itunes.apple.com/lookup?bundleId=\(a.bundleID)&country=fr"),
               let j = await HTTP.json(from: u),
               let r = (j["results"] as? [[String: Any]])?.first,
               let v = r["version"] as? String, isNewer(v, than: a.version) {
                out[i].update = v
                if let tid = r["trackId"] as? Int { out[i].updateLink = URL(string: "macappstore://apps.apple.com/app/id\(tid)") }
            } else if let feed = a.feedURL, let u = URL(string: feed) {
                let (data, code, _) = await HTTP.data(from: u, timeout: 15)
                if code == 200, let data, let res = SparkleFeed.latest(data), isNewer(res.0, than: a.version) {
                    out[i].update = res.0
                    out[i].updateLink = res.1
                }
            }
        }
        return out
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let pb = b.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Extensions

    static func resolveExtName(_ raw: String, dir: URL) -> String {
        guard raw.hasPrefix("__MSG_") else { return raw }
        let key = raw.replacingOccurrences(of: "__MSG_", with: "").replacingOccurrences(of: "__", with: "").lowercased()
        for loc in ["fr", "en", "en_US"] {
            let f = dir.appendingPathComponent("_locales/\(loc)/messages.json")
            if let d = try? Data(contentsOf: f), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                for (k, v) in j where k.lowercased() == key {
                    if let m = (v as? [String: Any])?["message"] as? String { return m }
                }
            }
        }
        return raw
    }

    static func extensions() -> [ExtensionItem] {
        var out: [ExtensionItem] = []
        // Safari
        for kind in ["com.apple.Safari.web-extension", "com.apple.Safari.extension", "com.apple.Safari.content-blocker"] {
            let r = Shell.run("/usr/bin/pluginkit", ["-mAvvv", "-p", kind], timeout: 20)
            var currentID: String?
            for line in r.out.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if let open = t.firstIndex(of: "("), !t.hasPrefix("Path"), !t.contains(" = ") {
                    currentID = String(t[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: "+-!= "))
                } else if t.hasPrefix("Path = "), let id = currentID {
                    let p = URL(fileURLWithPath: String(t.dropFirst(7)))
                    if p.path.hasPrefix("/System") || p.path.contains("/Safari.app/") { continue }
                    out.append(ExtensionItem(id: "safari:" + id, name: p.deletingPathExtension().lastPathComponent, browser: "Safari", path: p, pluginID: id))
                }
            }
        }
        // Chrome, Edge, Brave
        for (browser, profile) in ThreatEngine.chromiumProfiles() {
            for ext in FS.children(profile.appendingPathComponent("Extensions")) where FS.isDir(ext) {
                guard let ver = FS.children(ext).first(where: FS.isDir),
                      let d = try? Data(contentsOf: ver.appendingPathComponent("manifest.json")),
                      let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
                let n = resolveExtName(m["name"] as? String ?? ext.lastPathComponent, dir: ver)
                if ext.lastPathComponent == "nmmhkkegccagdldgiimedpiccmgmieda" || ext.lastPathComponent == "ghbmnnjooekpmoecnnnilnnbdlolhkhi" { continue }
                out.append(ExtensionItem(id: ext.path, name: n, browser: browser, path: ext, pluginID: nil))
            }
        }
        // Firefox
        for p in FS.children(FS.lib("Application Support/Firefox/Profiles")) {
            for x in FS.children(p.appendingPathComponent("extensions")) where x.pathExtension == "xpi" {
                out.append(ExtensionItem(id: x.path, name: x.deletingPathExtension().lastPathComponent, browser: "Firefox", path: x, pluginID: nil))
            }
        }
        // Modules des Réglages Système
        for d in [FS.lib("PreferencePanes"), URL(fileURLWithPath: "/Library/PreferencePanes")] {
            for x in FS.children(d) where x.pathExtension == "prefPane" {
                out.append(ExtensionItem(id: x.path, name: x.deletingPathExtension().lastPathComponent, browser: "Réglages Système", path: x, pluginID: nil))
            }
        }
        return out
    }

    static func removeExtension(_ e: ExtensionItem) {
        if let id = e.pluginID {
            Shell.run("/usr/bin/pluginkit", ["-e", "ignore", "-i", id])
            return
        }
        guard let p = e.path else { return }
        if FS.remove(p) == 0 && FS.exists(p) {
            Shell.admin(["rm -rf \(Shell.quote(p.path))"])
        }
    }
}

/// Lecture des flux de mise à jour « Sparkle » utilisés par la plupart des applications Mac.
final class SparkleFeed: NSObject, XMLParserDelegate {
    private var best: (String, URL?)?
    private var currentText = ""
    private var itemVersion: String?
    private var itemLink: URL?

    static func latest(_ data: Data) -> (String, URL?)? {
        let p = XMLParser(data: data)
        let d = SparkleFeed()
        p.delegate = d
        p.parse()
        return d.best
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        currentText = ""
        if name == "item" { itemVersion = nil; itemLink = nil }
        if name == "enclosure" {
            if let v = a["sparkle:shortVersionString"] ?? a["sparkle:version"] { itemVersion = itemVersion ?? v }
            if let u = a["url"] { itemLink = URL(string: u) }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName q: String?) {
        let t = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "sparkle:shortVersionString", !t.isEmpty { itemVersion = t }
        if name == "item", let v = itemVersion {
            if best == nil || AppsEngine.isNewer(v, than: best!.0) { best = (v, itemLink) }
        }
    }
}
