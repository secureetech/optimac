import Foundation
import AppKit

struct BrowserStatus: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let installed: Bool
    var issues: [String]
    var hijacked: Bool { !issues.isEmpty }
}

/// Navigateurs détournés : page d'accueil, nouvel onglet ou moteur de recherche modifiés,
/// sites ouverts au démarrage, règles « Géré par votre organisation ».
/// Favoris, mots de passe et historique ne sont jamais touchés.
enum BrowserEngine {
    static let safeDomains = ["google.", "bing.com", "duckduckgo.com", "qwant.com", "ecosia.org", "yahoo.", "apple.com",
                              "msn.com", "startpage.com", "lilo.org", "orange.fr", "free.fr", "sfr.fr", "bouyguestelecom.fr",
                              "laposte.net", "wanadoo.fr", "yandex.", "brave.com", "mozilla.", "firefox.com", "microsoft.com",
                              "secureetech.com", "chrome://", "about:", "edge://", "brave://", "opera://", "favorites://", "topsites://"]
    static let hijackWords = ["search", "find", "query", "srch", "seek", "results", "tab", "start", "home", "portal", "safe", "secure", "weather", "coupon", "convert", "pdf", "map"]

    static func host(_ s: String) -> String {
        (URL(string: s)?.host ?? s).lowercased()
    }

    static func isSafe(_ url: String) -> Bool {
        let l = url.lowercased()
        if l.isEmpty { return true }
        return safeDomains.contains { l.contains($0) }
    }

    /// Page d'accueil suspecte : domaine inconnu ressemblant à un moteur de recherche détourné.
    static func isSuspiciousHome(_ url: String) -> Bool {
        if isSafe(url) { return false }
        let h = host(url)
        return ThreatEngine.isAdware(url) || hijackWords.contains { h.contains($0) }
    }

    static func scan() -> [BrowserStatus] {
        var out: [BrowserStatus] = []

        // Safari
        var safari = BrowserStatus(id: "safari", name: "Safari", bundleID: "com.apple.Safari", installed: true, issues: [])
        let sp = safariPrefs()
        if let home = sp["HomePage"] as? String, isSuspiciousHome(home) { safari.issues.append("Page d'accueil détournée : \(host(home))") }
        let policies = managedPolicies(["com.apple.Safari"])
        if !policies.isEmpty { safari.issues.append("Réglages imposés par un profil (« Géré par votre organisation »)") }
        out.append(safari)

        // Navigateurs Chromium
        for (name, bid, base) in [("Chrome", "com.google.Chrome", "Google/Chrome"),
                                  ("Edge", "com.microsoft.edgemac", "Microsoft Edge"),
                                  ("Brave", "com.brave.Browser", "BraveSoftware/Brave-Browser")] {
            let root = FS.lib("Application Support/\(base)")
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil || FS.exists(root)
            var st = BrowserStatus(id: bid, name: name, bundleID: bid, installed: installed, issues: [])
            for profile in FS.children(root) where FS.exists(profile.appendingPathComponent("Preferences")) {
                st.issues.append(contentsOf: chromiumIssues(profile.appendingPathComponent("Preferences")))
            }
            if !managedPolicies([bid]).isEmpty { st.issues.append("« Géré par votre organisation » : règles imposées") }
            st.issues = Array(Set(st.issues)).sorted()
            out.append(st)
        }

        // Firefox
        let ffRoot = FS.lib("Application Support/Firefox/Profiles")
        let ffInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox") != nil
        var ff = BrowserStatus(id: "org.mozilla.firefox", name: "Firefox", bundleID: "org.mozilla.firefox", installed: ffInstalled || FS.exists(ffRoot), issues: [])
        for p in FS.children(ffRoot) where FS.isDir(p) {
            for file in ["prefs.js", "user.js"] {
                guard let s = try? String(contentsOf: p.appendingPathComponent(file), encoding: .utf8) else { continue }
                for line in s.components(separatedBy: .newlines) where line.contains("browser.startup.homepage\"") || line.contains("browser.newtab.url") {
                    if let v = line.components(separatedBy: "\"").dropFirst(3).first, isSuspiciousHome(v) {
                        ff.issues.append("Page d'accueil détournée : \(host(v))")
                    }
                }
                if file == "user.js" && s.contains("browser.startup.homepage") { ff.issues.append("Fichier user.js qui impose la page d'accueil") }
            }
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox"),
           FS.exists(app.appendingPathComponent("Contents/Resources/distribution/policies.json")) {
            ff.issues.append("Règles imposées (policies.json)")
        }
        ff.issues = Array(Set(ff.issues)).sorted()
        out.append(ff)
        return out
    }

    static func safariPrefs() -> [String: Any] {
        let candidates = [FS.lib("Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari.plist"),
                          FS.lib("Preferences/com.apple.Safari.plist")]
        for c in candidates {
            if let d = NSDictionary(contentsOf: c) as? [String: Any] { return d }
        }
        return [:]
    }

    static func managedPolicies(_ ids: [String]) -> [URL] {
        let user = NSUserName()
        var out: [URL] = []
        for id in ids {
            for p in ["/Library/Managed Preferences/\(id).plist", "/Library/Managed Preferences/\(user)/\(id).plist"] {
                if FS.fm.fileExists(atPath: p) { out.append(URL(fileURLWithPath: p)) }
            }
        }
        return out
    }

    private static func chromiumIssues(_ prefs: URL) -> [String] {
        guard let data = try? Data(contentsOf: prefs),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var issues: [String] = []
        if let home = j["homepage"] as? String, (j["homepage_is_newtabpage"] as? Bool) != true, isSuspiciousHome(home) {
            issues.append("Page d'accueil détournée : \(host(home))")
        }
        if let session = j["session"] as? [String: Any], (session["restore_on_startup"] as? Int) == 4,
           let urls = session["startup_urls"] as? [String] {
            for u in urls where !isSafe(u) { issues.append("Site ouvert au démarrage : \(host(u))") }
        }
        if let dsp = j["default_search_provider_data"] as? [String: Any],
           let t = dsp["template_url_data"] as? [String: Any], let u = t["url"] as? String, !isSafe(u) {
            issues.append("Moteur de recherche détourné : \(host(u))")
        }
        return issues
    }

    // MARK: Réparation (Premium)

    /// Ferme le navigateur, puis remet la page d'accueil, le démarrage et la recherche par défaut.
    static func repair(_ b: BrowserStatus) -> Bool {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID) {
            app.terminate()
        }
        Thread.sleep(forTimeInterval: 1.5)
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID) { app.forceTerminate() }

