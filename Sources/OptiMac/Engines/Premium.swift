import Foundation

/// Ce qui est réservé à la version Premium. Tout est centralisé ici pour pouvoir
/// ajuster l'offre facilement.
enum PremiumFeature: String, Identifiable {
    case unlimitedCleanup, fullSpaceResults, browserRepair, privacy, maintenance
    case forceUninstall, shredder, cloudFree, deleteDuplicates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedCleanup: return "Nettoyage complet sans limite"
        case .fullSpaceResults: return "Tous les résultats de l'Espace disque"
        case .browserRepair: return "Réparation des navigateurs en un clic"
        case .privacy: return "Effacement des traces de navigation"
        case .maintenance: return "Maintenance avancée du Mac"
        case .forceUninstall: return "Suppression forcée des logiciels récalcitrants"
        case .shredder: return "Broyeur de fichiers sécurisé"
        case .cloudFree: return "Libération des fichiers iCloud, Google Drive et OneDrive"
        case .deleteDuplicates: return "Suppression des doublons et des gros fichiers"
        }
    }
}

enum PremiumRules {
    /// Quantité nettoyable par la version gratuite (comme CleanMyMac).
    static let freeCleanupLimit: Int64 = 500_000_000
    /// Part des résultats visible dans l'Espace disque en version gratuite.
    static let freeVisibleRatio = 0.2

    static func visibleCount(_ total: Int, premium: Bool) -> Int {
        premium ? total : min(total, max(3, Int((Double(total) * freeVisibleRatio).rounded(.up))))
    }
}
