import Foundation
import CryptoKit

/// Règle de contenu : tous les mots de `all` et au moins un mot de `any` doivent être présents.
struct ContentRule {
    let name: String
    let detail: String
    let severity: Threat.Severity
    let all: [String]
    let any: [String]

    func matches(_ text: String) -> Bool {
        for a in all where !text.contains(a) { return false }
        return any.isEmpty || any.contains { text.contains($0) }
    }
}

/// Base de signatures : règles intégrées + compléments téléchargés
/// (Resources/signatures.json du dépôt, mis à jour sans recompiler OptiMac).
struct Signatures {
    var names: [String] = []
    var hashes: [String: String] = [:]
    var rules: [ContentRule] = Signatures.builtin

    static let remote = URL(string: "https://raw.githubusercontent.com/secureetech/optimac/main/Resources/signatures.json")!
    static var cacheFile: URL { FS.supportDir.appendingPathComponent("signatures.json") }

    static let pipes = ["| sh", "|sh", "| bash", "|bash", "| zsh", "|zsh", "| /bin/sh", "| /bin/bash", "|/bin/sh", "|/bin/bash"]

    static let builtin: [ContentRule] = [
        ContentRule(name: "Faux message demandant votre mot de passe",
                    detail: "Ce script affiche une fausse fenêtre macOS pour voler le mot de passe du Mac.",
                    severity: .high, all: ["osascript", "display dialog", "hidden answer"], any: []),
        ContentRule(name: "Vol de mots de passe",
                    detail: "Ce programme teste le mot de passe du Mac et lit le trousseau, comme les voleurs de données.",
                    severity: .high, all: ["dscl", "authonly"], any: ["osascript", "keychain"]),
        ContentRule(name: "Code masqué exécuté",
                    detail: "Ce script décode du code caché puis l'exécute.",
                    severity: .high, all: ["base64"],
                    any: ["-d | sh", "-d | bash", "-d|sh", "-d|bash", "--decode | sh", "--decode | bash", "--decode|sh", "--decode|bash"]),
        ContentRule(name: "Script qui télécharge et lance un programme",
                    detail: "Ce script télécharge un programme sur internet et le lance sans rien demander.",
                    severity: .medium, all: ["curl "], any: pipes),
        ContentRule(name: "Contournement de la protection de macOS",
                    detail: "Ce script retire la protection de macOS (quarantaine) d'un fichier téléchargé.",
                    severity: .medium, all: ["xattr", "com.apple.quarantine"], any: ["-d ", "-c ", "-dr ", "-cr ", "-rd "])
    ]

    /// Charge les compléments (copie locale, sinon fichier livré avec l'application).
    static func load() -> Signatures {
        var s = Signatures()
        let bundled = Bundle.main.url(forResource: "signatures", withExtension: "json")
        for u in [bundled, cacheFile].compactMap({ $0 }) {
            guard let d = try? Data(contentsOf: u), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            s.merge(j)
        }
        return s
    }

    private mutating func merge(_ j: [String: Any]) {
        for n in (j["names"] as? [String]) ?? [] where !n.isEmpty && !names.contains(n.lowercased()) { names.append(n.lowercased()) }
        for (h, n) in (j["hashes"] as? [String: String]) ?? [:] { hashes[h.lowercased()] = n }
        for r in (j["rules"] as? [[String: Any]]) ?? [] {
            guard let name = r["name"] as? String, let all = r["all"] as? [String], !all.isEmpty else { continue }
            let sev: Threat.Severity = (r["severity"] as? String) == "high" ? .high : .medium
            rules.append(ContentRule(name: name, detail: r["detail"] as? String ?? "", severity: sev,
                                     all: all.map { $0.lowercased() }, any: ((r["any"] as? [String]) ?? []).map { $0.lowercased() }))
        }
    }

    /// Télécharge la dernière base (au plus une fois par jour). Appelé hors de l'interface.
    static func refresh() {
        let last = UserDefaults.standard.object(forKey: "signaturesDate") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86400 else { return }
        var req = URLRequest(url: remote)
        req.timeoutInterval = 6
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            if let d, (resp as? HTTPURLResponse)?.statusCode == 200,
               (try? JSONSerialization.jsonObject(with: d)) is [String: Any] {
                try? d.write(to: cacheFile, options: .atomic)
                UserDefaults.standard.set(Date(), forKey: "signaturesDate")
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 7)
    }

    static func sha256(_ url: URL) -> String? {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
}
