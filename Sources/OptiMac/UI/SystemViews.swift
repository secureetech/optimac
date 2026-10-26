import SwiftUI
import AppKit

// MARK: - Réseau

struct NetworkView: View {
    @EnvironmentObject var model: Model
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionTitle(title: "Réseau", subtitle: "Votre Wi-Fi, les appareils connectés chez vous et la vitesse de votre connexion.")
                    .appear(0)

                HStack(spacing: 14) {
                    GlassCard(tint: Palette.blue) {
                        VStack(alignment: .leading, spacing: 8) {
                            IconBubble(symbol: "wifi", color: Palette.blue)
                            Muted("Wi-Fi")
                            Text(model.wifi?.ssid.isEmpty == false ? model.wifi!.ssid : "—")
                                .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(p.text).lineLimit(1)
                            if let w = model.wifi, !w.ssid.isEmpty {
                                Tag(text: w.secure ? "Sécurisé (\(w.security))" : "Non sécurisé", color: w.secure ? Palette.success : Palette.danger)
                            }
                        }
                    }
                    GlassCard(tint: Palette.accent) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                IconBubble(symbol: "speedometer", color: Palette.accent)
                                Spacer()
                                if model.speedLoading { Spinner() } else {
                                    Button("Tester") { model.runSpeedTest() }.buttonStyle(PrimaryButtonStyle())
                                }
                            }
                            Muted("Vitesse internet")
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                speed("↓", model.speedDown)
                                speed("↑", model.speedUp)
                            }
                            if let ping = model.speedPing { Muted("Latence : \(Int(ping)) ms") }
                        }
                    }
                    GlassCard(tint: Palette.success) {
                        VStack(alignment: .leading, spacing: 8) {
                            IconBubble(symbol: "cross.case", color: Palette.success)
                            Muted("Pages qui ne s'ouvrent plus ?")
                            Button("Réparer internet") { model.repairInternet() }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .appear(1)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Strong("Appareils connectés au réseau")
                                Muted("Box, téléphones, imprimantes, télévisions… Un appareil inconnu peut être un voisin sur votre Wi-Fi.")
                            }
                            Spacer()
                            if model.netLoading { Spinner() } else {
                                Button("Rechercher") { model.scanNetwork() }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        if model.netLoading { GlowBar(value: model.netProgress) }
                        ForEach(model.devices) { d in
                            HStack(spacing: 12) {
                                IconBubble(symbol: d.isGateway ? "antenna.radiowaves.left.and.right" : (d.isSelf ? "laptopcomputer" : "dot.radiowaves.left.and.right"),
                                           color: d.isGateway ? Palette.accent : (d.isSelf ? Palette.success : Palette.blue), size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Strong(d.name, size: 13)
                                    Muted(d.mac.isEmpty ? d.ip : "\(d.ip) · \(d.mac)", size: 11)
                                }
                                Spacer()
                            }
                        }
                        if !model.netLoading && !model.devices.isEmpty {
                            Muted("\(model.devices.count) appareil(s) trouvé(s).")
                        }
                    }
                }
                .appear(2)
            }
            .padding(26)
        }
        .onAppear { if model.wifi == nil { model.wifi = NetworkEngine.wifi() } }
    }

    private func speed(_ arrow: String, _ v: Double?) -> some View {
        Text(v.map { "\(arrow) \(Int($0)) Mb/s" } ?? "\(arrow) —")
            .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(p.text)
    }
}

// MARK: - Santé du Mac

