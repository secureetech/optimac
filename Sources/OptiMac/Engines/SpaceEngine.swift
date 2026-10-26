import Foundation
import CryptoKit

struct FileEntry: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let accessed: Date?
    let modified: Date?
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path.replacingOccurrences(of: FS.home.path, with: "~") }
}

struct DuplicateGroup: Identifiable {
    let id: String
    let files: [FileEntry]
    var wasted: Int64 { files.dropFirst().reduce(0) { $0 + $1.size } }
}

struct MapBlock: Identifiable {
    let id: String
    let name: String
    let size: Int64
    let url: URL?
}

struct CloudFolder: Identifiable {
    let id: String
    let name: String
    let url: URL
    let localSize: Int64
}

struct SpaceReport {
    var map: [MapBlock] = []
    var large: [FileEntry] = []
    var old: [FileEntry] = []
    var duplicates: [DuplicateGroup] = []
    var photoDuplicates: [DuplicateGroup] = []
    var emptyFolders: [URL] = []
    var cloud: [CloudFolder] = []
}

/// Espace disque : carte, gros fichiers, fichiers anciens, doublons, photos, dossiers vides, cloud.
enum SpaceEngine {
    static let imageExt: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "raw", "cr2", "nef", "arw", "dng", "webp"]

    static func scan(progress: @escaping (String) -> Void) -> SpaceReport {
        var r = SpaceReport()
        let home = FS.home
        let vol = FS.volume()

        // 1. Carte du disque
        progress("Mesure des dossiers…")
        let tops: [(String, URL)] = [
            ("Photos et images", home.appendingPathComponent("Pictures")),
            ("Documents", home.appendingPathComponent("Documents")),
            ("Bureau", home.appendingPathComponent("Desktop")),
            ("Téléchargements", home.appendingPathComponent("Downloads")),
            ("Vidéos", home.appendingPathComponent("Movies")),
            ("Musique", home.appendingPathComponent("Music")),
            ("Applications", URL(fileURLWithPath: "/Applications")),
            ("Bibliothèque (données des applis)", home.appendingPathComponent("Library"))
        ]
        var sum: Int64 = 0
        for (name, url) in tops where FS.exists(url) {
            let s = FS.size(of: url)
            sum += s
            r.map.append(MapBlock(id: name, name: name, size: s, url: url))
        }
        let used = vol.total - vol.free
        if used > sum { r.map.append(MapBlock(id: "system", name: "Système et autres", size: used - sum, url: nil)) }
        r.map.sort { $0.size > $1.size }

        // 2. Parcours des fichiers personnels
        progress("Recherche des gros fichiers et des doublons…")
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isPackageKey]
        var all: [FileEntry] = []
        let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0) }
        for root in roots where FS.exists(root) {
            guard let en = FS.fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                            errorHandler: { _, _ in true }) else { continue }
            for case let f as URL in en {
                guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                let size = Int64(v.fileSize ?? 0)
                if size < 1_000_000 { continue }
                all.append(FileEntry(url: f, size: size, accessed: v.contentAccessDate, modified: v.contentModificationDate))
            }
        }
        r.large = all.filter { $0.size >= 50_000_000 }.sorted { $0.size > $1.size }.prefix(400).map { $0 }
        let yearAgo = Date().addingTimeInterval(-365 * 86400)
        r.old = all.filter { $0.size >= 10_000_000 && ($0.accessed ?? $0.modified ?? Date()) < yearAgo }
            .sorted { $0.size > $1.size }.prefix(400).map { $0 }

        // 3. Doublons (même taille, puis même empreinte)
        progress("Comparaison des fichiers en double…")
        let groups = Dictionary(grouping: all, by: { $0.size }).values.filter { $0.count > 1 }
        var dups: [DuplicateGroup] = []
        for g in groups {
            var byHash: [String: [FileEntry]] = [:]
            for f in g { if let h = hash(f.url) { byHash[h, default: []].append(f) } }
            for (h, files) in byHash where files.count > 1 {
                let sorted = files.sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
                dups.append(DuplicateGroup(id: h, files: sorted))
            }
        }
        dups.sort { $0.wasted > $1.wasted }
        r.photoDuplicates = dups.filter { imageExt.contains($0.files[0].url.pathExtension.lowercased()) }
        r.duplicates = dups.filter { !imageExt.contains($0.files[0].url.pathExtension.lowercased()) }

        // 4. Dossiers vides
        progress("Recherche des dossiers vides…")
        for root in ["Desktop", "Documents", "Downloads"].map({ home.appendingPathComponent($0) }) {
            guard let en = FS.fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let d as URL in en {
                guard (try? d.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let content = FS.children(d).filter { $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized" }
                if content.isEmpty { r.emptyFolders.append(d) }
                if r.emptyFolders.count > 500 { break }
            }
        }

        // 5. Cloud
        progress("Analyse des dossiers iCloud, Google Drive et OneDrive…")
        let icloud = FS.lib("Mobile Documents/com~apple~CloudDocs")
        if FS.exists(icloud) { r.cloud.append(CloudFolder(id: "icloud", name: "iCloud Drive", url: icloud, localSize: FS.size(of: icloud))) }
        for d in FS.children(FS.lib("CloudStorage")) where FS.isDir(d) {
            let n = d.lastPathComponent
            let label = n.hasPrefix("GoogleDrive") ? "Google Drive" : n.hasPrefix("OneDrive") ? "OneDrive" : n.hasPrefix("Dropbox") ? "Dropbox" : n
            r.cloud.append(CloudFolder(id: n, name: label, url: d, localSize: FS.size(of: d)))
        }
        return r
    }

    private static func hash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let chunk = h.readData(ofLength: 4 * 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Libère la copie locale des fichiers déjà enregistrés dans le cloud.
    static func freeCloud(_ folder: CloudFolder) -> Int64 {
        var freed: Int64 = 0
        guard let en = FS.fm.enumerator(at: folder.url, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey],
                                        options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return 0 }
        for case let f as URL in en {
            guard let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]), v.isRegularFile == true else { continue }
            let s = Int64(v.totalFileAllocatedSize ?? 0)
            if s > 0, (try? FS.fm.evictUbiquitousItem(at: f)) != nil { freed += s }
        }
        return freed
    }
}
