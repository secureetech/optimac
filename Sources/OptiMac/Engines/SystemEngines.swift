import Foundation
import AppKit
import Darwin
import Security

// MARK: - Démarrage

struct StartupItem: Identifiable, Hashable {
    enum Kind { case loginItem, agent, daemon }
    let id: String
    let name: String
    let detail: String
    let kind: Kind
    let plist: URL?
    var enabled: Bool
    let useless: Bool
}

enum StartupEngine {
    static var disabledDir: URL {
        let u = FS.supportDir.appendingPathComponent("Démarrage désactivé")
        FS.ensureDir(u)
        return u
    }

    /// Programmes souvent inutiles au démarrage (le programme reste installé).
    static let uselessHints = ["update", "updater", "helper", "agent", "adobe", "google.keystone", "microsoft.update", "spotify",
                               "skype", "zoom", "teams", "dropbox", "steam", "epic", "discord", "hp", "canon", "epson", "logi", "java"]

    static func list() -> [StartupItem] {
        var out: [StartupItem] = []
        let r = Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to get the name of every login item"], timeout: 10)
        for n in r.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ", ") where !n.isEmpty && n != "OptiMac" {
            out.append(StartupItem(id: "login:" + n, name: n, detail: "S'ouvre à la connexion", kind: .loginItem, plist: nil, enabled: true,
                                   useless: uselessHints.contains { n.lowercased().contains($0) }))
        }
        for (dir, admin) in ThreatEngine.launchDirs {
            for p in FS.children(dir) where p.pathExtension == "plist" {
                let (label, program) = ThreatEngine.launchProgram(p)
                if label.hasPrefix("com.apple.") || label.contains("secureetech") { continue }
                out.append(StartupItem(id: p.path, name: niceName(label), detail: program.isEmpty ? label : program,
                                       kind: admin ? .daemon : .agent, plist: p, enabled: true,
                                       useless: uselessHints.contains { label.lowercased().contains($0) }))
            }
        }
        for p in FS.children(disabledDir) where p.pathExtension == "plist" {
            let (label, program) = ThreatEngine.launchProgram(p)
            out.append(StartupItem(id: p.path, name: niceName(label), detail: program, kind: .agent, plist: p, enabled: false, useless: false))
        }
        return out
    }

    static func niceName(_ label: String) -> String {
        let parts = label.split(separator: ".")
        guard parts.count >= 2 else { return label }
        return parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Désactive (déplace dans un dossier OptiMac, réversible) ou réactive.
    static func toggle(_ item: StartupItem) {
        let uid = getuid()
        switch item.kind {
        case .loginItem:
            let n = item.name.replacingOccurrences(of: "\"", with: "")
            Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to delete login item \"\(n)\""], timeout: 10)
        case .agent, .daemon:
            guard let p = item.plist else { return }
            if item.enabled {
                let dest = disabledDir.appendingPathComponent(p.lastPathComponent)
                let origin = dest.appendingPathExtension("origine")
                try? p.deletingLastPathComponent().path.write(to: origin, atomically: true, encoding: .utf8)
                if item.kind == .daemon || !FS.fm.isWritableFile(atPath: p.deletingLastPathComponent().path) {
                    let domain = p.path.contains("LaunchDaemons") ? "system" : "gui/\(uid)"
                    Shell.admin(["launchctl bootout \(domain) \(Shell.quote(p.path))",
                                 "mv \(Shell.quote(p.path)) \(Shell.quote(dest.path))", "chown \(uid) \(Shell.quote(dest.path))"])
                } else {
                    Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", p.path])
                    try? FS.fm.moveItem(at: p, to: dest)
                }
            } else {
                let origin = p.appendingPathExtension("origine")
                let dir = (try? String(contentsOf: origin, encoding: .utf8)) ?? FS.lib("LaunchAgents").path
                let dest = URL(fileURLWithPath: dir).appendingPathComponent(p.lastPathComponent)
                if dir.hasPrefix(FS.home.path) {
                    try? FS.fm.moveItem(at: p, to: dest)
                    Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", dest.path])
                } else {
                    let domain = dir.contains("LaunchDaemons") ? "system" : "gui/\(uid)"
                    Shell.admin(["mv \(Shell.quote(p.path)) \(Shell.quote(dest.path))", "chown root:wheel \(Shell.quote(dest.path))",
                                 "launchctl bootstrap \(domain) \(Shell.quote(dest.path))"])
                }
                try? FS.fm.removeItem(at: origin)
            }
        }
    }

    // MARK: Lancement d'OptiMac à l'ouverture de session (compatible macOS 11)

    static var selfAgent: URL { FS.lib("LaunchAgents/com.secureetech.optimac.plist") }

    static func setLaunchAtLogin(_ on: Bool) {
        if on {
            guard let exe = Bundle.main.executableURL?.path else { return }
            let plist: [String: Any] = ["Label": "com.secureetech.optimac", "ProgramArguments": [exe, "--login"],
                                        "RunAtLoad": true, "LimitLoadToSessionType": "Aqua"]
            FS.ensureDir(selfAgent.deletingLastPathComponent())
            (plist as NSDictionary).write(to: selfAgent, atomically: true)
        } else {
            try? FS.fm.removeItem(at: selfAgent)
        }
    }
}

