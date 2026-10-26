import SwiftUI
import AppKit

enum AppsTab: String, CaseIterable, Identifiable {
    case uninstall, menubar, updates, startup, extensions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .uninstall: return "Désinstaller"
        case .menubar: return "Près de l'horloge"
        case .updates: return "Mises à jour"
        case .startup: return "Démarrage"
        case .extensions: return "Extensions"
        }
    }
    var icon: String {
        switch self {
        case .uninstall: return "trash"
        case .menubar: return "menubar.rectangle"
        case .updates: return "arrow.down.circle"
        case .startup: return "power"
        case .extensions: return "puzzlepiece"
        }
    }
}

struct AppsView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    @State private var tab: AppsTab = .uninstall
    @State private var search = ""
    @State private var onlyUnused = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    SectionTitle(title: "Applications", subtitle: "Désinstallation complète, suppression forcée des logiciels récalcitrants, mises à jour, démarrage et extensions.")
                    Button(action: { model.loadApps() }) { Label("Actualiser", systemImage: "arrow.clockwise") }
                        .buttonStyle(GlassButtonStyle())
                }
                .appear(0)

                HStack(spacing: 8) {
                    ForEach(AppsTab.allCases) { t in
                        Button(action: { withAnimation(.spring()) { tab = t } }) {
                            HStack(spacing: 6) { Image(systemName: t.icon); Text(t.title) }
                                .font(.system(size: 12.5, weight: tab == t ? .bold : .medium, design: .rounded))
                                .foregroundColor(tab == t ? .white : p.text)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(ZStack {
                                    if tab == t { Capsule().fill(AnyShapeStyleFill.accent) } else { GlassBackground(radius: 16) }
                                })
                        }
                        .buttonStyle(PlainHover())
                    }
                    Spacer()
                }
                .appear(1)

                if model.appsLoading {
                    LoadingCard(text: "Inventaire des applications…")
                } else {
                    switch tab {
                    case .uninstall: uninstallTab
                    case .menubar: menubarTab
                    case .updates: updatesTab
                    case .startup: startupTab
                    case .extensions: extensionsTab
                    }
                }
            }
            .padding(26)
        }
        .onAppear { if model.apps.isEmpty && !model.appsLoading { model.loadApps() } }
    }

    // MARK: Désinstaller

    private var filtered: [AppItem] {
        let sixMonths = Date().addingTimeInterval(-180 * 86400)
        return model.apps.filter { a in
            (search.isEmpty || a.name.localizedCaseInsensitiveContains(search))
                && (!onlyUnused || (a.lastUsed ?? .distantPast) < sixMonths)
        }
    }

    private var uninstallTab: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(p.muted)
                    TextField("Rechercher une application", text: $search)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(GlassBackground(radius: 12))
                Toggle("Inutilisées depuis 6 mois", isOn: $onlyUnused)
                    .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
                    .font(.system(size: 12.5))
            }
            GlassCard(padding: 14, tint: Palette.accent) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundColor(Palette.accent)
                    Muted("« Désinstaller » supprime l'application et tous ses restes. « Forcer » ferme l'application, coupe ce qui la relance et supprime même les fichiers protégés (mot de passe administrateur demandé).")
                }
            }
            ForEach(Array(filtered.enumerated()), id: \.element.id) { i, a in
                AppRow(app: a,
                       uninstall: {
                           if Confirm.ask("Désinstaller \(a.name) ?", "L'application et ses fichiers seront supprimés.", ok: "Désinstaller", danger: true) {
                               model.uninstall(a, force: false)
                           }
                       },
                       force: {
                           if Confirm.ask("Suppression forcée de \(a.name) ?", "OptiMac va fermer l'application de force, retirer ce qui la relance et supprimer tous ses fichiers, même protégés.", ok: "Forcer la suppression", danger: true) {
                               model.uninstall(a, force: true)
                           }
                       })
                    .appear(min(i, 14))
            }
        }
    }

    // MARK: Barre des menus

    private var menubarTab: some View {
        VStack(spacing: 10) {
            GlassCard(tint: Palette.warning) {
                HStack(spacing: 12) {
                    IconBubble(symbol: "menubar.rectangle", color: Palette.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Strong("Logiciels affichés en haut de l'écran, près de l'horloge")
                        Muted("Certains refusent de se fermer ou de se désinstaller (faux antivirus, outils de prise en main à distance…). OptiMac peut les fermer et les supprimer de force.")
                    }
                }
            }
            if model.menuBarApps.isEmpty { GlassCard { Muted("Aucun logiciel tiers dans la barre des menus.") } }
            ForEach(model.menuBarApps) { m in
                GlassCard(padding: 12) {
                    HStack(spacing: 12) {
                        if let icon = m.icon { Image(nsImage: icon).resizable().frame(width: 32, height: 32) }
                        VStack(alignment: .leading, spacing: 2) {
                            Strong(m.name, size: 13.5)
                            Muted(m.url?.path ?? m.bundleID, size: 11).lineLimit(1)
                        }
                        Spacer()
                        Button("Quitter de force") {
                            PerformanceEngine.quit(m.pid, force: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { model.menuBarApps = AppsEngine.menuBarApps() }
                        }
                        .buttonStyle(GlassButtonStyle())
                        if !license.isPremium { PremiumTag() }
                        Button("Supprimer de force") {
                            if Confirm.ask("Supprimer \(m.name) de force ?", "Le logiciel sera fermé et supprimé avec tous ses fichiers, même protégés.", ok: "Supprimer", danger: true) {
                                model.forceRemoveMenuBar(m)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Mises à jour

    private var updatesTab: some View {
        let withUpdates = model.apps.filter { $0.update != nil }
        return VStack(spacing: 10) {
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Strong(model.updatesLoading ? "Recherche des mises à jour…" : (withUpdates.isEmpty ? "Vos applications sont à jour" : "\(withUpdates.count) mise(s) à jour disponible(s)"))
                        Muted("App Store et applications avec mise à jour intégrée.")
                    }
                    Spacer()
                    if model.updatesLoading { Spinner() } else {
                        Button("Rechercher") { model.checkUpdates() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            HStack {
                Button("Mettre à jour macOS") {
                    Links.open(URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!)
                }
                .buttonStyle(GlassButtonStyle())
                Spacer()
            }
            ForEach(withUpdates) { a in
                GlassCard(padding: 12) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Strong(a.name, size: 13.5)
                            Muted("\(a.version) → \(a.update ?? "")", size: 11.5)
                        }
                        Spacer()
                        Button("Mettre à jour") {
                            if let l = a.updateLink { Links.open(l) } else { NSWorkspace.shared.open(a.url) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Démarrage

    private var startupTab: some View {
        VStack(spacing: 8) {
            GlassCard(padding: 14, tint: Palette.blue) {
                Muted("Désactiver un élément ne supprime pas le logiciel : il ne se lance simplement plus tout seul. Vous pouvez le réactiver à tout moment.")
            }
            ForEach(model.startup) { s in
                GlassCard(padding: 12) {
                    HStack(spacing: 12) {
                        IconBubble(symbol: s.kind == .loginItem ? "person.crop.circle" : (s.kind == .daemon ? "gearshape.2" : "bolt.horizontal"),
                                   color: s.useless ? Palette.warning : Palette.blue, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Strong(s.name, size: 13.5)
                                if s.useless && s.enabled { Tag(text: "Souvent inutile", color: Palette.warning) }
                            }
                            Muted(s.detail, size: 11).lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { s.enabled }, set: { _ in model.toggleStartup(s) }))
                            .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
                            .labelsHidden()
                    }
                }
            }
            if model.startup.isEmpty { GlassCard { Muted("Aucun élément au démarrage.") } }
        }
    }

    // MARK: Extensions

    private var extensionsTab: some View {
        VStack(spacing: 8) {
            if model.extensions.isEmpty { GlassCard { Muted("Aucune extension trouvée.") } }
            ForEach(model.extensions) { e in
                GlassCard(padding: 12) {
                    HStack(spacing: 12) {
                        IconBubble(symbol: "puzzlepiece.fill", color: Palette.purple, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Strong(e.name, size: 13.5)
                            Muted(e.browser, size: 11.5)
                        }
                        Spacer()
                        Button("Supprimer") {
                            if Confirm.ask("Supprimer l'extension \(e.name) ?", "Elle sera retirée de \(e.browser).", ok: "Supprimer", danger: true) {
                                model.removeExtension(e)
                            }
                        }
                        .buttonStyle(GlassButtonStyle(danger: true))
                    }
                }
            }
        }
    }
}

struct AppRow: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    let app: AppItem
    let uninstall: () -> Void
    let force: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Strong(app.name, size: 13.5)
                    if app.runningInMenuBar { Tag(text: "Barre des menus", color: Palette.warning) }
                    if app.isAppStore { Tag(text: "App Store", color: Palette.blue) }
                }
                Muted("Version \(app.version.isEmpty ? "—" : app.version) · \(Fmt.ago(app.lastUsed))", size: 11.5)
            }
            Spacer()
            Text(Fmt.bytes(app.size)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(p.text)
            Button("Désinstaller", action: uninstall).buttonStyle(GlassButtonStyle())
            Button(action: force) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                    Text("Forcer")
                }
            }
            .buttonStyle(GlassButtonStyle(danger: true))
            .help(license.isPremium ? "Suppression forcée" : "Suppression forcée (Premium)")
        }
        .padding(12)
        .background(GlassBackground(radius: 16, tint: hover ? Palette.accent : nil))
        .onHover { hover = $0 }
    }
}
