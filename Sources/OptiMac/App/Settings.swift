import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: return "Clair"
        case .dark: return "Sombre"
        case .system: return "Comme macOS"
        }
    }
}

enum TextSize: String, CaseIterable, Identifiable {
    case normal, large, xlarge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal: return "Normal"
        case .large: return "Grand"
        case .xlarge: return "Très grand"
        }
    }
    var scale: CGFloat {
        switch self {
        case .normal: return 1
        case .large: return 1.12
        case .xlarge: return 1.25
        }
    }
}

enum AutoClean: String, CaseIterable, Identifiable {
    case off, daily, weekly, startup
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Désactivé"
        case .daily: return "Chaque jour"
        case .weekly: return "Chaque semaine"
        case .startup: return "Au démarrage"
        }
    }
}

/// Paramètres enregistrés sur ce Mac.
@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var appearance: AppearanceMode { didSet { d.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    @Published var textSize: TextSize { didSet { d.set(textSize.rawValue, forKey: "textSize") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); StartupEngine.setLaunchAtLogin(launchAtLogin) } }
    @Published var openWindowAtLogin: Bool { didSet { d.set(openWindowAtLogin, forKey: "openWindowAtLogin") } }
    @Published var weeklyCheck: Bool { didSet { d.set(weeklyCheck, forKey: "weeklyCheck") } }
    @Published var notifPremium: Bool { didSet { d.set(notifPremium, forKey: "notifPremium") } }
    @Published var notifCleanDone: Bool { didSet { d.set(notifCleanDone, forKey: "notifCleanDone") } }
    @Published var notifScanDone: Bool { didSet { d.set(notifScanDone, forKey: "notifScanDone") } }
    @Published var notifThreats: Bool { didSet { d.set(notifThreats, forKey: "notifThreats") } }
    @Published var notifStartup: Bool { didSet { d.set(notifStartup, forKey: "notifStartup") } }
    @Published var autoClean: AutoClean { didSet { d.set(autoClean.rawValue, forKey: "autoClean") } }
    @Published var autoCleanHour: Int { didSet { d.set(autoCleanHour, forKey: "autoCleanHour") } }
    @Published var consentAccepted: Bool { didSet { d.set(consentAccepted, forKey: "consentAccepted") } }
    @Published var welcomeShown: Bool { didSet { d.set(welcomeShown, forKey: "welcomeShown") } }

    init() {
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .light
        textSize = TextSize(rawValue: d.string(forKey: "textSize") ?? "") ?? .normal
        launchAtLogin = d.object(forKey: "launchAtLogin") as? Bool ?? true
        openWindowAtLogin = d.object(forKey: "openWindowAtLogin") as? Bool ?? true
        weeklyCheck = d.object(forKey: "weeklyCheck") as? Bool ?? true
        notifPremium = d.object(forKey: "notifPremium") as? Bool ?? true
        notifCleanDone = d.object(forKey: "notifCleanDone") as? Bool ?? true
        notifScanDone = d.object(forKey: "notifScanDone") as? Bool ?? true
        notifThreats = d.object(forKey: "notifThreats") as? Bool ?? true
        notifStartup = d.object(forKey: "notifStartup") as? Bool ?? true
        autoClean = AutoClean(rawValue: d.string(forKey: "autoClean") ?? "") ?? .off
        autoCleanHour = d.object(forKey: "autoCleanHour") as? Int ?? 10
        consentAccepted = d.bool(forKey: "consentAccepted")
        welcomeShown = d.bool(forKey: "welcomeShown")
    }

    func date(_ key: String) -> Date? { d.object(forKey: key) as? Date }
    func setDate(_ key: String, _ value: Date?) { d.set(value, forKey: key) }

    func applyAppearance() {
        switch appearance {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    func toggleTheme() { appearance = appearance == .dark ? .light : .dark }
}