// MARK: - Mémoire, processus, effets visuels

struct ProcessInfoItem: Identifiable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpu: Double
    let memory: Int64
    let icon: NSImage?
}

enum PerformanceEngine {
    static func heavyProcesses() -> [ProcessInfoItem] {
        let r = Shell.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm="], timeout: 10)
        let apps = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [ProcessInfoItem] = []
        for line in r.out.components(separatedBy: .newlines) {
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count == 4, let pid = Int32(f[0]), let cpu = Double(f[1].replacingOccurrences(of: ",", with: ".")), let rss = Int64(f[2]) else { continue }
            let app = apps[pid]
            if pid == getpid() { continue }
            out.append(ProcessInfoItem(pid: pid, name: app?.localizedName ?? String(f[3]), cpu: cpu, memory: rss * 1024, icon: app?.icon))
        }
        return out.sorted { ($0.cpu * 40 + Double($0.memory) / 50_000_000) > ($1.cpu * 40 + Double($1.memory) / 50_000_000) }
            .prefix(12).map { $0 }
    }

    static func quit(_ pid: Int32, force: Bool) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = force ? app.forceTerminate() : app.terminate()
        } else {
            kill(pid, force ? SIGKILL : SIGTERM)
        }
    }

    /// Libère la mémoire inactive (commande « purge » d'Apple).
    static func freeMemory() -> Bool {
        Shell.admin(["/usr/sbin/purge"], prompt: "OptiMac va libérer la mémoire vive de votre Mac.").ok
    }

    /// Moins d'animations = Mac plus réactif.
    static func reduceVisualEffects(_ reduce: Bool) {
        if reduce {
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "launchanim", "-bool", "false"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "mineffect", "-string", "scale"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "expose-animation-duration", "-float", "0.1"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-time-modifier", "-float", "0.2"])
            Shell.run("/usr/bin/defaults", ["write", "-g", "NSWindowResizeTime", "-float", "0.001"])
            Shell.run("/usr/bin/defaults", ["write", "-g", "NSAutomaticWindowAnimationsEnabled", "-bool", "false"])
            Shell.run("/usr/bin/defaults", ["write", "com.apple.universalaccess", "reduceTransparency", "-bool", "true"])
        } else {
            for (d, k) in [("com.apple.dock", "launchanim"), ("com.apple.dock", "mineffect"), ("com.apple.dock", "expose-animation-duration"),
                           ("com.apple.dock", "autohide-time-modifier"), ("-g", "NSWindowResizeTime"), ("-g", "NSAutomaticWindowAnimationsEnabled"),
                           ("com.apple.universalaccess", "reduceTransparency")] {
                Shell.run("/usr/bin/defaults", ["delete", d, k])
            }
        }
        Shell.run("/usr/bin/killall", ["Dock"])
    }
}

// MARK: - Maintenance

struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let admin: Bool
    let commands: [String]
    var selected: Bool
}

