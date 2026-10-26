import Foundation
import Security

/// Licences OptiMac, reliées au serveur SecureeTech (api.secureetech.com).
/// Mêmes clés que OptiPC (ST-XXXX-XXXX-XXXX) et même essai de 5 jours.
/// Le jeton renvoyé par le serveur est signé (RSA) et vérifié ici hors ligne :
/// impossible d'en fabriquer un faux sans la clé privée du serveur.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var isPremium = false
    @Published private(set) var isTrial = false
    @Published private(set) var expiresAt: Date?
    @Published private(set) var keyPrefix: String?
    @Published var message: String?
    @Published var warning: String?
    @Published var busy = false

    static let api = URL(string: "https://api.secureetech.com")!

    /// Clé publique du serveur (GET /v1/public-key) — non secrète.
    private static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwKIywxBtJ/gluJ5G/5B1
    s31wXjH9E9GlJlYv62M3QbFZ7P1WX0smHRfk9EyXjKC7pooYRySKSjaKNBjYWXsN
    PP9CCshJLQcRIqbiwqg/ZVQg2kXvi6xKlnu3Dm7wzKzUeQvtaALQT2X9V7Hb9hVN
    43p768ZxSjImRwmbXU6NjEo55OAS1wx/bVhLiBDsAIQSHuGjftCRDnip6SZAn56a
    FxciF4eACet/SF0Bae44XGg8LWBVxW1e8HkqMenBQqNMEtp2vu4V4Rpvoo6odHrQ
    U8txe7szx7FMH7t0jvpA7ZgUtuhTDDV+Wy15bCrQO2LXjoKS3fHUiCj5OZQcf0J+
    vQIDAQAB
    -----END PUBLIC KEY-----
    """

    private struct Stored: Codable {
        var token: String
        var billingPeriod: String?
        var lastHeartbeat: Date
        var heartbeatDays: Int
    }

    private struct Payload {
        let lic: String
        let kp: String?
        let mid: String
        let plan: String
        let exp: Date
    }

    private var stored: Stored?
    private let defaults = UserDefaults.standard
    private var storeURL: URL { FS.supportDir.appendingPathComponent("licence.json") }

    var daysLeft: Int? {
        guard let expiresAt else { return nil }
        return max(0, Int(ceil(expiresAt.timeIntervalSinceNow / 86400)))
    }

    var statusLabel: String {
        if isPremium && isTrial { return "Essai Premium · \(daysLeft ?? 0) jour\((daysLeft ?? 0) > 1 ? "s" : "") restant\((daysLeft ?? 0) > 1 ? "s" : "")" }
        if isPremium { return "Premium" }
        return "Version gratuite"
    }

    // MARK: Démarrage

    func bootstrap() async {
        load()
        if stored == nil && !defaults.bool(forKey: "trialRequested") {
            await requestTrial()
        } else if let s = stored {
            let due = Date().timeIntervalSince(s.lastHeartbeat) > Double(max(1, s.heartbeatDays)) * 86400
            if due { await heartbeat() }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else {
            apply(nil)
            return
        }
        stored = s
        apply(s)
    }

    private func save(_ s: Stored?) {
        stored = s
        if let s, let data = try? JSONEncoder().encode(s) {
            try? data.write(to: storeURL, options: .atomic)
        } else {
            try? FS.fm.removeItem(at: storeURL)
        }
        apply(s)
    }

    private func apply(_ s: Stored?) {
        guard let s, let p = verify(s.token) else {
            isPremium = false
            isTrial = false
            expiresAt = nil
            keyPrefix = nil
            return
        }
        expiresAt = p.exp
        keyPrefix = p.kp
        isTrial = s.billingPeriod == "trial"
        isPremium = p.exp > Date()
    }

    // MARK: Actions

    func requestTrial() async {
        defaults.set(true, forKey: "trialRequested")
        let (code, json) = await post("/v1/optipc/trial", body: baseBody())
        if code == 200, let token = json["token"] as? String {
            save(Stored(token: token, billingPeriod: "trial", lastHeartbeat: Date(),
                        heartbeatDays: json["heartbeat_days"] as? Int ?? 3))
            if isPremium {
                Notifier.post("Essai Premium activé", "Profitez de toutes les fonctions d'OptiMac pendant 5 jours.")
            }
        } else if code == 0 {
            // Pas d'internet : on réessaiera au prochain lancement.
            defaults.set(false, forKey: "trialRequested")
        }
    }

    func activate(key raw: String) async -> Bool {
        busy = true
        defer { busy = false }
        message = nil
        var body = baseBody()
        body["key"] = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let (code, json) = await post("/v1/activate", body: body)
        if code == 200, let token = json["token"] as? String, verify(token) != nil {
            save(Stored(token: token, billingPeriod: json["billing_period"] as? String,
                        lastHeartbeat: Date(), heartbeatDays: json["heartbeat_days"] as? Int ?? 3))
            warning = json["warning"] as? String
            message = "Votre licence Premium est activée. Merci !"
            return true
        }
        if code == 0 {
            message = "Impossible de joindre le serveur SecureeTech. Vérifiez votre connexion internet puis réessayez."
        } else {
            message = (json["message"] as? String) ?? (json["error"] as? String) ?? "L'activation a échoué (erreur \(code))."
        }
        return false
    }

    func heartbeat() async {
        guard let s = stored else { return }
        var body = baseBody()
        body["token"] = s.token
        let (code, json) = await post("/v1/heartbeat", body: body)
        if code == 200, let token = json["token"] as? String, verify(token) != nil {
            save(Stored(token: token, billingPeriod: s.billingPeriod, lastHeartbeat: Date(),
                        heartbeatDays: json["heartbeat_days"] as? Int ?? s.heartbeatDays))
            warning = json["warning"] as? String
        } else if code == 403 || code == 404 {
            // Licence désactivée, résiliée ou expirée côté serveur.
            save(nil)
            message = json["message"] as? String
        }
        // Autres cas (pas de réseau, serveur indisponible) : on garde le jeton jusqu'à son expiration.
    }

    func deactivate() async {
        guard let s = stored else { return }
        busy = true
        defer { busy = false }
        let (_, json) = await post("/v1/deactivate", body: ["token": s.token])
        save(nil)
        message = (json["message"] as? String) ?? "Ce Mac a été libéré."
    }

    // MARK: Réseau

    private func baseBody() -> [String: Any] {
        ["machine_id": SystemInfo.machineID,
         "hostname": SystemInfo.hostname,
         "os": SystemInfo.osVersion,
         "app_version": "OptiMac \(SystemInfo.appVersion)"]
    }

    private func post(_ path: String, body: [String: Any]) async -> (Int, [String: Any]) {
        var req = URLRequest(url: Self.api.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("OptiMac/\(SystemInfo.appVersion)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, code, err) = await HTTP.data(for: req)
        if let err {
            ErrorLog.write("Licence \(path) : \(err.localizedDescription)")
            return (0, [:])
        }
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        return (code, json)
    }

    // MARK: Vérification du jeton

    private static let publicKey: SecKey? = {
        let b64 = publicKeyPEM
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: b64) else { return nil }
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                    kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        if let k = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, nil) { return k }
        // Format SPKI → PKCS#1 : on retire l'en-tête de 24 octets (clé RSA 2048 bits).
        if der.count > 24, let k = SecKeyCreateWithData(der.dropFirst(24) as CFData, attrs as CFDictionary, nil) { return k }
        return nil
    }()

    private static func b64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    private func verify(_ token: String) -> Payload? {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 2,
              let sig = Self.b64url(parts[1]),
              let bodyData = Self.b64url(parts[0]),
              let key = Self.publicKey else { return nil }
        let ok = SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                       Data(parts[0].utf8) as CFData, sig as CFData, nil)
        guard ok,
              let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
              let mid = json["mid"] as? String, mid == SystemInfo.machineID,
              let exp = (json["exp"] as? NSNumber)?.doubleValue else { return nil }
        return Payload(lic: "\(json["lic"] ?? "")", kp: json["kp"] as? String, mid: mid,
                       plan: json["plan"] as? String ?? "pro", exp: Date(timeIntervalSince1970: exp))
    }
}

/// Recherche de mise à jour (canal « optimac » sur le serveur SecureeTech).
@MainActor
final class Updater: ObservableObject {
    @Published var latest: String?
    @Published var url: URL?
    @Published var notes: String?

    func check() async {
        var c = URLComponents(url: LicenseManager.api.appendingPathComponent("/v1/update"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "channel", value: "optimac"),
                        URLQueryItem(name: "current", value: SystemInfo.appVersion),
                        URLQueryItem(name: "machine", value: SystemInfo.machineID)]
        guard let u = c.url else { return }
        guard let json = await HTTP.json(from: u),
              json["update_available"] as? Bool == true,
              let s = json["url"] as? String, let link = URL(string: s) else { return }
        latest = (json["version"] as? String) ?? (json["latest"] as? String)
        url = link
        notes = json["notes"] as? String
    }
}
