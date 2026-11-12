import Foundation

/// Liste blanche : les logiciels SecureeTech et l'assistance SecureeTech
/// (MeshCentral relié à secureetech.com, GetScreen) ne sont jamais signalés,
/// jamais marqués « inutiles » et jamais désactivés ou supprimés automatiquement.
enum Whitelist {
    /// Mots qui identifient un logiciel SecureeTech.
    static let secureetechMarks = ["secureetech", "optimac", "optipc", "optiphone", "com.h2oconsulting"]

    /// Outils de prise en main utilisés par l'assistance SecureeTech.
    static let assistanceMarks = ["getscreen"]

    /// Dossiers où l'agent MeshCentral s'installe sur Mac.
    static let meshDirs = ["/usr/local/mesh_services", "/opt/mesh_services", "/Library/Application Support/MeshAgent"]

    /// L'agent MeshCentral installé est-il relié au serveur SecureeTech ?
    /// Un agent MeshCentral relié à un autre serveur n'est PAS de confiance.
    static let meshIsSecureeTech: Bool = {
        let fm = FileManager.default
        var found = false
        for root in meshDirs {
            guard let en = fm.enumerator(atPath: root) else { continue }
            var count = 0
            while let rel = en.nextObject() as? String {
                count += 1
                if count > 400 { break }
                guard rel.hasSuffix(".msh") else { continue }
                found = true
                if let s = try? String(contentsOfFile: root + "/" + rel, encoding: .utf8), s.lowercased().contains("secureetech") { return true }
            }
        }
        // Agent présent sans fichier de réglages lisible : on le considère comme celui de SecureeTech
        // seulement s'il n'y a aucun fichier .msh (installation SecureeTech standard).
        return !found
    }()

    static func isMesh(_ text: String) -> Bool {
        let l = text.lowercased()
        return l.contains("meshagent") || l.contains("mesh_services") || l.contains("meshcentral")
    }

    /// Vrai si le texte (nom, identifiant, chemin, label) désigne un logiciel SecureeTech ou l'assistance.
    static func contains(_ texts: String...) -> Bool {
        let l = texts.joined(separator: " ").lowercased()
        if secureetechMarks.contains(where: { l.contains($0) }) { return true }
        if assistanceMarks.contains(where: { l.contains($0) }) { return true }
        if isMesh(l) { return meshIsSecureeTech }
        return false
    }
}
