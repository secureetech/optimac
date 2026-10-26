import SwiftUI
import AppKit

// MARK: - Nettoyage

struct CleanView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p

    var selectedSize: Int64 { model.cleanup.filter(\.selected).reduce(0) { $0 + $1.size } }
    var total: Int64 { model.cleanup.reduce(0) { $0 + $1.size } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    SectionTitle(title: "Nettoyage", subtitle: "Caches, journaux, fichiers temporaires, corbeille, pièces jointes Mail, sauvegardes iPhone…")
                    Button(action: { model.loadCleanup() }) { Label("Analyser", systemImage: "arrow.clockwise") }
                        .buttonStyle(GlassButtonStyle())
                }
                .appear(0)

                if model.cleanupLoading {
                    LoadingCard(text: "Recherche des fichiers inutiles…")
                } else if model.cleanup.isEmpty {
                    GlassCard {
                        HStack(spacing: 14) {
                            IconBubble(symbol: "sparkles")
                            VStack(alignment: .leading, spacing: 3) {
                                Strong("Lancez l'analyse pour trouver les fichiers inutiles")
                                Muted("OptiMac ne touche jamais à vos documents, photos ou mots de passe.")
                            }
                            Spacer()
                            Button("Analyser") { model.loadCleanup() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .appear(1)
                } else {
                    GlassCard(tint: Palette.accent) {
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 4) {
                                Muted("Sélection à nettoyer")
                                Text(Fmt.bytes(selectedSize)).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                                Muted("sur \(Fmt.bytes(total)) trouvés")
                            }
                            Spacer()
                            Button(action: { model.cleanSelected() }) {
                                Label("Nettoyer", systemImage: "trash")
                            }
                            .buttonStyle(PrimaryButtonStyle(large: true))
                            .disabled(selectedSize == 0)
                        }
                    }
                    .appear(1)

                    if !license.isPremium {
                        PremiumBanner(text: "Version gratuite : 500 Mo maximum par nettoyage. Premium nettoie tout, et automatiquement si vous le souhaitez.",
                                      feature: .unlimitedCleanup)
                    }

                    VStack(spacing: 8) {
                        ForEach(Array(model.cleanup.enumerated()), id: \.element.id) { i, c in
                            CleanRow(cat: c) { model.cleanup[i].selected.toggle() }
                                .appear(i + 2)
                        }
                    }

                    HStack {
                        Button("Vider la corbeille") {
                            if Confirm.ask("Vider la corbeille ?", "Les fichiers de la corbeille seront supprimés définitivement.", ok: "Vider", danger: true) {
                                model.emptyTrash()
                            }
                        }
                        .buttonStyle(GlassButtonStyle())
                        Spacer()
                        Muted("Une copie de sécurité est faite avant chaque nettoyage important.")
                    }
                }
            }
            .padding(26)
        }
        .onAppear { if model.cleanup.isEmpty && !model.cleanupLoading { model.loadCleanup() } }
    }
}

struct CleanRow: View {
    @Environment(\.palette) private var p
    let cat: CleanCategory
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                CheckCircle(on: cat.selected)
                IconBubble(symbol: cat.icon, color: cat.safe ? Palette.accent : Palette.warning, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Strong(cat.name)
                        if !cat.safe { Tag(text: "À vérifier", color: Palette.warning) }
                    }
                    Muted(cat.detail, size: 11.5).lineLimit(1)
                }
                Spacer()
                Text(Fmt.bytes(cat.size)).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(p.text)
            }
            .padding(12)
            .background(GlassBackground(radius: 16))
        }
        .buttonStyle(PlainHover())
    }
}

// MARK: - Espace disque

enum SpaceTab: String, CaseIterable, Identifiable {
    case map, large, duplicates, photos, old, empty, cloud
    var id: String { rawValue }
    var title: String {
        switch self {
        case .map: return "Carte"
        case .large: return "Gros fichiers"
        case .duplicates: return "Doublons"
        case .photos: return "Photos similaires"
        case .old: return "Peu utilisés"
        case .empty: return "Dossiers vides"
        case .cloud: return "iCloud & cloud"
        }
    }
}

