import Foundation

/// Outils fichiers : tailles, listes, suppressions.
enum FS {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }
    static func lib(_ path: String) -> URL { home.appendingPathComponent("Library").appendingPathComponent(path) }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDir(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    static func children(_ url: URL, includeHidden: Bool = true) -> [URL] {
        let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: opts)) ?? []
    }

    /// Taille réellement occupée sur le disque (dossier ou fichier), en octets.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey]
        if let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func size(of urls: [URL]) -> Int64 { urls.reduce(0) { $0 + size(of: $1) } }

    /// Supprime définitivement. Renvoie la place libérée.
    @discardableResult
    static func remove(_ url: URL) -> Int64 {
        let s = size(of: url)
        do { try fm.removeItem(at: url); return s } catch { return 0 }
    }

    /// Vide un dossier sans supprimer le dossier lui-même.
    @discardableResult
    static func removeContents(of url: URL) -> Int64 {
        children(url).reduce(Int64(0)) { $0 + remove($1) }
    }

    /// Met à la corbeille (récupérable).
    @discardableResult
    static func trash(_ url: URL) -> Bool {
        do { try fm.trashItem(at: url, resultingItemURL: nil); return true } catch { return false }
    }

    static func ensureDir(_ url: URL) {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static var supportDir: URL {
        let u = lib("Application Support/OptiMac")
        ensureDir(u)
        return u
    }

    static func modDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func accessDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
    }

    /// Volume principal : capacité totale et espace libre.
    static func volume() -> (total: Int64, free: Int64) {
        let u = URL(fileURLWithPath: "/")
        let v = try? u.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let free = v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
        return (total, free)
    }

    /// Chemins jamais supprimables, quelle que soit la demande.
    static func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let forbidden = ["/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private", "/etc", "/var", "/Volumes", home.path,
                         home.appendingPathComponent("Library").path, home.appendingPathComponent("Documents").path,
                         home.appendingPathComponent("Desktop").path, home.appendingPathComponent("Downloads").path,
                         home.appendingPathComponent("Pictures").path]
        if forbidden.contains(p) { return true }
        if p.hasPrefix("/System/") || p.hasPrefix("/usr/") || p.hasPrefix("/bin/") || p.hasPrefix("/sbin/") { return true }
        return false
    }
}

/// Affichage des tailles et nombres en français (« 6,4 Go »).
enum Fmt {
    private static let nf: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f
    }()

    static func bytes(_ b: Int64) -> String {
        let units = ["octets", "Ko", "Mo", "Go", "To"]
        var v = Double(max(b, 0))
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        if i == 0 { return "\(Int(v)) octets" }
        nf.maximumFractionDigits = v < 10 ? 1 : 0
        return "\(nf.string(from: NSNumber(value: v)) ?? "\(v)") \(units[i])"
    }

    static func number(_ n: Int) -> String {
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func percent(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }

    static func date(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    static func dateTime(_ d: Date?) -> String {
        guard let d else { return "jamais" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func ago(_ d: Date?) -> String {
        guard let d else { return "jamais ouvert" }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        if days < 1 { return "aujourd'hui" }
        if days < 31 { return "il y a \(days) jour\(days > 1 ? "s" : "")" }
        if days < 365 { return "il y a \(days / 30) mois" }
        let y = days / 365
        return "il y a \(y) an\(y > 1 ? "s" : "")"
    }
}

/// Journal d'erreurs local : ~/Library/Logs/OptiMac/erreurs.log
enum ErrorLog {
    private static let queue = DispatchQueue(label: "optimac.errorlog")
    static func write(_ message: String) {
        ErrorReport.send(message)
        queue.async {
            let dir = FS.lib("Logs/OptiMac")
            FS.ensureDir(dir)
            let url = dir.appendingPathComponent("erreurs.log")
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
