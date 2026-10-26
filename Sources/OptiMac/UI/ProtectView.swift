import SwiftUI

enum ProtectTab: String, CaseIterable, Identifiable {
    case threats, browsers, security, privacy, quarantine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .threats: return "Anti-malware"
        case .browsers: return "Navigateurs"
        case .security: return "Sécurité de macOS"
        case .privacy: return "Vie privée"
        case .quarantine: return "Quarantaine"
        }
    }
    var icon: String {
        switch self {
        case .threats: return "ant"
        case .browsers: return "globe"
        case .security: return "lock.shield"
        case .privacy: return "eye.slash"
        case .quarantine: return "archivebox"
        }
    }
}

struct ProtectView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    @State private var tab: ProtectTab = .threats

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionTitle(title: "Protection", subtitle: "Malwares et adwares Mac, faux optimiseurs, navigateurs détournés, prise en main à distance et vie privée.")
                    .appear(0)
                HStack(spacing: 8) {
                    ForEach(ProtectTab.allCases) { t in
                        Button(action: { withAnimation(.spring()) { tab = t } }) {
                            HStack(spacing: 6) {
                                Image(systemName: t.icon)
                                Text(t.title)
                                if t == .threats && model.dangerCount > 0 { Text("\(model.dangerCount)").bold() }
                                if t == .browsers && model.hijackedCount > 0 { Text("\(model.hijackedCount)").bold() }
                            }
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

                switch tab {
                case .threats: threatsTab
                case .browsers: browsersTab
                case .security: securityTab
                case .privacy: privacyTab
                case .quarantine: quarantineTab
                }
            }
            .padding(26)
        }
        .onAppear {
            if model.browsers.isEmpty { model.loadBrowsers() }
            if model.security == nil { model.loadSecurity() }
        }
    }

    // MARK: Anti-malware

    private var threatsTab: some View {
        VStack(spacing: 12) {
            GlassCard(tint: model.dangerCount > 0 ? Palette.danger : Palette.success) {
                HStack(spacing: 16) {
                    IconBubble(symbol: model.dangerCount > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill",
                               color: model.dangerCount > 0 ? Palette.danger : Palette.success, size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.lastThreatScan == nil ? "Jamais analysé" : (model.dangerCount > 0 ? "\(model.dangerCount) menace(s) détectée(s)" : "Aucune menace"))
                            .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        Muted(model.lastThreatScan == nil ? "Lancez une analyse pour vérifier votre Mac." : "Dernière analyse : \(Fmt.dateTime(model.lastThreatScan))")
                    }
                    Spacer()
                    if model.threatLoading {
                        Button(action: { model.stopScan() }) { Label("Arrêter", systemImage: "stop.fill") }
                            .buttonStyle(GlassButtonStyle(danger: true))
                    } else {
                        Button("Analyse rapide") { model.scanThreats(full: false) }.buttonStyle(GlassButtonStyle())
                        Button("Analyse complète") { model.scanThreats(full: true) }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            if model.threatLoading {
                LoadingCard(text: model.threatStep.isEmpty ? "Analyse…" : model.threatStep, progress: model.threatProgress)
            }
            if !model.threats.isEmpty {
                HStack(spacing: 8) {
                    Button(model.selectedThreats.count == model.threats.count ? "Tout désélectionner" : "Tout sélectionner") {
                        if model.selectedThreats.count == model.threats.count { model.selectedThreats = [] }
                        else { model.selectedThreats = Set(model.threats.map(\.id)) }
                    }
                    .buttonStyle(GlassButtonStyle())
                    Button("Ignorer tout") { model.ignoreThreats(all: true) }.buttonStyle(GlassButtonStyle())
                    Button("Ignorer la sélection") { model.ignoreThreats(all: false) }.buttonStyle(GlassButtonStyle())
                        .disabled(model.selectedThreats.isEmpty)
                    Spacer()
                    Button("Mettre en quarantaine") { model.removeThreats(quarantine: true) }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(model.selectedThreats.isEmpty)
                    Button(action: {
                        if Confirm.ask("Supprimer la sélection ?", "Les éléments sélectionnés seront supprimés définitivement.", ok: "Supprimer", danger: true) {
                            model.removeThreats(quarantine: false)
                        }
                    }) { Label("Supprimer la sélection", systemImage: "trash") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.selectedThreats.isEmpty)
                }
                if !license.isPremium {
                    PremiumBanner(text: "La version gratuite détecte les menaces. La suppression et la quarantaine sont réservées à Premium.", feature: .threatRemoval)
                }
                ForEach(Array(model.threats.enumerated()), id: \.element.id) { i, t in
                    ThreatRow(threat: t, on: model.selectedThreats.contains(t.id)) {
                        if model.selectedThreats.contains(t.id) { model.selectedThreats.remove(t.id) } else { model.selectedThreats.insert(t.id) }
                    }
                    .appear(min(i, 12))
                }
            }
            GlassCard {
                HStack(spacing: 12) {
                    IconBubble(symbol: "calendar.badge.clock", color: Palette.blue, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Strong("Vérification automatique chaque semaine", size: 13)
                        Muted("Analyse rapide en arrière-plan, sans rien supprimer automatiquement.", size: 11.5)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.settings.weeklyCheck }, set: { model.settings.weeklyCheck = $0 }))
                        .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: Navigateurs détournés

    private var browsersTab: some View {
        VStack(spacing: 12) {
            GlassCard(tint: model.hijackedCount > 0 ? Palette.danger : nil) {
                HStack(spacing: 14) {
                    IconBubble(symbol: "globe", color: model.hijackedCount > 0 ? Palette.danger : Palette.success, size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.hijackedCount > 0 ? "\(model.hijackedCount) navigateur(s) détourné(s)" : "Navigateurs en bon état")
                            .font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        Muted("Page d'accueil, moteur de recherche, sites au démarrage et réglages « Géré par votre organisation ». Vos favoris et mots de passe ne sont jamais touchés.")
                    }
                    Spacer()
                    Button("Vérifier") { model.loadBrowsers() }.buttonStyle(GlassButtonStyle())
                    if model.hijackedCount > 0 {
                        HStack(spacing: 6) {
                            if !license.isPremium { PremiumTag() }
                            Button("Réparer en un clic") { model.repairBrowsers() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
            ForEach(model.browsers.filter(\.installed)) { b in
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: b.hijacked ? "xmark.octagon.fill" : "checkmark.seal.fill")
                                .foregroundColor(b.hijacked ? Palette.danger : Palette.success)
                                .font(.system(size: 18))
                            Strong(b.name)
                            Spacer()
                            Tag(text: b.hijacked ? "Détourné" : "OK", color: b.hijacked ? Palette.danger : Palette.success)
                        }
                        ForEach(b.issues, id: \.self) { i in
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundColor(p.muted)
                                Muted(i, size: 12)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Sécurité de macOS

    private var securityTab: some View {
        VStack(spacing: 12) {
            if let s = model.security {
                GlassCard {
                    HStack(spacing: 18) {
                        ZStack {
                            Ring(value: Double(s.score) / 100, color: s.score >= 80 ? Palette.success : Palette.warning, width: 10).frame(width: 80, height: 80)
                            Text("\(s.score)").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Niveau de sécurité").font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                            Muted("Les protections intégrées à macOS, vérifiées une par une.")
                        }
                        Spacer()
                    }
                }
                SecurityRow(title: "Pare-feu", detail: "Bloque les connexions entrantes non autorisées.", ok: s.firewall, action: s.firewall ? nil : ("Activer", { model.enableFirewall() }))
                SecurityRow(title: "Gatekeeper", detail: "N'autorise que les applications vérifiées.", ok: s.gatekeeper, action: s.gatekeeper ? nil : ("Réactiver", {
                    Task { _ = await background { SecurityEngine.enableGatekeeper() }; model.loadSecurity() }
                }))
                SecurityRow(title: "FileVault", detail: "Chiffre le disque si le Mac est volé.", ok: s.fileVault, action: s.fileVault ? nil : ("Ouvrir", { SecurityEngine.openFileVault() }))
                SecurityRow(title: "Protection de l'intégrité du système", detail: "Empêche la modification de macOS.", ok: s.sip, action: nil)
                SecurityRow(title: "Mises à jour automatiques", detail: "macOS se protège contre les nouvelles failles.", ok: s.autoUpdates,
                            action: s.autoUpdates ? nil : ("Ouvrir", { Links.open(URL(string: "x-apple.systempreferences:com.apple.preferences.softwareupdate")!) }))
            } else {
                LoadingCard(text: "Vérification de la sécurité…")
            }
        }
    }

    // MARK: Vie privée

    private var privacyTab: some View {
        VStack(spacing: 12) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Strong("Traces de navigation")
                        Spacer()
                        if !license.isPremium { PremiumTag() }
                        Button("Effacer la sélection") { model.cleanPrivacy() }.buttonStyle(PrimaryButtonStyle())
                    }
                    if model.privacy.isEmpty { Muted("Aucune trace trouvée (ou l'Accès complet au disque n'est pas encore autorisé).") }
                    ForEach(Array(model.privacy.enumerated()), id: \.element.id) { i, item in
                        Button(action: { model.privacy[i].selected.toggle() }) {
                            HStack(spacing: 10) {
                                CheckCircle(on: item.selected)
                                VStack(alignment: .leading, spacing: 1) {
                                    Strong(item.name, size: 13)
                                    Muted(item.detail, size: 11.5)
                                }
                                Spacer()
                                Muted("\(Fmt.number(item.count)) élément(s)")
                            }
                        }
                        .buttonStyle(PlainHover())
                    }
                }
            }
            HStack(spacing: 12) {
                accessCard(title: "Accès à la caméra", icon: "video.fill", apps: model.cameraApps, anchor: "Privacy_Camera")
                accessCard(title: "Accès au micro", icon: "mic.fill", apps: model.micApps, anchor: "Privacy_Microphone")
            }
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Strong("Partage d'analyses avec Apple", size: 13)
                        Muted("Envoie des rapports d'utilisation de votre Mac.", size: 11.5)
                    }
                    Spacer()
                    Button("Désactiver") {
                        Task { let ok = await background { SecurityEngine.disableAnalyticsSharing() }; if ok { model.notify("Partage d'analyses désactivé") } }
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
    }

    private func accessCard(title: String, icon: String, apps: [String], anchor: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconBubble(symbol: icon, color: Palette.purple, size: 30)
                    Strong(title, size: 13)
                    Spacer()
                    Button("Gérer") { SecurityEngine.openPrivacy(anchor) }.buttonStyle(GlassButtonStyle())
                }
                if apps.isEmpty { Muted("Aucune application.", size: 11.5) }
                ForEach(apps, id: \.self) { a in Muted("• " + a, size: 12) }
            }
        }
    }

    // MARK: Quarantaine

    private var quarantineTab: some View {
        VStack(spacing: 8) {
            if model.quarantine.isEmpty {
                GlassCard { Muted("La quarantaine est vide. Les menaces mises en quarantaine peuvent être restaurées ici.") }
            }
            ForEach(model.quarantine) { q in
                GlassCard(padding: 12) {
                    HStack(spacing: 10) {
                        IconBubble(symbol: "archivebox.fill", color: Palette.warning, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Strong(q.name, size: 13)
                            Muted("\(q.original) · \(Fmt.dateTime(q.date))", size: 11).lineLimit(1)
                        }
                        Spacer()
                        Button("Restaurer") { model.restore(q) }.buttonStyle(GlassButtonStyle())
                        Button("Supprimer") { model.purge(q) }.buttonStyle(GlassButtonStyle(danger: true))
                    }
                }
            }
        }
    }
}

struct ThreatRow: View {
    @Environment(\.palette) private var p
    let threat: Threat
    let on: Bool
    let toggle: () -> Void
    var color: Color { threat.severity == .high ? Palette.danger : threat.severity == .medium ? Palette.warning : Palette.blue }
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                CheckCircle(on: on)
                IconBubble(symbol: threat.severity == .check ? "questionmark.circle" : "ant.fill", color: color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Strong(threat.name, size: 13.5)
                        Tag(text: threat.severity.label, color: color)
                    }
                    Muted("\(threat.type) · \(threat.location)", size: 11).lineLimit(1)
                    if !threat.detail.isEmpty { Muted(threat.detail, size: 11).lineLimit(2) }
                }
                Spacer()
            }
            .padding(12)
            .background(GlassBackground(radius: 16))
        }
        .buttonStyle(PlainHover())
    }
}

struct SecurityRow: View {
    @Environment(\.palette) private var p
    let title: String
    let detail: String
    let ok: Bool
    let action: (String, () -> Void)?
    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20)).foregroundColor(ok ? Palette.success : Palette.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Strong(title, size: 13.5)
                    Muted(detail, size: 11.5)
                }
                Spacer()
                Tag(text: ok ? "Activé" : "Désactivé", color: ok ? Palette.success : Palette.warning)
                if let action {
                    Button(action.0, action: action.1).buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }
}