struct HealthView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var monitor: Monitor
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    SectionTitle(title: "Santé du Mac", subtitle: "État du disque (SMART), de la batterie, de la mémoire et du processeur.")
                    Button(action: { model.loadHealth() }) { Label("Actualiser", systemImage: "arrow.clockwise") }.buttonStyle(GlassButtonStyle())
                }
                .appear(0)

                HStack(spacing: 14) {
                    gauge("Processeur", monitor.cpuNow, Palette.accent, monitor.cpu)
                    gauge("Mémoire", monitor.memNow, Palette.blue, monitor.mem)
                    gauge("Disque occupé", monitor.diskUsedRatio, Palette.success, nil)
                    if monitor.hasGPU { gauge("Carte graphique", monitor.gpuNow, Palette.purple, monitor.gpu) }
                }
                .appear(1)

                HStack(alignment: .top, spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                IconBubble(symbol: "internaldrive.fill", color: Palette.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Strong("Disque")
                                    Muted(model.disk?.name ?? "…", size: 11.5)
                                }
                                Spacer()
                                if let d = model.disk {
                                    Tag(text: d.ok ? "Bon état" : (d.smart == "Not Supported" ? "Non communiqué" : d.smart), color: d.ok ? Palette.success : Palette.warning)
                                }
                            }
                            if let d = model.disk {
                                info("État SMART", d.smart == "Verified" ? "Vérifié" : d.smart)
                                info("Type", d.solidState ? "SSD" : "Disque dur")
                                if !d.protocolName.isEmpty { info("Connexion", d.protocolName) }
                                info("Capacité", Fmt.bytes(d.total))
                                info("Libre", Fmt.bytes(d.free))
                                info("Température", thermalLabel)
                            }
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                IconBubble(symbol: "battery.100", color: Palette.success)
                                Strong("Batterie")
                                Spacer()
                                if let b = model.battery, b.present {
                                    Tag(text: b.condition, color: b.capacity >= 0.8 ? Palette.success : Palette.warning)
                                }
                            }
                            if let b = model.battery, b.present {
                                info("Capacité maximale", Fmt.percent(b.capacity))
                                GlowBar(value: b.capacity, color: b.capacity >= 0.8 ? Palette.success : Palette.warning)
                                info("Cycles de charge", "\(b.cycles)")
                                info("Charge actuelle", "\(b.level) %\(b.charging ? " (en charge)" : "")")
                                if let t = b.temperature { info("Température", String(format: "%.0f °C", t)) }
                            } else {
                                Muted("Ce Mac n'a pas de batterie (Mac de bureau).")
                            }
                        }
                    }
                }
                .appear(2)

                if let h = model.hardware {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { IconBubble(symbol: "desktopcomputer", color: Palette.blue); Strong("Ce Mac") }
                            info("Modèle", h.model)
                            if !h.chip.isEmpty { info("Puce", h.chip) }
                            if !h.memory.isEmpty { info("Mémoire", h.memory) }
                            info("Système", h.macOS)
                            if !h.serial.isEmpty { info("Numéro de série", h.serial) }
                        }
                    }
                    .appear(3)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Strong("Ce qui ralentit votre Mac")
                                Muted("Applications qui utilisent le plus le processeur et la mémoire.")
                            }
                            Spacer()
                            Button("Libérer la mémoire") { model.freeMemory() }.buttonStyle(PrimaryButtonStyle())
                        }
                        ForEach(model.processes) { pr in
                            HStack(spacing: 10) {
                                if let i = pr.icon { Image(nsImage: i).resizable().frame(width: 22, height: 22) }
                                else { Image(systemName: "gearshape").frame(width: 22, height: 22).foregroundColor(p.muted) }
                                Text(pr.name).font(.system(size: 13, weight: .medium)).foregroundColor(p.text).lineLimit(1)
                                Spacer()
                                Muted(String(format: "%.0f %%", pr.cpu), size: 12).frame(width: 52, alignment: .trailing)
                                Muted(Fmt.bytes(pr.memory), size: 12).frame(width: 70, alignment: .trailing)
                                Button("Quitter") { model.quit(pr, force: false) }.buttonStyle(GlassButtonStyle())
                                Button("Forcer") { model.quit(pr, force: true) }.buttonStyle(GlassButtonStyle(danger: true))
                            }
                        }
                    }
                }
                .appear(4)

                ScoreHistoryCard().appear(5)
            }
            .padding(26)
        }
        .onAppear { model.loadHealth() }
    }

    private var thermalLabel: String {
        switch monitor.thermal {
        case .nominal: return "Normale"
        case .fair: return "Tiède"
        case .serious: return "Chaude"
        case .critical: return "Très chaude"
        @unknown default: return "—"
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack {
            Muted(k)
            Spacer()
            Text(v).font(.system(size: 12.5, weight: .semibold)).foregroundColor(p.text).lineLimit(1)
        }
    }

    private func gauge(_ title: String, _ v: Double, _ c: Color, _ series: [Double]?) -> some View {
        GlassCard(tint: c) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Ring(value: v, color: c, width: 7).frame(width: 52, height: 52)
                        Text(Fmt.percent(v)).font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                    }
                    Spacer()
                }
                Strong(title, size: 13)
                if let series { Sparkline(values: series, color: c, maxValue: 1).frame(height: 26) }
            }
        }
    }
}

struct ScoreHistoryCard: View {
    @EnvironmentObject var model: Model
    @Environment(\.palette) private var p
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Strong("Score de votre Mac sur 30 jours")
                if model.history.count < 2 {
                    Muted("Faites quelques analyses pour voir l'évolution de votre score.")
                } else {
                    Sparkline(values: model.history.map { Double($0.1) }, color: Palette.accent, maxValue: 100).frame(height: 70)
                    HStack {
                        Muted(Fmt.date(model.history.first?.0), size: 11)
                        Spacer()
                        Muted(Fmt.date(model.history.last?.0), size: 11)
                    }
                }
            }
        }
    }
}