enum MaintenanceEngine {
    static func tasks() -> [MaintenanceTask] {
        let lsreg = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        var mailCmds: [String] = []
        for v in FS.children(FS.lib("Mail")) where v.lastPathComponent.hasPrefix("V") {
            let idx = v.appendingPathComponent("MailData/Envelope Index")
            if FS.exists(idx) { mailCmds.append("/usr/bin/sqlite3 \(Shell.quote(idx.path)) 'vacuum;'") }
        }
        return [
            MaintenanceTask(id: "dns", title: "Réparer internet", detail: "Vide le cache DNS quand des pages ne s'ouvrent plus.", admin: true,
                            commands: ["dscacheutil -flushcache", "killall -HUP mDNSResponder"], selected: true),
            MaintenanceTask(id: "purgeable", title: "Libérer l'espace purgeable", detail: "Récupère l'espace réservé par macOS pour les instantanés.", admin: true,
                            commands: ["tmutil thinlocalsnapshots / 999999999999 4"], selected: true),
            MaintenanceTask(id: "spotlight", title: "Réindexer Spotlight", detail: "Répare la recherche quand elle ne trouve plus vos fichiers.", admin: true,
                            commands: ["mdutil -E /"], selected: false),
            MaintenanceTask(id: "launchservices", title: "Réparer « Ouvrir avec »", detail: "Supprime les doublons dans le menu Ouvrir avec.", admin: false,
                            commands: ["\(lsreg) -kill -r -domain local -domain system -domain user"], selected: true),
            MaintenanceTask(id: "mail", title: "Accélérer Mail", detail: "Compacte la base de données de Mail (Mail doit être fermé).", admin: false,
                            commands: mailCmds, selected: !mailCmds.isEmpty),
            MaintenanceTask(id: "fonts", title: "Réparer les polices", detail: "Reconstruit le cache des polices de caractères.", admin: true,
                            commands: ["atsutil databases -remove"], selected: false),
            MaintenanceTask(id: "permissions", title: "Réparer les autorisations", detail: "Remet en ordre les droits de votre dossier personnel.", admin: true,
                            commands: ["diskutil resetUserPermissions / \(getuid())"], selected: false),
            MaintenanceTask(id: "snapshots", title: "Alléger Time Machine", detail: "Supprime les instantanés locaux de Time Machine.", admin: true,
                            commands: ["tmutil deletelocalsnapshots /"], selected: false),
            MaintenanceTask(id: "periodic", title: "Scripts d'entretien de macOS", detail: "Lance les tâches d'entretien quotidiennes, hebdomadaires et mensuelles.", admin: true,
                            commands: ["periodic daily weekly monthly"], selected: false)
        ]
    }

    static func run(_ tasks: [MaintenanceTask]) -> Bool {
        let chosen = tasks.filter(\.selected)
        if chosen.contains(where: { $0.id == "mail" }) {
            for a in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail") { a.terminate() }
            Thread.sleep(forTimeInterval: 1)
        }
        for t in chosen where !t.admin { t.commands.forEach { Shell.sh($0, timeout: 300) } }
        let admin = chosen.filter(\.admin).flatMap(\.commands)
        return admin.isEmpty ? true : Shell.admin(admin, prompt: "OptiMac va lancer la maintenance de votre Mac.").ok
    }

    /// Instantané Time Machine avant une optimisation (point de restauration).
    @discardableResult
    static func snapshot() -> Bool {
        Shell.run("/usr/bin/tmutil", ["localsnapshot"], timeout: 60).ok
    }

    static func snapshots() -> [String] {
        Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 30).out
            .components(separatedBy: .newlines).filter { $0.contains("com.apple.TimeMachine") }
    }
}

// MARK: - Santé du Mac

struct DiskHealth {
    var name = "Disque"
    var smart = "Inconnu"
    var solidState = true
    var protocolName = ""
    var total: Int64 = 0
    var free: Int64 = 0
    var ok: Bool { smart.lowercased().contains("verified") || smart.lowercased().contains("vérifié") }
}

struct BatteryHealth {
    var present = false
    var cycles = 0
    var capacity: Double = 1
    var temperature: Double?
    var charging = false
    var level = 0
    var condition: String { capacity >= 0.8 ? "Normale" : "Entretien recommandé" }
}

struct HardwareInfo {
    var model = ""
    var chip = ""
    var memory = ""
    var serial = ""
    var macOS = ""
}

