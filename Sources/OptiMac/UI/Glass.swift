import SwiftUI
import AppKit

// MARK: - Verre « Liquid Glass » (compatible macOS 11 Big Sur)

/// Flou natif de macOS (NSVisualEffectView) : la base de l'effet verre.
struct VisualBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Carte en verre dépoli : flou + reflet + liseré lumineux + ombre douce.
struct GlassBackground: View {
    @Environment(\.palette) private var p
    var radius: CGFloat = 22
    var tint: Color? = nil
    var strong = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            VisualBlur(material: p.isDark ? .hudWindow : .popover)
            shape.fill(p.isDark ? Color.white.opacity(strong ? 0.07 : 0.045) : Color.white.opacity(strong ? 0.78 : 0.6))
            if let tint {
                shape.fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            // Reflet de lumière en haut, comme sur le verre d'iPhone
            shape.fill(LinearGradient(colors: [Color.white.opacity(p.isDark ? 0.10 : 0.55), Color.white.opacity(0)],
                                      startPoint: .top, endPoint: .center))
                .blendMode(.plusLighter)
                .opacity(0.6)
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(p.isDark ? 0.22 : 0.95),
                                                       Color.white.opacity(p.isDark ? 0.04 : 0.35),
                                                       (tint ?? Color.white).opacity(p.isDark ? 0.18 : 0.25)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(p.isDark ? 0.35 : 0.08), radius: 18, x: 0, y: 10)
    }
}

struct GlassCard<Content: View>: View {
    var radius: CGFloat = 22
    var padding: CGFloat = 18
    var tint: Color? = nil
    let content: Content

    init(radius: CGFloat = 22, padding: CGFloat = 18, tint: Color? = nil, @ViewBuilder _ content: () -> Content) {
        self.radius = radius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassBackground(radius: radius, tint: tint))
    }
}

/// Fond animé : halos de couleur qui dérivent lentement derrière le verre.
struct AuroraBackground: View {
    @Environment(\.palette) private var p
    @State private var move = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                p.bg
                blob(Palette.accent, size: g.size.width * 0.55)
                    .offset(x: move ? g.size.width * 0.28 : g.size.width * 0.12, y: move ? -g.size.height * 0.18 : -g.size.height * 0.05)
                blob(Color(hex: 0xFFB36B), size: g.size.width * 0.45)
                    .offset(x: move ? -g.size.width * 0.22 : -g.size.width * 0.32, y: move ? g.size.height * 0.28 : g.size.height * 0.12)
                blob(Palette.purple, size: g.size.width * 0.38)
                    .offset(x: move ? g.size.width * 0.05 : g.size.width * 0.2, y: move ? g.size.height * 0.35 : g.size.height * 0.42)
                    .opacity(0.55)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { move = true }
        }
    }

    private func blob(_ c: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [c.opacity(p.isDark ? 0.30 : 0.26), c.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .blur(radius: 30)
    }
}

// MARK: - Boutons

struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    var color: Color = Palette.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 17 : 13.5, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, large ? 30 : 18)
            .padding(.vertical, large ? 15 : 9)
            .background(
                ZStack {
                    Capsule().fill(LinearGradient(colors: [color.opacity(0.95), color, Color(hex: 0xE85D00)], startPoint: .top, endPoint: .bottom))
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)], startPoint: .top, endPoint: .center))
                        .padding(1.5)
                }
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: color.opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 6 : 14, x: 0, y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(danger ? p.dangerText : p.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(GlassBackground(radius: 12))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct PlainHover: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - Petits éléments

struct Tag: View {
    let text: String
    var color: Color = Palette.accent
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.8))
    }
}

struct PremiumTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").font(.system(size: 9))
            Text("PREMIUM")
        }
        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFB04A), Palette.accent], startPoint: .leading, endPoint: .trailing)))
    }
}

struct IconBubble: View {
    let symbol: String
    var color: Color = Palette.accent
    var size: CGFloat = 38
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 0.8)
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
    }
}

