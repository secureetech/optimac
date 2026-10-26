import SwiftUI
import AppKit

enum Section: String, CaseIterable, Identifiable {
    case home, clean, space, protect, apps, network, health, tools, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Accueil"
        case .clean: return "Nettoyage"
        case .space: return "Espace disque"
        case .protect: return "Protection"
        case .apps: return "Applications"
        case .network: return "Réseau"
        case .health: return "Santé du Mac"
        case .tools: return "Outils"
        case .settings: return "Paramètres"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .clean: return "trash"
        case .space: return "chart.pie"
        case .protect: return "checkmark.shield"
        case .apps: return "square.grid.2x2"
        case .network: return "wifi"
        case .health: return "waveform.path.ecg"
        case .tools: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }
}

enum HomePhase { case idle, scanning, results, boosting, done }

struct Finding: Identifiable {
    let id: String
    let title: String
    let detail: String
    let size: Int64
    var selected: Bool
    let premium: Bool
    let alert: Bool
}

/// Drapeau d'arrêt partagé entre l'interface et une analyse en cours.
final class StopFlag {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

/// Exécute un travail lourd hors de l'interface puis revient avec le résultat.
func runInBackground<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { c in
        DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: work()) }
    }
}

@MainActor
final class Model: ObservableObject {
    let license: LicenseManager
    let settings: AppSettings

    // Navigation et fenêtres
    @Published var section: Section = .home
    @Published var premiumFeature: PremiumFeature?
    @Published var showPremium = false
    @Published var showCallback = false
    @Published var toast: String?
    @Published var working: String?

    // Accueil
    @Published var phase: HomePhase = .idle
    @Published var progress: Double = 0
    @Published var progressLabel = ""
    @Published var findings: [Finding] = []
    @Published var score: Int?
    @Published var lastScan: Date?
    @Published var freed: Int64 = 0
    @Published var boostSteps: [String] = []

    // Écrans
    @Published var cleanup: [CleanCategory] = []
    @Published var cleanupLoading = false
    @Published var space: SpaceReport?
    @Published var spaceLoading = false
    @Published var spaceLabel = ""
    @Published var threats: [Threat] = []
    @Published var selectedThreats = Set<String>()
    @Published var threatLoading = false
    @Published var threatProgress: Double = 0
    @Published var threatStep = ""
    @Published var lastThreatScan: Date?
    @Published var browsers: [BrowserStatus] = []
    @Published var privacy: [PrivacyItem] = []
    @Published var security: SecurityStatus?
    @Published var cameraApps: [String] = []
    @Published var micApps: [String] = []
    @Published var apps: [AppItem] = []
    @Published var appsLoading = false
    @Published var updatesLoading = false
    @Published var menuBarApps: [AppsEngine.MenuBarApp] = []
    @Published var startup: [StartupItem] = []
    @Published var extensions: [ExtensionItem] = []
    @Published var processes: [ProcessInfoItem] = []
    @Published var maintenance: [MaintenanceTask] = []
    @Published var quarantine: [QuarantineItem] = []
    @Published var disk: DiskHealth?
    @Published var battery: BatteryHealth?
    @Published var hardware: HardwareInfo?
    @Published var devices: [NetDevice] = []
    @Published var netLoading = false
    @Published var netProgress: Double = 0
    @Published var wifi: WifiInfo?
    @Published var speedDown: Double?
    @Published var speedUp: Double?
    @Published var speedPing: Double?
    @Published var speedLoading = false
    @Published var history: [(Date, Int)] = []
    @Published var activity: [(Date, String)] = []

    private let stop = StopFlag()

    init(license: LicenseManager, settings: AppSettings) {
        self.license = license
        self.settings = settings
        lastScan = settings.date("lastScan")
        maintenance = MaintenanceEngine.tasks()
        quarantine = ThreatEngine.loadQuarantine()
        history = ScoreHistory.load()
        activity = ActivityLog.load()
    }