enum HealthEngine {
    static func disk() -> DiskHealth {
        var h = DiskHealth()
        let r = Shell.run("/usr/sbin/diskutil", ["info", "-plist", "/"], timeout: 20)
        if let d = try? PropertyListSerialization.propertyList(from: Data(r.out.utf8), format: nil) as? [String: Any] {
            h.name = d["MediaName"] as? String ?? d["VolumeName"] as? String ?? "Disque"
            h.smart = d["SMARTStatus"] as? String ?? "Inconnu"
            h.solidState = d["SolidState"] as? Bool ?? true
            h.protocolName = d["BusProtocol"] as? String ?? ""
        }
        if h.smart == "Not Supported" || h.smart == "Inconnu" {
            let w = Shell.run("/usr/sbin/diskutil", ["info", "-plist", "disk0"], timeout: 20)
            if let d = try? PropertyListSerialization.propertyList(from: Data(w.out.utf8), format: nil) as? [String: Any] {
                h.smart = d["SMARTStatus"] as? String ?? h.smart
                h.name = d["MediaName"] as? String ?? h.name
            }
        }
        let v = FS.volume()
        h.total = v.total
        h.free = v.free
        return h
    }

    static func battery() -> BatteryHealth {
        var b = BatteryHealth()
        let r = Shell.run("/usr/sbin/ioreg", ["-a", "-r", "-c", "AppleSmartBattery"], timeout: 10)
        guard let arr = try? PropertyListSerialization.propertyList(from: Data(r.out.utf8), format: nil) as? [[String: Any]],
              let d = arr.first else { return b }
        b.present = true
        b.cycles = d["CycleCount"] as? Int ?? 0
        let design = Double(d["DesignCapacity"] as? Int ?? 0)
        let maxCap = Double(d["AppleRawMaxCapacity"] as? Int ?? d["NominalChargeCapacity"] as? Int ?? d["MaxCapacity"] as? Int ?? 0)
        if design > 0, maxCap > 100 { b.capacity = min(1, maxCap / design) }
        if let t = d["Temperature"] as? Int { b.temperature = Double(t) / 100 }
        b.charging = d["IsCharging"] as? Bool ?? false
        let cur = Double(d["CurrentCapacity"] as? Int ?? 0)
        let mx = Double(d["MaxCapacity"] as? Int ?? 100)
        b.level = mx > 0 ? Int(cur / (mx > 100 ? mx : 100) * 100) : 0
        return b
    }

    static func hardware() -> HardwareInfo {
        var h = HardwareInfo()
        let r = Shell.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"], timeout: 30)
        if let j = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any],
           let d = (j["SPHardwareDataType"] as? [[String: Any]])?.first {
            h.model = d["machine_name"] as? String ?? SystemInfo.modelIdentifier
            h.chip = d["chip_type"] as? String ?? d["cpu_type"] as? String ?? ""
            h.memory = d["physical_memory"] as? String ?? ""
            h.serial = d["serial_number"] as? String ?? ""
        }
        h.macOS = SystemInfo.osVersion
        return h
    }

    /// Température approximative : batterie si disponible, sinon état thermique de macOS.
    static func temperature() -> Double? { battery().temperature }
}

// MARK: - Réseau

struct NetDevice: Identifiable {
    var id: String { ip }
    let ip: String
    let mac: String
    let name: String
    let isGateway: Bool
    let isSelf: Bool
}

struct WifiInfo {
    var ssid = ""
    var security = ""
    var secure: Bool { !security.isEmpty && !security.lowercased().contains("none") && !security.uppercased().contains("WEP") }
}