struct SpaceView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var monitor: Monitor
    @Environment(\.palette) private var p
    @State private var tab: SpaceTab = .map
    @State private var picked = Set<String>()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    SectionTitle(title: "Espace disque", subtitle: "Ce qui prend de la place sur votre Mac, et ce que vous pouvez supprimer sans risque.")
                    Button(action: { model.loadSpace() }) { Label("Analyser", systemImage: "arrow.clockwise") }
                        .buttonStyle(GlassButtonStyle())
                }
                .appear(0)

                GlassCard {
                    HStack(spacing: 20) {
                        ZStack {
                            Ring(value: monitor.diskUsedRatio, color: monitor.diskUsedRatio > 0.85 ? Palette.danger : Palette.accent, width: 11)
                                .frame(width: 92, height: 92)
                            Text(Fmt.percent(monitor.diskUsedRatio)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(Fmt.bytes(monitor.freeSpace)) libres").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                            Muted("sur \(Fmt.bytes(monitor.totalSpace)) au total")
                            if monitor.diskUsedRatio > 0.85 {
                                Tag(text: "Disque presque plein : le Mac ralentit", color: Palette.danger)
                            }
                        }
                        Spacer()
                    }
                }
                .appear(1)

                if model.spaceLoading {
                    LoadingCard(text: model.spaceLabel.isEmpty ? "Analyse de votre disque…" : model.spaceLabel)
                } else if let r = model.space {
                    tabs
                    content(r)
                } else {
                    GlassCard {
                        HStack {
                            Muted("Analysez votre disque pour trouver les gros fichiers, les doublons et les photos similaires.")
                            Spacer()
                            Button("Analyser") { model.loadSpace() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(26)
        }
        .onAppear { if model.space == nil && !model.spaceLoading { model.loadSpace() } }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SpaceTab.allCases) { t in
                    Button(action: { withAnimation(.spring()) { tab = t; picked = [] } }) {
                        Text(t.title)
                            .font(.system(size: 12.5, weight: tab == t ? .bold : .medium, design: .rounded))
                            .foregroundColor(tab == t ? .white : p.text)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                ZStack {
                                    if tab == t { Capsule().fill(AnyShapeStyleFill.accent) }
                                    else { GlassBackground(radius: 16) }
                                }
                            )
                    }
                    .buttonStyle(PlainHover())
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private func content(_ r: SpaceReport) -> some View {
        switch tab {
        case .map: map(r)
        case .large: fileList(r.large, emptyText: "Aucun fichier de plus de 100 Mo.")
        case .old: fileList(r.old, emptyText: "Aucun gros fichier oublié depuis plus d'un an.")
        case .duplicates: dupList(r.duplicates, emptyText: "Aucun doublon trouvé.")
        case .photos: dupList(r.photoDuplicates, emptyText: "Aucune photo en double.")
        case .empty: emptyFolders(r.emptyFolders)
        case .cloud: cloud(r.cloud)
        }
    }

    private func map(_ r: SpaceReport) -> some View {
        let total = max(1, r.map.reduce(0) { $0 + $1.size })
        let colors = [Palette.accent, Palette.blue, Palette.success, Palette.purple, Color(hex: 0xEC4899), Color(hex: 0x14B8A6), Palette.warning, Color(hex: 0x64748B), Color(hex: 0xA3A3A3)]
        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(r.map.enumerated()), id: \.element.id) { i, b in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(colors[i % colors.count])
                                .frame(width: max(3, (g.size.width - CGFloat(r.map.count) * 2) * CGFloat(Double(b.size) / Double(total))))
                        }
                    }
                }
                .frame(height: 30)
                ForEach(Array(r.map.enumerated()), id: \.element.id) { i, b in
                    HStack(spacing: 10) {
                        Circle().fill(colors[i % colors.count]).frame(width: 10, height: 10)
                        Text(b.name).font(.system(size: 13, weight: .medium)).foregroundColor(p.text)
                        Spacer()
                        Text(Fmt.bytes(b.size)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(p.text)
                        if let u = b.url {
                            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([u]) }) {
                                Image(systemName: "magnifyingglass").foregroundColor(p.muted)
                            }
                            .buttonStyle(PlainHover())
                            .help("Afficher dans le Finder")
                        }
                    }
                }
            }
        }
    }

    private func fileList(_ files: [FileEntry], emptyText: String) -> some View {
        let visible = PremiumRules.visibleCount(files.count, premium: license.isPremium)
        let hidden = files.count - visible
        return VStack(spacing: 8) {
            if files.isEmpty {
                GlassCard { Muted(emptyText) }
            }
            ForEach(Array(files.prefix(visible).enumerated()), id: \.element.id) { i, f in
                FilePickRow(name: f.name, detail: "\(f.folder) · \(Fmt.ago(f.accessed))", size: f.size, url: f.url,
                            on: picked.contains(f.id)) { toggle(f.id) }
                    .appear(min(i, 12))
            }
            if hidden > 0 { lockedRows(hidden, size: files.dropFirst(visible).reduce(0) { $0 + $1.size }) }
            actionBar(urls: files.filter { picked.contains($0.id) }.map(\.url))
        }
    }

    private func dupList(_ groups: [DuplicateGroup], emptyText: String) -> some View {
        let visible = PremiumRules.visibleCount(groups.count, premium: license.isPremium)
        let hidden = groups.count - visible
        return VStack(spacing: 8) {
            if groups.isEmpty { GlassCard { Muted(emptyText) } }
            ForEach(Array(groups.prefix(visible).enumerated()), id: \.element.id) { i, g in
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Strong(g.files.first?.name ?? "")
                            Spacer()
                            Tag(text: "\(g.files.count) copies · \(Fmt.bytes(g.wasted)) perdus")
                        }
                        ForEach(Array(g.files.enumerated()), id: \.element.id) { j, f in
                            Button(action: { if j > 0 { toggle(f.id) } }) {
                                HStack(spacing: 8) {
                                    if j == 0 {
                                        Tag(text: "Original gardé", color: Palette.success)
                                    } else {
                                        CheckCircle(on: picked.contains(f.id))
                                    }
                                    Muted(f.folder, size: 11.5).lineLimit(1)
                                    Spacer()
                                    Muted(Fmt.date(f.modified), size: 11)
                                }
                            }
                            .buttonStyle(PlainHover())
                        }
                    }
                }
                .appear(min(i, 10))
            }
            if hidden > 0 { lockedRows(hidden, size: groups.dropFirst(visible).reduce(0) { $0 + $1.wasted }) }
            HStack {
                Button("Sélectionner toutes les copies") {
                    for g in groups.prefix(visible) { g.files.dropFirst().forEach { picked.insert($0.id) } }
                }
                .buttonStyle(GlassButtonStyle())
                Spacer()
            }
            actionBar(urls: groups.flatMap { $0.files }.filter { picked.contains($0.id) }.map(\.url))
        }
    }

    private func emptyFolders(_ urls: [URL]) -> some View {
        VStack(spacing: 8) {
            if urls.isEmpty { GlassCard { Muted("Aucun dossier vide.") } }
            ForEach(urls.prefix(200), id: \.path) { u in
                FilePickRow(name: u.lastPathComponent, detail: u.deletingLastPathComponent().path.replacingOccurrences(of: FS.home.path, with: "~"),
                            size: 0, url: u, on: picked.contains(u.path)) { toggle(u.path) }
            }
            actionBar(urls: urls.filter { picked.contains($0.path) })
        }
    }

    private func cloud(_ folders: [CloudFolder]) -> some View {
        VStack(spacing: 8) {
            GlassCard(tint: Palette.blue) {
                Muted("Libérer l'espace garde vos fichiers en sécurité dans iCloud, Google Drive, OneDrive ou Dropbox : ils sont simplement retirés du Mac et se re-téléchargent quand vous les ouvrez.")
            }
            if folders.isEmpty { GlassCard { Muted("Aucun dossier cloud synchronisé sur ce Mac.") } }
            ForEach(folders) { f in
                GlassCard(padding: 14) {
                    HStack(spacing: 12) {
                        IconBubble(symbol: "icloud", color: Palette.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Strong(f.name)
                            Muted("\(Fmt.bytes(f.localSize)) téléchargés sur ce Mac")
                        }
                        Spacer()
                        if !license.isPremium { PremiumTag() }
                        Button("Libérer l'espace") { model.freeCloud(f) }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private func lockedRows(_ n: Int, size: Int64) -> some View {
        ZStack {
            VStack(spacing: 8) {
                ForEach(0..<min(3, n), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16).fill(p.subtle).frame(height: 54)
                }
            }
            .blur(radius: 4)
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 22)).foregroundColor(Palette.accent)
                Text("\(n) autre(s) élément(s) · \(Fmt.bytes(size))").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(p.text)
                Muted("La version gratuite affiche 20 % des résultats.")
                Button("Tout voir avec Premium") {
                    model.premiumFeature = .fullSpaceResults
                    model.showPremium = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func actionBar(urls: [URL]) -> some View {
        HStack {
            Muted(urls.isEmpty ? "Cochez les fichiers à supprimer." : "\(urls.count) élément(s) · \(Fmt.bytes(FS.size(of: urls)))")
            Spacer()
            Button(action: {
                if Confirm.ask("Mettre à la corbeille ?", "\(urls.count) élément(s) seront déplacés dans la corbeille. Vous pourrez encore les récupérer.", ok: "Mettre à la corbeille") {
                    model.trashFiles(urls)
                    picked = []
                }
            }) { Label("Supprimer la sélection", systemImage: "trash") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(urls.isEmpty)
            .opacity(urls.isEmpty ? 0.5 : 1)
        }
        .padding(.top, 6)
    }
}

struct FilePickRow: View {
    @Environment(\.palette) private var p
    let name: String
    let detail: String
    let size: Int64
    let url: URL
    let on: Bool
    let toggle: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    CheckCircle(on: on)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Strong(name, size: 13)
                        Muted(detail, size: 11).lineLimit(1)
                    }
                    Spacer()
                    if size > 0 {
                        Text(Fmt.bytes(size)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(p.text)
                    }
                }
            }
            .buttonStyle(PlainHover())
            Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                Image(systemName: "magnifyingglass").foregroundColor(p.muted)
            }
            .buttonStyle(PlainHover())
            .help("Afficher dans le Finder")
        }
        .padding(11)
        .background(GlassBackground(radius: 16))
    }
}