    var premium: Bool { license.isPremium }
    var dangerCount: Int { threats.filter { $0.severity >= .medium }.count }
    var hijackedCount: Int { browsers.filter(\.hijacked).count }

    func needsPremium(_ f: PremiumFeature) -> Bool {
        if premium { return false }
        premiumFeature = f
        showPremium = true
        return true
    }

    func notify(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }

    func log(_ text: String) {
        ActivityLog.add(text)
        activity = ActivityLog.load()
    }

    // MARK: - Analyse complète

    func startScan() {
        guard phase != .scanning, phase != .boosting else { return }
        phase = .scanning
        progress = 0
        Task { await runScan() }
    }

    private func runScan() async {
        progressLabel = "Recherche des fichiers inutiles…"
        cleanup = await runInBackground { CleanupEngine.scan() }
        progress = 0.3

        progressLabel = "Recherche des menaces…"
        let found = await runInBackground { ThreatEngine.scan(full: false, step: { _, _ in }, cancelled: { false }) }
        threats = found
        selectedThreats = Set(found.filter { $0.severity >= .medium }.map(\.id))
        lastThreatScan = Date()
        progress = 0.55

        progressLabel = "Vérification des navigateurs…"
        browsers = await runInBackground { BrowserEngine.scan() }
        progress = 0.7

        progressLabel = "Analyse du démarrage…"
        startup = await runInBackground { StartupEngine.list() }
        progress = 0.85

        progressLabel = "Santé du disque…"
        disk = await runInBackground { HealthEngine.disk() }
        progress = 1

        buildFindings()
        let s = computeScore()
        score = s
        ScoreHistory.add(s)
        history = ScoreHistory.load()
        lastScan = Date()
        settings.setDate("lastScan", lastScan)
        phase = .results
        log("Analyse complète : score \(s)/100")
        if settings.notifScanDone && !NSApp.isActive {
            Notifier.post("Analyse terminée", "Vous pouvez récupérer \(Fmt.bytes(junkSize)) et corriger \(dangerCount + hijackedCount) problème(s).")
        }
    }

    var junkSize: Int64 { cleanup.filter(\.safe).reduce(0) { $0 + $1.size } }

    private func buildFindings() {
        var f: [Finding] = []
        for c in cleanup where c.size > 0 {
            f.append(Finding(id: "clean:" + c.id, title: c.name, detail: c.detail, size: c.size, selected: c.safe, premium: false, alert: false))
        }
        if dangerCount > 0 {
            let names = threats.filter { $0.severity >= .medium }.prefix(2).map(\.name).joined(separator: ", ")
            f.append(Finding(id: "threats", title: "Menaces détectées (\(dangerCount))", detail: names, size: 0, selected: true, premium: true, alert: true))
        }
        for b in browsers where b.hijacked {
            f.append(Finding(id: "browser:" + b.id, title: "\(b.name) détourné", detail: b.issues.first ?? "", size: 0, selected: true, premium: true, alert: true))
        }
        let useless = startup.filter { $0.useless && $0.enabled }
        if !useless.isEmpty {
            f.append(Finding(id: "startup", title: "Applis inutiles au démarrage (\(useless.count))", detail: "Le Mac démarrera plus vite", size: 0, selected: true, premium: false, alert: false))
        }
        findings = f
    }

    private func computeScore() -> Int {
        var s = 100
        s -= min(30, Int(Double(junkSize) / 1_000_000_000 * 4))
        s -= min(30, threats.filter { $0.severity == .high }.count * 15 + threats.filter { $0.severity == .medium }.count * 5)
        s -= hijackedCount * 10
        if FS.volume().total > 0 && Double(FS.volume().free) / Double(FS.volume().total) < 0.15 { s -= 10 }
        if startup.filter({ $0.useless && $0.enabled }).count > 3 { s -= 5 }
        return max(5, s)
    }