enum NetworkEngine {
    static func localAddress() -> (ip: String, iface: String)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            if let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 {
                let name = String(cString: p.pointee.ifa_name)
                if name.hasPrefix("en") {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    return (String(cString: host), name)
                }
            }
            ptr = p.pointee.ifa_next
        }
        return nil
    }

    static func gateway() -> String {
        let r = Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 10)
        for l in r.out.components(separatedBy: .newlines) where l.contains("gateway:") {
            return l.components(separatedBy: "gateway:").last?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        return ""
    }

    static func scanDevices(progress: @escaping (Double) -> Void) -> [NetDevice] {
        guard let me = localAddress() else { return [] }
        let gw = gateway()
        let parts = me.ip.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let prefix = parts.prefix(3).joined(separator: ".")
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: 48)
        var done = 0
        let lock = NSLock()
        for i in 1...254 {
            group.enter()
            DispatchQueue.global().async {
                sem.wait()
                Shell.run("/sbin/ping", ["-c", "1", "-t", "1", "\(prefix).\(i)"], timeout: 3)
                sem.signal()
                lock.lock(); done += 1; let d = done; lock.unlock()
                if d % 16 == 0 { progress(Double(d) / 254) }
                group.leave()
            }
        }
        group.wait()
        let r = Shell.run("/usr/sbin/arp", ["-an"], timeout: 15)
        var out: [NetDevice] = []
        for line in r.out.components(separatedBy: .newlines) {
            guard let o = line.firstIndex(of: "("), let c = line.firstIndex(of: ")") else { continue }
            let ip = String(line[line.index(after: o)..<c])
            guard ip.hasPrefix(prefix + "."), line.contains(" at "), !line.contains("incomplete") else { continue }
            let mac = line.components(separatedBy: " at ").last?.components(separatedBy: " ").first ?? ""
            if mac == "ff:ff:ff:ff:ff:ff" { continue }
            let name = ip == gw ? "Box internet" : "Appareil"
            out.append(NetDevice(ip: ip, mac: mac, name: name, isGateway: ip == gw, isSelf: false))
        }
        out.append(NetDevice(ip: me.ip, mac: "", name: "Ce Mac (\(SystemInfo.hostname))", isGateway: false, isSelf: true))
        return out.sorted { a, b in
            let x = Int(a.ip.split(separator: ".").last ?? "0") ?? 0, y = Int(b.ip.split(separator: ".").last ?? "0") ?? 0
            return x < y
        }
    }

    static func wifi() -> WifiInfo {
        var w = WifiInfo()
        let airport = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
        if FS.fm.fileExists(atPath: airport) {
            let r = Shell.run(airport, ["-I"], timeout: 10)
            for l in r.out.components(separatedBy: .newlines) {
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("SSID:") { w.ssid = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                if t.hasPrefix("link auth:") { w.security = String(t.dropFirst(10)).trimmingCharacters(in: .whitespaces) }
            }
        }
        if w.ssid.isEmpty {
            let r = Shell.run("/usr/sbin/system_profiler", ["SPAirPortDataType", "-json"], timeout: 30)
            if let j = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any],
               let ifs = ((j["SPAirPortDataType"] as? [[String: Any]])?.first?["spairport_airport_interfaces"] as? [[String: Any]]),
               let cur = ifs.compactMap({ $0["spairport_current_network_information"] as? [String: Any] }).first {
                w.ssid = cur["_name"] as? String ?? ""
                w.security = cur["spairport_security_mode"] as? String ?? ""
            }
        }
        return w
    }

    /// Test de vitesse (téléchargement d'environ 25 Mo + envoi de 5 Mo) via Cloudflare.
    static func speedTest() async -> (down: Double, up: Double, ping: Double)? {
        let t0 = Date()
        let (_, c0, _) = await HTTP.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=0")!, timeout: 10)
        guard c0 == 200 else { return nil }
        let ping = Date().timeIntervalSince(t0) * 1000
        let t1 = Date()
        let (d, c1, _) = await HTTP.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!, timeout: 60)
        guard c1 == 200, let d else { return nil }
        let down = Double(d.count) * 8 / Date().timeIntervalSince(t1) / 1_000_000
        var req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
        req.httpMethod = "POST"
        req.httpBody = Data(count: 5_000_000)
        req.timeoutInterval = 60
        let t2 = Date()
        let (_, c2, _) = await HTTP.data(for: req)
        let up = c2 == 200 ? 5_000_000 * 8 / Date().timeIntervalSince(t2) / 1_000_000 : 0
        return (down, up, ping)
    }

    static func repairConnection() -> Bool {
        Shell.admin(["dscacheutil -flushcache", "killall -HUP mDNSResponder"], prompt: "OptiMac va réparer la connexion internet.").ok
    }
}

// MARK: - Sécurité de macOS

