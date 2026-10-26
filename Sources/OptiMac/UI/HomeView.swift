import SwiftUI

/// Accueil : gros bouton ANALYSER → résultats → BOOSTER MON MAC → bilan.
struct HomeView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var monitor: Monitor
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch model.phase {
                case .idle: idle
                case .scanning: scanning
                case .results: results
                case .boosting: boosting
                case .done: done
                }
                if model.phase == .idle || model.phase == .done {
                    quickTiles.appear(4)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
        }
    }

    // MARK: Repos

    private var idle: some View {
        VStack(spacing: 20) {
            GlassCard(radius: 30, padding: 34) {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text("Bonjour 👋").font(.system(size: 15, weight: .medium)).foregroundColor(p.muted)
                        Text("Votre Mac mérite un coup de neuf")
                            .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                            .multilineTextAlignment(.center)
                        Muted("Une seule analyse vérifie tout : fichiers inutiles, menaces, navigateurs détournés, démarrage et santé du disque.", size: 13.5)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                    ScanOrb { model.startScan() }
                    HStack(spacing: 18) {
                        Label(model.lastScan == nil ? "Jamais analysé" : "Dernière analyse : \(Fmt.dateTime(model.lastScan))", systemImage: "clock")
                        if let s = model.score {
                            Label("Score : \(s)/100", systemImage: "gauge")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(p.muted)
                }
                .frame(maxWidth: .infinity)
            }
            .appear(0)

            HStack(spacing: 14) {
                StatTile(icon: "internaldrive", color: Palette.accent, title: "Espace libre",
                         value: Fmt.bytes(monitor.freeSpace), detail: "sur \(Fmt.bytes(monitor.totalSpace))",
                         progress: monitor.diskUsedRatio)
                StatTile(icon: "memorychip", color: Palette.blue, title: "Mémoire utilisée",
                         value: Fmt.percent(monitor.memNow), detail: "\(Fmt.bytes(Int64(monitor.memUsed))) / \(Fmt.bytes(Int64(monitor.memTotal)))",
                         progress: monitor.memNow)
                StatTile(icon: "checkmark.shield", color: model.dangerCount > 0 ? Palette.danger : Palette.success, title: "Protection",
                         value: model.lastThreatScan == nil ? "À vérifier" : (model.dangerCount > 0 ? "\(model.dangerCount) menace(s)" : "Aucune menace"),
                         detail: model.lastThreatScan == nil ? "Lancez une analyse" : "Analysé \(Fmt.ago(model.lastThreatScan))", progress: nil)
            }
            .appear(2)

            PremiumBanner(text: "Version gratuite : le nettoyage est limité à 500 Mo et la protection ne fait que détecter. Premium nettoie tout, en un clic.",
                          feature: .unlimitedCleanup)
                .appear(3)
        }
    }

    // MARK: Analyse en cours

    private var scanning: some View {
        GlassCard(radius: 30, padding: 40) {
            VStack(spacing: 24) {
                ZStack {
                    Ring(value: model.progress, width: 16).frame(width: 190, height: 190)
                    PulseRings()
                    VStack(spacing: 4) {
                        Text(Fmt.percent(model.progress)).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        Text("Analyse").font(.system(size: 13, weight: .semibold)).foregroundColor(p.muted)
                    }
                }
                Text(model.progressLabel).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(p.text)
                HStack(spacing: 10) {
                    StepDot(title: "Fichiers", done: model.progress >= 0.3)
                    StepDot(title: "Menaces", done: model.progress >= 0.55)
                    StepDot(title: "Navigateurs", done: model.progress >= 0.7)
                    StepDot(title: "Démarrage", done: model.progress >= 0.85)
                    StepDot(title: "Disque", done: model.progress >= 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .appear(0)
    }

    // MARK: Résultats

    private var results: some View {
        VStack(spacing: 16) {
            GlassCard(radius: 30, padding: 26) {
                HStack(spacing: 26) {
                    ZStack {
                        Ring(value: Double(model.score ?? 0) / 100, color: scoreColor, width: 13).frame(width: 128, height: 128)
                        VStack(spacing: 0) {
                            Text("\(model.score ?? 0)").font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                            Text("/ 100").font(.system(size: 12, weight: .semibold)).foregroundColor(p.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(scoreTitle).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        Muted("OptiMac peut récupérer \(Fmt.bytes(model.selectedGain)) et corriger \(model.findings.filter { $0.alert }.count) problème(s) de sécurité.", size: 14)
                        HStack(spacing: 10) {
                            Button(action: { model.boost() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill")
                                    Text("BOOSTER MON MAC")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(large: true))
                            Button("Nouvelle analyse") { model.startScan() }
                                .buttonStyle(GlassButtonStyle())
                        }
                        .padding(.top, 6)
                    }
                    Spacer()
                }
            }
            .appear(0)

            VStack(spacing: 8) {
                ForEach(Array(model.findings.enumerated()), id: \.element.id) { i, f in
                    FindingRow(finding: f) {
                        if let idx = model.findings.firstIndex(where: { $0.id == f.id }) {
                            model.findings[idx].selected.toggle()
                        }
                    }
                    .appear(i + 1)
                }
                if model.findings.isEmpty {
                    GlassCard { HStack { Image(systemName: "sparkles").foregroundColor(Palette.success); Strong("Rien à corriger, votre Mac est en pleine forme !") } }
                }
            }

            if !license.isPremium && model.findings.contains(where: { $0.premium }) {
                PremiumBanner(text: "Les menaces et les navigateurs détournés ne sont supprimés qu'avec Premium. En version gratuite, OptiMac nettoie jusqu'à 500 Mo.",
                              feature: .threatRemoval)
            }
        }
    }

    private var scoreColor: Color {
        let s = model.score ?? 0
        return s >= 80 ? Palette.success : s >= 55 ? Palette.warning : Palette.danger
    }

    private var scoreTitle: String {
        let s = model.score ?? 0
        return s >= 80 ? "Votre Mac va bien" : s >= 55 ? "Votre Mac peut aller plus vite" : "Votre Mac a besoin d'aide"
    }

    // MARK: Optimisation en cours

    private var boosting: some View {
        GlassCard(radius: 30, padding: 34) {
            VStack(spacing: 20) {
                ZStack {
                    PulseRings()
                    Spinner(size: 70)
                    Image(systemName: "bolt.fill").font(.system(size: 26)).foregroundColor(Palette.accent)
                }
                .frame(height: 140)
                Text("Optimisation en cours…").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.boostSteps.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 10) {
                            Image(systemName: i == model.boostSteps.count - 1 ? "circle.dotted" : "checkmark.circle.fill")
                                .foregroundColor(i == model.boostSteps.count - 1 ? Palette.accent : Palette.success)
                            Text(s).font(.system(size: 13.5, weight: .medium)).foregroundColor(p.text)
                        }
                        .appear(0)
                    }
                }
                .frame(maxWidth: 380, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Bilan

    private var done: some View {
        GlassCard(radius: 30, padding: 34) {
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Palette.success.opacity(0.15)).frame(width: 120, height: 120)
                    Image(systemName: "checkmark").font(.system(size: 50, weight: .heavy)).foregroundColor(Palette.success)
                }
                .appear(0)
                Text("Votre Mac est optimisé").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                Text("\(Fmt.bytes(model.freed)) libérés").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(Palette.accent)
                Muted("Un instantané Time Machine a été créé avant l'optimisation.").multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Nouvelle analyse") { model.startScan() }.buttonStyle(PrimaryButtonStyle())
                    Button("Être rappelé par un technicien") { model.showCallback = true }.buttonStyle(GlassButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Raccourcis

    private var quickTiles: some View {
        let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: cols, spacing: 14) {
            QuickTile(icon: "trash", color: Palette.accent, title: "Nettoyage", detail: "Caches, journaux, corbeille") { model.section = .clean }
            QuickTile(icon: "chart.pie", color: Palette.blue, title: "Espace disque", detail: "Gros fichiers, doublons") { model.section = .space }
            QuickTile(icon: "checkmark.shield", color: Palette.success, title: "Protection", detail: "Malwares, navigateurs") { model.section = .protect }
            QuickTile(icon: "square.grid.2x2", color: Palette.purple, title: "Applications", detail: "Désinstaller, mettre à jour") { model.section = .apps }
            QuickTile(icon: "waveform.path.ecg", color: Color(hex: 0xEC4899), title: "Santé du Mac", detail: "Disque, batterie, mémoire") { model.section = .health }
            QuickTile(icon: "phone.fill", color: Color(hex: 0x14B8A6), title: "Être rappelé", detail: "Un technicien SecureeTech") { model.showCallback = true }
        }
    }
}

/// Grosse sphère en verre avec le bouton ANALYSER, qui « respire ».
struct ScanOrb: View {
    @Environment(\.palette) private var p
    let action: () -> Void
    @State private var breathe = false
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Palette.accent.opacity(0.18 - Double(i) * 0.05), lineWidth: 1.5)
                        .frame(width: 200 + CGFloat(i) * 36, height: 200 + CGFloat(i) * 36)
                        .scaleEffect(breathe ? 1.05 : 0.97)
                        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(Double(i) * 0.3), value: breathe)
                }
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFB36B), Palette.accent, Color(hex: 0xE45A00)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 4, endRadius: 120))
                    .frame(width: 190, height: 190)
                    .shadow(color: Palette.accent.opacity(0.55), radius: hover ? 34 : 24, x: 0, y: 14)
                Circle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.65), Color.white.opacity(0)], startPoint: .top, endPoint: .center))
                    .frame(width: 160, height: 160)
                    .offset(y: -12)
                    .blendMode(.plusLighter)
                    .opacity(0.55)
                Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5).frame(width: 190, height: 190)
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 30, weight: .bold))
                    Text("ANALYSER").font(.system(size: 22, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
            }
            .frame(width: 290, height: 290)
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: hover)
        }
        .buttonStyle(PlainHover())
        .onHover { hover = $0 }
        .onAppear { breathe = true }
    }
}