// MARK: - Outils

struct ToolsView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    @State private var reduced = UserDefaults.standard.bool(forKey: "effectsReduced")

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionTitle(title: "Outils", subtitle: "Suppression forcée, broyeur, maintenance, effets visuels et points de restauration.")
                    .appear(0)

                HStack(spacing: 14) {
                    toolCard(icon: "xmark.bin.fill", color: Palette.danger, title: "Suppression forcée",
                             detail: "Supprime les fichiers et dossiers que macOS refuse d'effacer (verrouillés, protégés, en cours d'utilisation).",
                             button: "Choisir des éléments…") {
                        let urls = FilePicker.pick(prompt: "Supprimer de force")
                        if !urls.isEmpty, Confirm.ask("Supprimer de force ?", "\(urls.count) élément(s) seront supprimés définitivement.", ok: "Supprimer", danger: true) {
                            model.forceDelete(urls)
                        }
                    }
                    toolCard(icon: "scissors", color: Palette.purple, title: "Broyeur de fichiers",
                             detail: "Détruit des fichiers confidentiels sans aucune possibilité de récupération.",
                             button: "Choisir des fichiers…") {
                        let urls = FilePicker.pick(prompt: "Broyer")
                        if !urls.isEmpty, Confirm.ask("Broyer définitivement ?", "\(urls.count) élément(s) seront écrasés puis supprimés. Impossible de les récupérer.", ok: "Broyer", danger: true) {
                            model.shred(urls)
                        }
                    }
                }
                .appear(1)

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            IconBubble(symbol: "wrench.and.screwdriver.fill", color: Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Strong("Maintenance du Mac")
                                Muted("Les réparations que les techniciens font à la main, en un clic.")
                            }
                            Spacer()
                            if !license.isPremium { PremiumTag() }
                            Button("Lancer la maintenance") { model.runMaintenance() }.buttonStyle(PrimaryButtonStyle())
                        }
                        ForEach(Array(model.maintenance.enumerated()), id: \.element.id) { i, t in
                            Button(action: { model.maintenance[i].selected.toggle() }) {
                                HStack(spacing: 10) {
                                    CheckCircle(on: t.selected)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Strong(t.title, size: 13)
                                        Muted(t.detail, size: 11.5)
                                    }
                                    Spacer()
                                    if t.admin { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundColor(p.muted).help("Mot de passe administrateur demandé") }
                                }
                            }
                            .buttonStyle(PlainHover())
                        }
                    }
                }
                .appear(2)

                HStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            IconBubble(symbol: "sparkles", color: Palette.blue)
                            Strong("Effets visuels")
                            Muted("Moins d'animations et de transparence : idéal pour les Mac anciens.")
                            Toggle("Mode rapide", isOn: Binding(get: { reduced }, set: { v in
                                reduced = v
                                UserDefaults.standard.set(v, forKey: "effectsReduced")
                                model.reduceEffects(v)
                            }))
                            .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            IconBubble(symbol: "clock.arrow.circlepath", color: Palette.success)
                            Strong("Point de restauration")
                            Muted("Crée un instantané Time Machine local avant une grosse modification.")
                            Button("Créer maintenant") {
                                Task {
                                    let ok = await background { MaintenanceEngine.snapshot() }
                                    model.notify(ok ? "Instantané créé" : "Instantané impossible (Time Machine désactivé ?)")
                                }
                            }
                            .buttonStyle(GlassButtonStyle())
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            IconBubble(symbol: "phone.fill", color: Color(hex: 0x14B8A6))
                            Strong("Assistance SecureeTech")
                            Muted("Un technicien vous rappelle pour vous aider.")
                            Button("Être rappelé") { model.showCallback = true }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .appear(3)

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Strong("Historique d'activité")
                            Spacer()
                            Button("Effacer") { ActivityLog.clear(); model.activity = [] }.buttonStyle(GlassButtonStyle())
                        }
                        if model.activity.isEmpty { Muted("Aucune activité pour le moment.") }
                        ForEach(Array(model.activity.prefix(30).enumerated()), id: \.offset) { _, e in
                            HStack {
                                Muted(Fmt.dateTime(e.0), size: 11).frame(width: 150, alignment: .leading)
                                Text(e.1).font(.system(size: 12.5)).foregroundColor(p.text)
                                Spacer()
                            }
                        }
                    }
                }
                .appear(4)
            }
            .padding(26)
        }
    }

    private func toolCard(icon: String, color: Color, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        GlassCard(tint: color) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconBubble(symbol: icon, color: color)
                    Spacer()
                    if !license.isPremium { PremiumTag() }
                }
                Strong(title)
                Muted(detail)
                Button(button, action: action).buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