struct SecurityStatus {
    var firewall = false
    var gatekeeper = true
    var fileVault = false
    var sip = true
    var autoUpdates = true
    var score: Int {
        var s = 100
        if !firewall { s -= 15 }
        if !gatekeeper { s -= 30 }
        if !fileVault { s -= 10 }
        if !sip { s -= 30 }
        if !autoUpdates { s -= 10 }
        return max(0, s)
    }
}

enum SecurityEngine {
    static func status() -> SecurityStatus {
        var s = SecurityStatus()
        let fw = Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], timeout: 10).out.lowercased()
        s.firewall = fw.contains("enabled") || fw.contains("state = 1")
        s.gatekeeper = Shell.run("/usr/sbin/spctl", ["--status"], timeout: 10).out.contains("enabled")
        s.fileVault = Shell.run("/usr/bin/fdesetup", ["status"], timeout: 10).out.contains("On")
        s.sip = Shell.run("/usr/bin/csrutil", ["status"], timeout: 10).out.contains("enabled")
        let au = Shell.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.SoftwareUpdate", "AutomaticCheckEnabled"], timeout: 10).out
        s.autoUpdates = !au.contains("0")
        return s
    }

    static func enableFirewall() -> Bool {
        Shell.admin(["/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on",
                     "/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on"],
                    prompt: "OptiMac va activer le pare-feu de macOS.").ok
    }

    static func enableGatekeeper() -> Bool {
        Shell.admin(["spctl --master-enable"], prompt: "OptiMac va réactiver Gatekeeper.").ok
    }

    static func openFileVault() {
        Links.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?FDE")!)
    }

    static func openPrivacy(_ anchor: String) {
        Links.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    /// Applications ayant obtenu l'accès caméra / micro (nécessite l'Accès complet au disque).
    static func tccApps(service: String) -> [String] {
        let db = FS.lib("Application Support/com.apple.TCC/TCC.db")
        let r = Shell.run("/usr/bin/sqlite3", [db.path, "select client from access where service='\(service)' and (auth_value=2 or allowed=1);"], timeout: 10)
        return r.out.components(separatedBy: .newlines).filter { !$0.isEmpty }.map { id in
            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return u.deletingPathExtension().lastPathComponent }
            return id
        }
    }

    static var analyticsSharing: Bool {
        let r = Shell.run("/usr/bin/defaults", ["read", "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist", "AutoSubmit"], timeout: 10)
        return r.out.contains("1")
    }

    static func disableAnalyticsSharing() -> Bool {
        Shell.admin(["defaults write '/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist' AutoSubmit -bool false",
                     "defaults write '/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist' ThirdPartyDataSubmit -bool false"],
                    prompt: "OptiMac va désactiver le partage d'analyses.").ok
    }
}

// MARK: - Vie privée

struct PrivacyItem: Identifiable {
    let id: String
    let name: String
    let detail: String
    let count: Int
    var selected: Bool
}

