import Foundation
import UserNotifications
import AppKit

/// Notifications macOS (coin supérieur droit de l'écran).
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(_ title: String, _ body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { err in
            if let err { ErrorLog.write("Notification impossible : \(err.localizedDescription)") }
        }
    }
}

/// Liens et coordonnées SecureeTech utilisés dans le logiciel.
enum Links {
    static let premium = URL(string: "https://secureetech.com/optipc/")!
    static let site = URL(string: "https://secureetech.com")!
    static let support = "05 54 54 23 43"
    static let email = "contact@secureetech.com"
    static let fullDiskAccess = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// Vérifie si OptiMac a l'« Accès complet au disque ».
enum Permissions {
    static var hasFullDiskAccess: Bool {
        let probes = ["/Library/Application Support/com.apple.TCC/TCC.db",
                      FS.lib("Safari").path,
                      FS.lib("Mail").path]
        for p in probes where FS.fm.fileExists(atPath: p) {
            if FS.isDir(URL(fileURLWithPath: p)) {
                if (try? FS.fm.contentsOfDirectory(atPath: p)) != nil { return true }
            } else if let h = FileHandle(forReadingAtPath: p) {
                try? h.close()
                return true
            }
        }
        return false
    }
}