    var selectedGain: Int64 { findings.filter(\.selected).reduce(0) { $0 + $1.size } }

    // MARK: - Booster mon Mac

    func boost() {
        guard phase == .results else { return }
        let wantsPremium = findings.contains { $0.selected && $0.premium }
        phase = .boosting
        boostSteps = []
        Task {
            boostSteps.append("Création d'un instantané Time Machine…")
            _ = await runInBackground { MaintenanceEngine.snapshot() }

            let chosen = Set(findings.filter { $0.selected }.map(\.id))
            var cats = cleanup
            for i in cats.indices { cats[i].selected = chosen.contains("clean:" + cats[i].id) }
            boostSteps.append("Nettoyage des fichiers inutiles…")
            let limit: Int64? = premium ? nil : PremiumRules.freeCleanupLimit
            let got = await runInBackground { CleanupEngine.clean(cats, limit: limit) }
            freed = got

            if premium && chosen.contains("threats") {
                boostSteps.append("Mise en quarantaine des menaces…")
                let list = threats.filter { selectedThreats.contains($0.id) }
                _ = await runInBackground { ThreatEngine.remove(list, quarantine: true) }
                threats.removeAll { selectedThreats.contains($0.id) }
                quarantine = ThreatEngine.loadQuarantine()
            }
            if premium {
                for b in browsers where b.hijacked && chosen.contains("browser:" + b.id) {
                    boostSteps.append("Réparation de \(b.name)…")
                    _ = await runInBackground { BrowserEngine.repair(b) }
                }
            }
            if chosen.contains("startup") {
                boostSteps.append("Allègement du démarrage…")
                for item in startup where item.useless && item.enabled && item.kind == .agent {
                    await runInBackground { StartupEngine.toggle(item) }
                }
                startup = await runInBackground { StartupEngine.list() }
            }
            boostSteps.append("Terminé")
            phase = .done
            log("Optimisation : \(Fmt.bytes(got)) libérés")
            if settings.notifCleanDone && !NSApp.isActive {
                Notifier.post("Optimisation terminée", "\(Fmt.bytes(got)) libérés sur votre Mac.")
            }
            if !premium && (wantsPremium || junkSize > got) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.premiumFeature = .unlimitedCleanup
                    self?.showPremium = true
                }
            }
        }
    }

    func emptyTrash() {
        let freedTrash = FS.removeContents(of: FS.home.appendingPathComponent(".Trash"))
        notify("Corbeille vidée : \(Fmt.bytes(freedTrash)) libérés")
    }

    // MARK: - Nettoyage

    func loadCleanup() {
        cleanupLoading = true
        Task {
            cleanup = await runInBackground { CleanupEngine.scan() }
            cleanupLoading = false
        }
    }

    func cleanSelected() {
        let cats = cleanup
        let limit: Int64? = premium ? nil : PremiumRules.freeCleanupLimit
        working = "Nettoyage en cours…"
        Task {
            let got = await runInBackground { CleanupEngine.clean(cats, limit: limit) }
            working = nil
            log("Nettoyage : \(Fmt.bytes(got)) libérés")
            notify("\(Fmt.bytes(got)) libérés")
            let remaining = cats.filter(\.selected).reduce(0) { $0 + $1.size } - got
            loadCleanup()
            if limit != nil && remaining > 1_000_000 { _ = needsPremium(.unlimitedCleanup) }
        }
    }

    // MARK: - Espace disque

    func loadSpace() {
        spaceLoading = true
        Task {
            let r = await runInBackground { SpaceEngine.scan(progress: { label in
                DispatchQueue.main.async { self.spaceLabel = label }
            }) }
            space = r
            spaceLoading = false
        }
    }

    func trashFiles(_ urls: [URL]) {
        if needsPremium(.deleteDuplicates) { return }
        Task {
            let n = await runInBackground { urls.filter { FS.trash($0) }.count }
            log("Espace disque : \(n) fichier(s) mis à la corbeille")
            notify("\(n) fichier(s) mis à la corbeille")
            loadSpace()
        }
    }

    func freeCloud(_ folder: CloudFolder) {
        if needsPremium(.cloudFree) { return }
        working = "Libération de \(folder.name)…"
        Task {
            let got = await runInBackground { SpaceEngine.freeCloud(folder) }
            working = nil
            notify("\(Fmt.bytes(got)) libérés (les fichiers restent dans le cloud)")
            loadSpace()
        }
    }

    // MARK: - Protection

    func scanThreats(full: Bool) {
        guard !threatLoading else { return }
        threatLoading = true
        stop.value = false
        threatProgress = 0
        Task {
            let found = await runInBackground {
                ThreatEngine.scan(full: full, step: { label, p in
                    DispatchQueue.main.async { self.threatStep = label; self.threatProgress = p }
                }, cancelled: { [stop = self.stop] in stop.value })
            }
            threats = found
            selectedThreats = Set(found.filter { $0.severity >= .medium }.map(\.id))
            lastThreatScan = Date()
            threatLoading = false
            log("Analyse anti-malware : \(found.count) élément(s)")
            if dangerCount > 0 && settings.notifThreats {
                Notifier.post("Menaces détectées", "OptiMac a trouvé \(dangerCount) menace(s) sur votre Mac.")
            }
        }
    }

    func stopScan() { stop.value = true }

    func removeThreats(quarantine: Bool) {
        if needsPremium(.threatRemoval) { return }
        let list = threats.filter { selectedThreats.contains($0.id) }
        guard !list.isEmpty else { return }
        working = "Traitement des menaces…"
        Task {
            let n = await runInBackground { ThreatEngine.remove(list, quarantine: quarantine) }
            working = nil
            threats.removeAll { selectedThreats.contains($0.id) }
            selectedThreats = []
            self.quarantine = ThreatEngine.loadQuarantine()
            log("\(n) menace(s) \(quarantine ? "mise(s) en quarantaine" : "supprimée(s)")")
            notify("\(n) menace(s) traitée(s)")
        }
    }

    func ignoreThreats(all: Bool) {
        let ids = all ? threats.map(\.id) : Array(selectedThreats)
        ThreatEngine.ignore(ids)
        threats.removeAll { ids.contains($0.id) }
        selectedThreats = []
    }

    func loadBrowsers() {
        Task { browsers = await runInBackground { BrowserEngine.scan() } }
    }

    func repairBrowsers() {
        if needsPremium(.browserRepair) { return }
        let list = browsers.filter(\.hijacked)
        working = "Réparation des navigateurs…"
        Task {
            for b in list { _ = await runInBackground { BrowserEngine.repair(b) } }
            working = nil
            log("Navigateurs réparés : \(list.map(\.name).joined(separator: ", "))")
            notify("Navigateurs réparés")
            loadBrowsers()
        }
    }

    func loadSecurity() {
        Task {
            security = await runInBackground { SecurityEngine.status() }
            cameraApps = await runInBackground { SecurityEngine.tccApps(service: "kTCCServiceCamera") }
            micApps = await runInBackground { SecurityEngine.tccApps(service: "kTCCServiceMicrophone") }
            privacy = await runInBackground { PrivacyEngine.scan() }
        }
    }

    func cleanPrivacy() {
        if needsPremium(.privacy) { return }
        let items = privacy
        working = "Effacement des traces…"
        Task {
            await runInBackground { PrivacyEngine.clean(items) }
            working = nil
            log("Traces de navigation effacées")
            notify("Traces effacées")
            loadSecurity()
        }
    }

    func enableFirewall() {
        Task {
            _ = await runInBackground { SecurityEngine.enableFirewall() }
            loadSecurity()
        }
    }

    func enableGatekeeper() {
        Task {
            _ = await runInBackground { SecurityEngine.enableGatekeeper() }
            loadSecurity()
        }
    }

    func disableAnalytics() {
        Task {
            let ok = await runInBackground { SecurityEngine.disableAnalyticsSharing() }
            if ok { notify("Partage d'analyses désactivé") }
        }
    }

    func createSnapshot() {
        Task {
            let ok = await runInBackground { MaintenanceEngine.snapshot() }
            notify(ok ? "Instantané créé" : "Instantané impossible (Time Machine désactivé ?)")
        }
    }

    func restore(_ q: QuarantineItem) {
        Task {
            await runInBackground { ThreatEngine.restore(q) }
            quarantine = ThreatEngine.loadQuarantine()
        }
    }

    func purge(_ q: QuarantineItem) {
        ThreatEngine.purge(q)
        quarantine = ThreatEngine.loadQuarantine()
    }

    // MARK: - Applications

    func loadApps() {
        appsLoading = true
        Task {
            let list = await runInBackground { AppsEngine.withSizes(AppsEngine.list()) }
            apps = list
            menuBarApps = AppsEngine.menuBarApps()
            startup = await runInBackground { StartupEngine.list() }
            extensions = await runInBackground { AppsEngine.extensions() }
            appsLoading = false
        }
    }

    func checkUpdates() {
        updatesLoading = true
        Task {
            apps = await AppsEngine.checkUpdates(apps)
            updatesLoading = false
        }
    }

    func uninstall(_ app: AppItem, force: Bool) {
        if force && needsPremium(.forceUninstall) { return }
        working = "Désinstallation de \(app.name)…"
        Task {
            let left = await runInBackground { AppsEngine.leftovers(for: app) }
            let ok = await runInBackground { AppsEngine.uninstall(app, leftovers: left, force: force) }
            working = nil
            log("\(app.name) \(ok ? "désinstallé" : "n'a pas pu être désinstallé")")
            notify(ok ? "\(app.name) a été supprimé" : "\(app.name) résiste : utilisez la suppression forcée")
            loadApps()
        }
    }

    func forceRemoveMenuBar(_ m: AppsEngine.MenuBarApp) {
        guard let url = m.url else {
            PerformanceEngine.quit(m.pid, force: true)
            return
        }
        let item = AppItem(url: url, name: m.name, bundleID: m.bundleID, version: "", size: 0, isAppStore: false, feedURL: nil, lastUsed: nil)
        uninstall(item, force: true)
    }

    func toggleStartup(_ item: StartupItem) {
        Task {
            await runInBackground { StartupEngine.toggle(item) }
            startup = await runInBackground { StartupEngine.list() }
        }
    }

    func removeExtension(_ e: ExtensionItem) {
        Task {
            await runInBackground { AppsEngine.removeExtension(e) }
            extensions = await runInBackground { AppsEngine.extensions() }
        }
    }

    // MARK: - Santé, réseau, outils

    func loadHealth() {
        Task {
            disk = await runInBackground { HealthEngine.disk() }
            battery = await runInBackground { HealthEngine.battery() }
            hardware = await runInBackground { HealthEngine.hardware() }
            processes = await runInBackground { PerformanceEngine.heavyProcesses() }
        }
    }

    func freeMemory() {
        Task {
            let ok = await runInBackground { PerformanceEngine.freeMemory() }
            if ok { notify("Mémoire vive libérée"); log("Mémoire vive libérée") }
            processes = await runInBackground { PerformanceEngine.heavyProcesses() }
        }
    }

    func quit(_ p: ProcessInfoItem, force: Bool) {
        PerformanceEngine.quit(p.pid, force: force)
        Task { processes = await runInBackground { PerformanceEngine.heavyProcesses() } }
    }

    func scanNetwork() {
        netLoading = true
        netProgress = 0
        Task {
            wifi = await runInBackground { NetworkEngine.wifi() }
            devices = await runInBackground { NetworkEngine.scanDevices(progress: { p in
                DispatchQueue.main.async { self.netProgress = p }
            }) }
            netLoading = false
        }
    }

    func runSpeedTest() {
        speedLoading = true
        Task {
            if let r = await NetworkEngine.speedTest() {
                speedDown = r.down; speedUp = r.up; speedPing = r.ping
            } else {
                notify("Test impossible : vérifiez votre connexion internet")
            }
            speedLoading = false
        }
    }

    func repairInternet() {
        Task {
            let ok = await runInBackground { NetworkEngine.repairConnection() }
            notify(ok ? "Connexion réparée" : "Réparation annulée")
        }
    }

    func runMaintenance() {
        if needsPremium(.maintenance) { return }
        let list = maintenance
        working = "Maintenance en cours…"
        Task {
            let ok = await runInBackground { MaintenanceEngine.run(list) }
            working = nil
            log("Maintenance \(ok ? "terminée" : "annulée")")
            notify(ok ? "Maintenance terminée" : "Maintenance annulée")
        }
    }

    func forceDelete(_ urls: [URL]) {
        if needsPremium(.forceUninstall) { return }
        Task {
            let r = await runInBackground { FileTools.forceDelete(urls) }
            log("Suppression forcée : \(r.ok) élément(s)")
            notify(r.refused.isEmpty ? "\(r.ok) élément(s) supprimé(s)" : "Refusé (élément système protégé) : \(r.refused.joined(separator: ", "))")
        }
    }

    func shred(_ urls: [URL]) {
        if needsPremium(.shredder) { return }
        Task {
            let n = await runInBackground { FileTools.shred(urls) }
            log("Broyeur : \(n) élément(s) détruit(s)")
            notify("\(n) élément(s) détruit(s) définitivement")
        }
    }

    func reduceEffects(_ on: Bool) {
        Task {
            await runInBackground { PerformanceEngine.reduceVisualEffects(on) }
            notify(on ? "Effets visuels réduits" : "Effets visuels restaurés")
        }
    }

    // MARK: - Tâches de fond (appelées toutes les heures)

    func backgroundTick() {
        let now = Date()
        if settings.weeklyCheck, now.timeIntervalSince(settings.date("lastWeeklyCheck") ?? .distantPast) > 7 * 86400 {
            settings.setDate("lastWeeklyCheck", now)
            scanThreats(full: false)
        }
        if premium, settings.autoClean != .off, settings.autoClean != .startup {
            let interval: Double = settings.autoClean == .daily ? 86400 : 7 * 86400
            let hour = Calendar.current.component(.hour, from: now)
            if hour >= settings.autoCleanHour, now.timeIntervalSince(settings.date("lastAutoClean") ?? .distantPast) > interval - 3600 {
                settings.setDate("lastAutoClean", now)
                autoCleanNow()
            }
        }
        if !premium, settings.notifPremium, now.timeIntervalSince(settings.date("lastPremiumNotif") ?? .distantPast) > 2 * 86400 {
            settings.setDate("lastPremiumNotif", now)
            Task {
                let cats = await runInBackground { CleanupEngine.scan() }
                let junk = cats.filter(\.safe).reduce(0) { $0 + $1.size }
                var body = "\(Fmt.bytes(junk)) de fichiers inutiles peuvent être nettoyés."
                if dangerCount > 0 { body += " \(dangerCount) menace(s) à supprimer." }
                Notifier.post("Votre Mac peut aller plus vite", body + " Essayez OptiMac Premium.")
            }
        }
    }

    func autoCleanNow() {
        Task {
            let cats = await runInBackground { CleanupEngine.scan() }
            let got = await runInBackground { CleanupEngine.clean(cats.filter(\.safe), limit: nil) }
            log("Nettoyage automatique : \(Fmt.bytes(got)) libérés")
            if settings.notifCleanDone { Notifier.post("Nettoyage automatique", "\(Fmt.bytes(got)) libérés.") }
        }
    }
}