enum PrivacyEngine {
    private static func sqliteCount(_ db: URL, _ sql: String) -> Int {
        guard FS.exists(db) else { return 0 }
        let tmp = FS.fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        defer { try? FS.fm.removeItem(at: tmp) }
        guard (try? FS.fm.copyItem(at: db, to: tmp)) != nil else { return 0 }
        return Int(Shell.run("/usr/bin/sqlite3", [tmp.path, sql], timeout: 15).out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func scan() -> [PrivacyItem] {
        var out: [PrivacyItem] = []
        let safariHist = sqliteCount(FS.lib("Safari/History.db"), "select count(*) from history_items;")
        let safariCookies = FS.exists(FS.lib("Cookies/Cookies.binarycookies")) || FS.exists(FS.lib("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")) ? 1 : 0
        out.append(PrivacyItem(id: "safari", name: "Safari", detail: "Historique et cookies de suivi", count: safariHist + safariCookies, selected: true))
        var chromeHist = 0, chromeCookies = 0
        for (_, p) in ThreatEngine.chromiumProfiles() {
            chromeHist += sqliteCount(p.appendingPathComponent("History"), "select count(*) from urls;")
            chromeCookies += sqliteCount(p.appendingPathComponent("Cookies"), "select count(*) from cookies;")
        }
        out.append(PrivacyItem(id: "chromium", name: "Chrome, Edge, Brave", detail: "Historique et cookies de suivi", count: chromeHist + chromeCookies, selected: true))
        var ff = 0
        for p in FS.children(FS.lib("Application Support/Firefox/Profiles")) {
            ff += sqliteCount(p.appendingPathComponent("places.sqlite"), "select count(*) from moz_historyvisits;")
            ff += sqliteCount(p.appendingPathComponent("cookies.sqlite"), "select count(*) from moz_cookies;")
        }
        out.append(PrivacyItem(id: "firefox", name: "Firefox", detail: "Historique et cookies de suivi", count: ff, selected: true))
        let recents = FS.children(FS.lib("Application Support/com.apple.sharedfilelist")).filter { $0.lastPathComponent.contains("Recent") }
        out.append(PrivacyItem(id: "recent", name: "Éléments récents", detail: "Documents et applications ouverts récemment", count: recents.count, selected: true))
        let nets = wifiNetworks()
        out.append(PrivacyItem(id: "wifi", name: "Anciens réseaux Wi-Fi", detail: "Réseaux mémorisés (hôtels, gares…)", count: nets.count, selected: false))
        return out.filter { $0.count > 0 }
    }

    static func wifiInterface() -> String {
        let r = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 10)
        let lines = r.out.components(separatedBy: .newlines)
        for (i, l) in lines.enumerated() where l.contains("Wi-Fi") || l.contains("AirPort") {
            if i + 1 < lines.count, lines[i + 1].hasPrefix("Device:") { return lines[i + 1].replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        return "en0"
    }

    static func wifiNetworks() -> [String] {
        let r = Shell.run("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", wifiInterface()], timeout: 10)
        let current = NetworkEngine.wifi().ssid
        return r.out.components(separatedBy: .newlines).dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != current }
    }

    static func clean(_ items: [PrivacyItem]) {
        var admin: [String] = []
        for it in items where it.selected {
            switch it.id {
            case "safari":
                quit("com.apple.Safari")
                Shell.run("/usr/bin/sqlite3", [FS.lib("Safari/History.db").path, "delete from history_visits; delete from history_items;"])
                for c in [FS.lib("Cookies/Cookies.binarycookies"), FS.lib("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")] { FS.remove(c) }
            case "chromium":
                ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"].forEach(quit)
                for (_, p) in ThreatEngine.chromiumProfiles() {
                    for f in ["History", "History-journal", "Cookies", "Cookies-journal", "Visited Links", "Top Sites"] { FS.remove(p.appendingPathComponent(f)) }
                }
            case "firefox":
                quit("org.mozilla.firefox")
                for p in FS.children(FS.lib("Application Support/Firefox/Profiles")) {
                    Shell.run("/usr/bin/sqlite3", [p.appendingPathComponent("places.sqlite").path, "delete from moz_historyvisits;"])
                    FS.remove(p.appendingPathComponent("cookies.sqlite"))
                    FS.remove(p.appendingPathComponent("formhistory.sqlite"))
                }
            case "recent":
                for f in FS.children(FS.lib("Application Support/com.apple.sharedfilelist")) where f.lastPathComponent.contains("Recent") { FS.remove(f) }
                Shell.run("/usr/bin/killall", ["sharedfilelistd"])
            case "wifi":
                let iface = wifiInterface()
                for n in wifiNetworks() { admin.append("networksetup -removepreferredwirelessnetwork \(iface) \(Shell.quote(n))") }
            default: break
            }
        }
        if !admin.isEmpty { Shell.admin(admin, prompt: "OptiMac va oublier les anciens réseaux Wi-Fi.") }
    }

    private static func quit(_ bid: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        apps.forEach { $0.terminate() }
        if !apps.isEmpty { Thread.sleep(forTimeInterval: 1.5) }
    }
}

// MARK: - Outils : suppression forcée et broyeur

enum FileTools {
    /// Supprime un fichier ou dossier que macOS refuse de supprimer.
    static func forceDelete(_ urls: [URL]) -> (ok: Int, refused: [String]) {
        var ok = 0
        var refused: [String] = []
        var admin: [String] = []
        for u in urls {
            if FS.isProtected(u) { refused.append(u.lastPathComponent); continue }
            Shell.run("/usr/bin/chflags", ["-R", "nouchg", u.path])
            for app in NSWorkspace.shared.runningApplications where app.bundleURL == u { app.forceTerminate() }
            if (try? FS.fm.removeItem(at: u)) != nil { ok += 1; continue }
            admin.append("chflags -R nouchg,noschg \(Shell.quote(u.path)); rm -rf \(Shell.quote(u.path))")
        }
        if !admin.isEmpty, Shell.admin(admin, prompt: "OptiMac va supprimer de force les éléments bloqués.").ok {
            ok += urls.filter { !FS.exists($0) }.count - ok
        }
        return (ok, refused)
    }

