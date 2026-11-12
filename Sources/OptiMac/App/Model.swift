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
    /// Compteurs en direct pendant une analyse (accueil et anti-malware).
    @Published var scanFiles = 0
    @Published var scanCurrent = ""
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
    /// macOS n'a laissé voir aucun appareil (autorisation « Réseau local » refusée).
    @Published var netBlocked = false
    @Published var startupDenied = false
    @Published var wifi: WifiInfo?
    @Published var speedDown: Double?
    @Published var speedUp: Double?
    @Published var speedPing: Double?
    @Published var speedLoading = false
    @Published var history: [(Date, Int)] = []
    @Published var activity: [(Date, String)] = []

    private let stop = StopFlag()
    private var progressTimer: Timer?

    /// Recopie dix fois par seconde l'avancement du moteur vers l'interface.
    private func watch(_ pr: ScanProgress, update: @escaping (Double, String) -> Void) {
        progressTimer?.invalidate()
        scanFiles = 0
        scanCurrent = ""
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let s = pr.snapshot()
            Task { @MainActor in
                guard let self else { return }
                if s.files != self.scanFiles { Sound.tick.play() }
                self.scanFiles = s.files
                self.scanCurrent = s.current
                update(s.fraction, s.label)
            }
        }
    }

    private func unwatch() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

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
        Sound.start.play()
        Task { await runScan() }
    }

    private func runScan() async {
        let pr = ScanProgress()
        watch(pr) { [weak self] fraction, _ in self?.progress = fraction }

        progressLabel = "Recherche des fichiers inutiles…"
        pr.setRange(base: 0, span: 0.35)
        cleanup = await runInBackground { CleanupEngine.scan(progress: pr) }

        progressLabel = "Recherche des menaces…"
        pr.setRange(base: 0.35, span: 0.35)
        let found = await runInBackground { ThreatEngine.scan(full: false, progress: pr, cancelled: { false }) }
        threats = found
        selectedThreats = Set(found.filter { $0.severity >= .medium }.map(\.id))
        lastThreatScan = Date()

        progressLabel = "Vérification des navigateurs…"
        pr.setRange(base: 0.7, span: 0.1)
        browsers = await runInBackground { BrowserEngine.scan() }

        progressLabel = "Analyse du démarrage…"
        pr.setRange(base: 0.8, span: 0.1)
        startup = await runInBackground { StartupEngine.list() }

        progressLabel = "Santé du disque…"
        pr.setRange(base: 0.9, span: 0.1)
        disk = await runInBackground { HealthEngine.disk() }
        unwatch()
        progress = 1

        buildFindings()
        let s = computeScore()
        score = s
        ScoreHistory.add(s)
        history = ScoreHistory.load()
        lastScan = Date()
        settings.setDate("lastScan", lastScan)
        phase = .results
        (dangerCount + hijackedCount > 0 ? Sound.alert : Sound.found).play()
        log("Analyse complète : score \(s)/100 (\(Fmt.number(scanFiles)) fichiers examinés)")
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
        Sound.boost.play()
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
                let list = startup.filter { $0.useless && $0.enabled && $0.kind == .agent }
                await runInBackground { StartupEngine.setEnabled(list, false) }
                startup = await runInBackground { StartupEngine.list() }
            }
            boostSteps.append("Terminé")
            phase = .done
            Sound.success.play()
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
            Sound.success.play()
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
        Sound.start.play()
        let pr = ScanProgress()
        watch(pr) { [weak self] fraction, label in
            self?.threatProgress = fraction
            self?.threatStep = label
        }
        Task {
            let found = await runInBackground {
                ThreatEngine.scan(full: full, progress: pr, cancelled: { [stop = self.stop] in stop.value })
            }
            unwatch()
            threats = found
            selectedThreats = Set(found.filter { $0.severity >= .medium }.map(\.id))
            lastThreatScan = Date()
            threatLoading = false
            (dangerCount > 0 ? Sound.alert : Sound.success).play()
            log("Analyse anti-malware : \(Fmt.number(scanFiles)) fichiers examinés, \(found.count) élément(s) signalé(s)")
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
            Sound.success.play()
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
            startupDenied = StartupEngine.loginItemsDenied
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

    /// Désinstalle une ou plusieurs applications (un seul mot de passe pour toute la sélection).
    func uninstall(_ list: [AppItem], force: Bool) {
        guard !list.isEmpty else { return }
        if force && needsPremium(.forceUninstall) { return }
        working = list.count == 1 ? "Désinstallation de \(list[0].name)…" : "Désinstallation de \(list.count) applications…"
        Task {
            let removed = await runInBackground {
                AppsEngine.uninstall(list, force: force) { app in
                    DispatchQueue.main.async { self.working = "Désinstallation de \(app.name)…" }
                }
            }
            working = nil
            let failed = list.filter { a in !removed.contains(a) }
            let freedSize = removed.reduce(Int64(0)) { $0 + $1.size }
            log("Désinstallation : \(removed.map(\.name).joined(separator: ", "))" + (failed.isEmpty ? "" : " — échec : \(failed.map(\.name).joined(separator: ", "))"))
            if failed.isEmpty {
                Sound.success.play()
                notify(removed.count == 1 ? "\(removed[0].name) a été supprimé" : "\(removed.count) applications supprimées (\(Fmt.bytes(freedSize)))")
            } else {
                notify("\(failed.map(\.name).joined(separator: ", ")) résiste : utilisez la suppression forcée")
            }
            loadApps()
        }
    }

    func forceRemoveMenuBar(_ m: AppsEngine.MenuBarApp) {
        guard let url = m.url else {
            PerformanceEngine.quit(m.pid, force: true)
            return
        }
        let item = AppItem(url: url, name: m.name, bundleID: m.bundleID, version: "", size: 0, isAppStore: false, feedURL: nil, lastUsed: nil)
        uninstall([item], force: true)
    }

    /// Active ou désactive des éléments de démarrage. L'interrupteur bouge tout de suite, puis l'état réel est relu.
    func setStartup(_ items: [StartupItem], enabled: Bool) {
        let ids = Set(items.map(\.id))
        for i in startup.indices where ids.contains(startup[i].id) { startup[i].enabled = enabled }
        Sound.click.play()
        Task {
            await runInBackground { StartupEngine.setEnabled(items, enabled) }
            startup = await runInBackground { StartupEngine.list() }
            startupDenied = StartupEngine.loginItemsDenied
            let stuck = startup.filter { ids.contains($0.id) && $0.enabled != enabled }
            if stuck.isEmpty {
                notify(items.count == 1 ? "\(items[0].name) : \(enabled ? "réactivé" : "désactivé au démarrage")" : "\(items.count) éléments \(enabled ? "réactivés" : "désactivés")")
                log("Démarrage : \(items.map(\.name).joined(separator: ", ")) \(enabled ? "réactivé(s)" : "désactivé(s)")")
            } else {
                notify("macOS a refusé pour : \(stuck.map(\.name).joined(separator: ", "))")
            }
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
        netBlocked = false
        netProgress = 0
        Sound.start.play()
        Task {
            wifi = await runInBackground { NetworkEngine.wifi() }
            devices = await runInBackground { NetworkEngine.scanDevices(progress: { p in
                DispatchQueue.main.async { self.netProgress = p }
            }) }
            netLoading = false
            netBlocked = devices.filter { !$0.isSelf }.isEmpty
            if devices.contains(where: \.isNew) { Sound.found.play() } else if !netBlocked { Sound.success.play() }
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