        var adminCmds: [String] = []
        for p in managedPolicies([b.bundleID]) { adminCmds.append("rm -f \(Shell.quote(p.path))") }

        switch b.id {
        case "safari":
            Shell.run("/usr/bin/defaults", ["write", "com.apple.Safari", "HomePage", "https://www.google.fr/"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.Safari", "SearchProviderShortName", "Google"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.Safari", "SearchProviderIdentifier", "com.google.www"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.Safari", "NewWindowBehavior", "-int", "0"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.Safari", "NewTabBehavior", "-int", "0"])
            for id in ThreatEngine.profileIdentifiers() where id.lowercased().contains("safari") || id.lowercased().contains("search") {
                adminCmds.append("/usr/bin/profiles -R -p \(Shell.quote(id))")
            }
        case "org.mozilla.firefox":
            for p in FS.children(FS.lib("Application Support/Firefox/Profiles")) where FS.isDir(p) {
                for file in ["prefs.js", "user.js"] {
                    let u = p.appendingPathComponent(file)
                    guard let s = try? String(contentsOf: u, encoding: .utf8) else { continue }
                    let kept = s.components(separatedBy: .newlines).filter {
                        !($0.contains("browser.startup.homepage") || $0.contains("browser.newtab.url") || $0.contains("browser.search.") || $0.contains("keyword.URL"))
                    }
                    try? kept.joined(separator: "\n").write(to: u, atomically: true, encoding: .utf8)
                }
            }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.bundleID) {
                let pol = app.appendingPathComponent("Contents/Resources/distribution/policies.json")
                if FS.exists(pol) { adminCmds.append("rm -f \(Shell.quote(pol.path))") }
            }
        default:
            let base = ["com.google.Chrome": "Google/Chrome", "com.microsoft.edgemac": "Microsoft Edge",
                        "com.brave.Browser": "BraveSoftware/Brave-Browser"][b.bundleID] ?? ""
            for profile in FS.children(FS.lib("Application Support/\(base)")) {
                let prefs = profile.appendingPathComponent("Preferences")
                guard let data = try? Data(contentsOf: prefs),
                      var j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                j["homepage"] = "https://www.google.fr/"
                j["homepage_is_newtabpage"] = true
                j.removeValue(forKey: "default_search_provider_data")
                var session = j["session"] as? [String: Any] ?? [:]
                session["restore_on_startup"] = 5
                session["startup_urls"] = [String]()
                j["session"] = session
                if let out = try? JSONSerialization.data(withJSONObject: j) { try? out.write(to: prefs, options: .atomic) }
            }
            for key in ["HomepageLocation", "NewTabPageLocation", "RestoreOnStartupURLs", "DefaultSearchProviderSearchURL", "DefaultSearchProviderEnabled", "HomepageIsNewTabPage", "RestoreOnStartup"] {
                Shell.run("/usr/bin/defaults", ["delete", b.bundleID, key])
            }
        }
        if !adminCmds.isEmpty {
            Shell.admin(adminCmds, prompt: "OptiMac doit retirer les réglages imposés à votre navigateur.")
        }
        return true
    }
}