    /// Broyeur : écrase le contenu avec des données aléatoires avant de supprimer.
    static func shred(_ urls: [URL]) -> Int {
        var count = 0
        for u in urls where !FS.isProtected(u) {
            var files: [URL] = []
            if FS.isDir(u), let en = FS.fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let f as URL in en where (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { files.append(f) }
            } else {
                files = [u]
            }
            for f in files {
                guard let h = try? FileHandle(forWritingTo: f) else { continue }
                let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                var written = 0
                while written < size {
                    let n = min(1_048_576, size - written)
                    var bytes = [UInt8](repeating: 0, count: n)
                    _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
                    h.write(Data(bytes))
                    written += n
                }
                h.synchronizeFile()
                try? h.close()
            }
            if (try? FS.fm.removeItem(at: u)) != nil { count += 1 }
        }
        return count
    }
}

// MARK: - Rappel par un technicien SecureeTech

enum Callback {
    static func send(firstName: String, phone: String, subject: String, premium: Bool) async -> (Bool, String) {
        let tel = phone.filter { $0.isNumber || $0 == "+" }
        guard tel.count >= 9 else { return (false, "Numéro de téléphone invalide.") }
        var req = URLRequest(url: URL(string: "https://crm-secureetech.up.railway.app/api/rappel-optipc")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["prenom": firstName, "telephone": phone, "sujet": subject, "source": "logiciel",
                                   "machine": SystemInfo.machineID, "version": "OptiMac \(SystemInfo.appVersion)",
                                   "premium": premium, "pc": SystemInfo.hostname]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, code, _) = await HTTP.data(for: req)
        let j = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        if code == 200, j["ok"] as? Bool ?? true {
            return (true, "Demande envoyée : un technicien SecureeTech vous rappelle rapidement.")
        }
        return (false, "La demande n'a pas pu être envoyée. Appelez directement le \(Links.support) (du lundi au vendredi, de 10 h à 17 h).")
    }
}

// MARK: - Historique du score sur 30 jours

enum ScoreHistory {
    private static var url: URL { FS.supportDir.appendingPathComponent("score.json") }

    static func load() -> [(Date, Int)] {
        guard let d = try? Data(contentsOf: url), let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        let cut = Date().addingTimeInterval(-30 * 86400)
        return arr.compactMap { e in
            guard let t = e["d"] as? Double, let s = e["s"] as? Int else { return nil }
            let date = Date(timeIntervalSince1970: t)
            return date > cut ? (date, s) : nil
        }
    }

    static func add(_ score: Int) {
        var items = load().map { ["d": $0.0.timeIntervalSince1970, "s": $0.1] as [String: Any] }
        items.append(["d": Date().timeIntervalSince1970, "s": score])
        if let d = try? JSONSerialization.data(withJSONObject: items) { try? d.write(to: url, options: .atomic) }
    }
}

// MARK: - Historique d'activité

enum ActivityLog {
    private static var url: URL { FS.supportDir.appendingPathComponent("activite.json") }

    static func load() -> [(Date, String)] {
        guard let d = try? Data(contentsOf: url), let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return arr.compactMap { e in
            guard let t = e["d"] as? Double, let m = e["m"] as? String else { return nil }
            return (Date(timeIntervalSince1970: t), m)
        }.reversed()
    }

    static func add(_ message: String) {
        var items = Array(load().reversed().map { ["d": $0.0.timeIntervalSince1970, "m": $0.1] as [String: Any] }.suffix(199))
        items.append(["d": Date().timeIntervalSince1970, "m": message])
        if let d = try? JSONSerialization.data(withJSONObject: items) { try? d.write(to: url, options: .atomic) }
    }

    static func clear() { try? FS.fm.removeItem(at: url) }
}
