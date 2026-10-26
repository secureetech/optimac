import SwiftUI
import AppKit

/// Fenêtre principale : barre latérale en verre + écran actif + fenêtres d'offre.
struct RootView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            AuroraBackground()
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 248)
                    .padding(.leading, 12)
                    .padding(.vertical, 12)
                ZStack(alignment: .top) {
                    content
                        .id(model.section)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: model.section)
            }
            .padding(.top, 26)

            TopBar()
                .frame(maxHeight: .infinity, alignment: .top)

            if let w = model.working {
                WorkingOverlay(text: w).transition(.opacity)
            }
            if let t = model.toast {
                ToastView(text: t)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.showPremium {
                PremiumSheet().transition(.opacity)
            }
            if model.showCallback {
                CallbackSheet().transition(.opacity)
            }
            if !settings.welcomeShown {
                WelcomeSheet().transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.toast)
        .animation(.easeInOut(duration: 0.25), value: model.working)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: model.showPremium)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: model.showCallback)
        .font(.system(size: 13 * settings.textSize.scale))
        .frame(minWidth: 1080, minHeight: 720)
        .edgesIgnoringSafeArea(.all)
    }

    @ViewBuilder private var content: some View {
        switch model.section {
        case .home: HomeView()
        case .clean: CleanView()
        case .space: SpaceView()
        case .protect: ProtectView()
        case .apps: AppsView()
        case .network: NetworkView()
        case .health: HealthView()
        case .tools: ToolsView()
        case .settings: SettingsView()
        }
    }
}

/// Barre du haut : titre centré + bascule clair/sombre (les pastilles macOS restent à gauche).
struct TopBar: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 80)
            Spacer()
            Text("OptiMac").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundColor(p.muted)
            Text("by SecureeTech").font(.system(size: 11.5)).foregroundColor(p.muted.opacity(0.7))
            Spacer()
            Button(action: { withAnimation { settings.toggleTheme() } }) {
                Image(systemName: p.isDark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(p.isDark ? Color(hex: 0xFFD27A) : p.muted)
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(PlainHover())
            .help("Thème clair / sombre")
            .padding(.trailing, 14)
        }
        .frame(height: 30)
    }
}

// MARK: - Barre latérale

struct Sidebar: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var monitor: Monitor
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Logo(size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OptiMac").font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                    Text("by SecureeTech").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 14)

            VStack(spacing: 3) {
                ForEach(Section.allCases.filter { $0 != .settings }) { s in
                    SidebarItem(section: s)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 10)

            VStack(spacing: 8) {
                MeterRow(label: "Processeur", value: Fmt.percent(monitor.cpuNow), values: monitor.cpu, color: Palette.accent, max: 1)
                MeterRow(label: "Mémoire", value: Fmt.percent(monitor.memNow), values: monitor.mem, color: Palette.blue, max: 1)
                MeterRow(label: "Disque", value: Fmt.bytes(Int64(monitor.diskRate)) + "/s", values: monitor.disk, color: Palette.success, max: nil)
                if monitor.hasGPU {
                    MeterRow(label: "Carte graphique", value: Fmt.percent(monitor.gpuNow), values: monitor.gpu, color: Palette.purple, max: 1)
                }
            }
            .padding(.horizontal, 10)

            SidebarItem(section: .settings).padding(.horizontal, 8).padding(.top, 8)

            Button(action: {
                if !license.isPremium || license.isTrial { model.premiumFeature = nil; model.showPremium = true }
                else { model.section = .settings }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: license.isPremium ? "crown.fill" : "crown")
                        .foregroundColor(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(license.statusLabel).font(.system(size: 12, weight: .semibold)).foregroundColor(p.text).lineLimit(1)
                        if !license.isPremium || license.isTrial {
                            Text("Activer Premium").font(.system(size: 11, weight: .bold)).foregroundColor(Palette.accent)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(GlassBackground(radius: 14, tint: Palette.accent))
            }
            .buttonStyle(PlainHover())
            .padding(10)
        }
        .background(GlassBackground(radius: 26, strong: true))
    }
}

struct SidebarItem: View {
    @EnvironmentObject var model: Model
    @Environment(\.palette) private var p
    let section: Section
    @State private var hover = false

    var badge: Int {
        switch section {
        case .protect: return model.dangerCount + model.hijackedCount
        case .apps: return model.apps.filter { $0.update != nil }.count
        default: return 0
        }
    }

    var body: some View {
        let selected = model.section == section
        Button(action: { model.section = section }) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selected ? .white : p.muted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? AnyShapeStyleFill.accent : AnyShapeStyleFill.clear)
                    )
                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundColor(selected ? p.text : p.muted)
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 10.5, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.danger))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? p.selection : (hover ? p.subtle.opacity(0.6) : Color.clear))
            )
        }
        .buttonStyle(PlainHover())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Remplissage de l'icône sélectionnée (dégradé orange) — compatible macOS 11.
enum AnyShapeStyleFill {
    static let accent = LinearGradient(colors: [Color(hex: 0xFF9A3D), Palette.accent], startPoint: .top, endPoint: .bottom)
    static let clear = LinearGradient(colors: [Color.clear, Color.clear], startPoint: .top, endPoint: .bottom)
}

struct MeterRow: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    let values: [Double]
    let color: Color
    let max: Double?
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundColor(p.muted)
                Spacer()
                Text(value).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(p.text)
            }
            Sparkline(values: values, color: color, maxValue: max).frame(height: 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GlassBackground(radius: 12))
    }
}

// MARK: - Notifications dans la fenêtre

struct ToastView: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(Palette.success)
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(p.text)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(GlassBackground(radius: 20, strong: true))
    }
}

struct WorkingOverlay: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(p.isDark ? 0.35 : 0.12)
            VStack(spacing: 14) {
                Spinner(size: 34)
                Text(text).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(p.text)
                Muted("Merci de patienter, ne fermez pas OptiMac.")
            }
            .padding(30)
            .background(GlassBackground(radius: 26, strong: true))
        }
    }
}

/// Fond assombri + carte centrale en verre, pour les fenêtres d'OptiMac.
struct Modal<Content: View>: View {
    @Environment(\.palette) private var p
    let width: CGFloat
    let onClose: (() -> Void)?
    let content: Content
    init(width: CGFloat = 560, onClose: (() -> Void)? = nil, @ViewBuilder _ content: () -> Content) {
        self.width = width
        self.onClose = onClose
        self.content = content()
    }
    @State private var shown = false
    var body: some View {
        ZStack {
            Color.black.opacity(p.isDark ? 0.45 : 0.22)
                .onTapGesture { onClose?() }
            ZStack(alignment: .topTrailing) {
                content.padding(28)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(p.muted)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(p.subtle))
                    }
                    .buttonStyle(PlainHover())
                    .padding(14)
                }
            }
            .frame(width: width)
            .background(GlassBackground(radius: 28, strong: true))
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { shown = true } }
        }
    }
}