struct SectionTitle: View {
    @Environment(\.palette) private var p
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(p.text)
            if let subtitle {
                Text(subtitle).font(.system(size: 13.5)).foregroundColor(p.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Muted: View {
    @Environment(\.palette) private var p
    let text: String
    var size: CGFloat = 12.5
    init(_ text: String, size: CGFloat = 12.5) { self.text = text; self.size = size }
    var body: some View {
        Text(text).font(.system(size: size)).foregroundColor(p.muted).fixedSize(horizontal: false, vertical: true)
    }
}

struct Strong: View {
    @Environment(\.palette) private var p
    let text: String
    var size: CGFloat = 14
    init(_ text: String, size: CGFloat = 14) { self.text = text; self.size = size }
    var body: some View {
        Text(text).font(.system(size: size, weight: .semibold, design: .rounded)).foregroundColor(p.text).lineLimit(1)
    }
}

/// Case à cocher ronde, orange.
struct CheckCircle: View {
    @Environment(\.palette) private var p
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Palette.accent : p.muted.opacity(0.5), lineWidth: 1.6)
            if on {
                Circle().fill(Palette.accent).padding(0.5)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
            }
        }
        .frame(width: 19, height: 19)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: on)
    }
}

/// Barre de progression arrondie et animée.
struct GlowBar: View {
    @Environment(\.palette) private var p
    let value: Double
    var color: Color = Palette.accent
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(p.subtle)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * CGFloat(min(1, max(0, value)))))
                    .shadow(color: color.opacity(0.5), radius: 6, x: 0, y: 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

/// Anneau de score / jauge circulaire.
struct Ring: View {
    @Environment(\.palette) private var p
    let value: Double
    var color: Color = Palette.accent
    var width: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().stroke(p.subtle, lineWidth: width)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, value))))
                .stroke(AngularGradient(gradient: Gradient(colors: [color.opacity(0.55), color, color.opacity(0.9)]), center: .center),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 8)
        }
        .animation(.easeOut(duration: 0.9), value: value)
    }
}

/// Mini graphique en courbe (barre latérale).
struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.accent
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { g in
            let top = maxValue ?? max(values.max() ?? 1, 0.0001)
            let pts = values.enumerated().map { i, v -> CGPoint in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1)),
                        y: g.size.height * (1 - CGFloat(min(1, v / top))))
            }
            ZStack {
                Path { path in
                    guard let f = pts.first else { return }
                    path.move(to: CGPoint(x: f.x, y: g.size.height))
                    pts.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let f = pts.first else { return }
                    path.move(to: f)
                    pts.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Bloc d'écran « vide » ou de chargement.
struct LoadingCard: View {
    @Environment(\.palette) private var p
    let text: String
    var progress: Double? = nil
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Spinner()
                VStack(alignment: .leading, spacing: 8) {
                    Strong(text)
                    if let progress { GlowBar(value: progress) }
                }
            }
        }
    }
}

struct Spinner: View {
    @State private var spin = false
    var size: CGFloat = 22
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.85)
            .stroke(AngularGradient(gradient: Gradient(colors: [Palette.accent.opacity(0.1), Palette.accent]), center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
    }
}

/// Bandeau qui pousse vers Premium (version gratuite).
struct PremiumBanner: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    let text: String
    let feature: PremiumFeature

    var body: some View {
        if !license.isPremium {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill").foregroundColor(Palette.accent).font(.system(size: 16))
                Text(text).font(.system(size: 13, weight: .medium)).foregroundColor(p.text).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Passer à Premium") {
                    model.premiumFeature = feature
                    model.showPremium = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(14)
            .background(GlassBackground(radius: 18, tint: Palette.accent))
        }
    }
}

/// Apparition en fondu + glissement, décalée selon l'ordre.
struct Appear: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func appear(_ index: Int = 0) -> some View { modifier(Appear(delay: Double(index) * 0.05)) }
}

/// Logo SecureeTech (bouclier orange « S ») embarqué dans l'application.
struct Logo: View {
    var size: CGFloat = 34
    static let image: NSImage? = {
        if let u = Bundle.main.url(forResource: "logo", withExtension: "png") { return NSImage(contentsOf: u) }
        return NSImage(named: "AppIcon")
    }()
    var body: some View {
        Group {
            if let img = Logo.image {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "shield.fill").resizable().aspectRatio(contentMode: .fit).foregroundColor(Palette.accent)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Palette.accent.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}

/// Choix de fichiers (Finder).
enum FilePicker {
    static func pick(directories: Bool = true, multiple: Bool = true, prompt: String = "Choisir") -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = multiple
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// Confirmation simple (fenêtre macOS).
enum Confirm {
    static func ask(_ title: String, _ text: String, ok: String = "Continuer", danger: Bool = false) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = danger ? .critical : .informational
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Annuler")
        return a.runModal() == .alertFirstButtonReturn
    }
}