struct PulseRings: View {
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Palette.accent.opacity(0.35), lineWidth: 2)
                    .frame(width: 130, height: 130)
                    .scaleEffect(go ? 1.9 : 0.8)
                    .opacity(go ? 0 : 0.8)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.7), value: go)
            }
        }
        .onAppear { go = true }
    }
}

struct StepDot: View {
    @Environment(\.palette) private var p
    let title: String
    let done: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? Palette.success : p.muted.opacity(0.6))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(done ? p.text : p.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GlassBackground(radius: 12))
        .animation(.spring(), value: done)
    }
}

struct StatTile: View {
    @Environment(\.palette) private var p
    let icon: String
    let color: Color
    let title: String
    let value: String
    let detail: String
    let progress: Double?
    var body: some View {
        GlassCard(tint: color) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconBubble(symbol: icon, color: color, size: 34)
                    Spacer()
                }
                Muted(title)
                Text(value).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(p.text).lineLimit(1)
                if let progress { GlowBar(value: progress, color: color, height: 6) }
                Muted(detail, size: 11.5)
            }
        }
    }
}

struct QuickTile: View {
    @Environment(\.palette) private var p
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBubble(symbol: icon, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Strong(title)
                    Muted(detail, size: 11.5)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundColor(p.muted)
            }
            .padding(14)
            .background(GlassBackground(radius: 18, tint: hover ? color : nil))
            .offset(y: hover ? -2 : 0)
        }
        .buttonStyle(PlainHover())
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
    }
}

struct FindingRow: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    let finding: Finding
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                CheckCircle(on: finding.selected)
                IconBubble(symbol: finding.alert ? "exclamationmark.triangle.fill" : "doc.on.doc", color: finding.alert ? Palette.danger : Palette.accent, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Strong(finding.title)
                        if finding.premium && !license.isPremium { PremiumTag() }
                    }
                    if !finding.detail.isEmpty { Muted(finding.detail, size: 11.5).lineLimit(1) }
                }
                Spacer()
                if finding.size > 0 {
                    Text(Fmt.bytes(finding.size)).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(p.text)
                }
            }
            .padding(12)
            .background(GlassBackground(radius: 16))
        }
        .buttonStyle(PlainHover())
    }
}
