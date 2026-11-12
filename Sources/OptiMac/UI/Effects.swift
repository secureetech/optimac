import SwiftUI

// MARK: - Effets 3D et animations (tout fonctionne dès macOS 11 Big Sur)

/// Carte qui se soulève et s'incline en 3D au passage de la souris.
struct Tilt3D: ViewModifier {
    var amount: Double = 7
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(hover ? amount : 0), axis: (x: 1, y: -0.6, z: 0), anchor: .center, perspective: 0.6)
            .scaleEffect(hover ? 1.025 : 1)
            .shadow(color: Color.black.opacity(hover ? 0.16 : 0), radius: 18, x: 0, y: 14)
            .onHover { hover = $0 }
            .animation(.spring(response: 0.4, dampingFraction: 0.62), value: hover)
    }
}

extension View {
    func tilt3D(_ amount: Double = 7) -> some View { modifier(Tilt3D(amount: amount)) }
}

/// Gyroscope : trois anneaux lumineux qui tournent dans l'espace autour d'un centre.
struct Orbit3D: View {
    var size: CGFloat = 230
    var color: Color = Palette.accent
    var speed: Double = 1
    @State private var spin = false

    var body: some View {
        ZStack {
            ring(axis: (1, 0.2, 0), tilt: 68, duration: 5.5, width: 2.5, dot: true)
            ring(axis: (0.2, 1, 0), tilt: 72, duration: 7.5, width: 2, dot: true).scaleEffect(0.86)
            ring(axis: (0.7, 0.7, 0), tilt: 60, duration: 9.5, width: 1.5, dot: false).scaleEffect(1.12)
        }
        .frame(width: size, height: size)
        .onAppear { spin = true }
        .allowsHitTesting(false)
    }

    private func ring(axis: (CGFloat, CGFloat, CGFloat), tilt: Double, duration: Double, width: CGFloat, dot: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(AngularGradient(gradient: Gradient(colors: [color.opacity(0), color.opacity(0.9), Color.white.opacity(0.9), color.opacity(0)]),
                                        center: .center), lineWidth: width)
            if dot {
                Circle().fill(Color.white).frame(width: 7, height: 7)
                    .shadow(color: color, radius: 6)
                    .offset(y: -size / 2)
            }
        }
        .rotationEffect(.degrees(spin ? 360 : 0))
        .animation(.linear(duration: duration / speed).repeatForever(autoreverses: false), value: spin)
        .rotation3DEffect(.degrees(tilt), axis: (x: axis.0, y: axis.1, z: axis.2), perspective: 0.5)
        .shadow(color: color.opacity(0.5), radius: 6)
    }
}

/// Radar : cercles, faisceau qui balaie et points qui s'allument pendant l'analyse.
struct RadarView: View {
    @Environment(\.palette) private var p
    var size: CGFloat = 150
    var color: Color = Palette.success
    @State private var sweep = false
    @State private var blink = false

    private let blips: [(CGFloat, CGFloat, Double)] = [(0.32, -0.2, 0), (-0.25, 0.3, 0.9), (0.12, 0.36, 1.7), (-0.34, -0.14, 2.4), (0.4, 0.12, 3.1)]

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.22), color.opacity(0.04)], center: .center, startRadius: 2, endRadius: size / 2))
            ForEach(1..<4) { i in
                Circle().stroke(color.opacity(0.35), lineWidth: 1).frame(width: size * CGFloat(i) / 3, height: size * CGFloat(i) / 3)
            }
            Rectangle().fill(color.opacity(0.25)).frame(width: 1, height: size)
            Rectangle().fill(color.opacity(0.25)).frame(width: size, height: 1)
            Circle()
                .fill(AngularGradient(gradient: Gradient(stops: [.init(color: color.opacity(0), location: 0),
                                                                 .init(color: color.opacity(0), location: 0.72),
                                                                 .init(color: color.opacity(0.75), location: 1)]), center: .center))
                .rotationEffect(.degrees(sweep ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: sweep)
            ForEach(0..<blips.count, id: \.self) { i in
                Circle().fill(Color.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: color, radius: 5)
                    .offset(x: blips[i].0 * size, y: blips[i].1 * size)
                    .opacity(blink ? 1 : 0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(blips[i].2 * 0.4), value: blink)
            }
            Circle().strokeBorder(color.opacity(0.7), lineWidth: 1.5)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .rotation3DEffect(.degrees(28), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .shadow(color: color.opacity(0.45), radius: 14, x: 0, y: 10)
        .onAppear { sweep = true; blink = true }
    }
}

/// Bouclier qui tourne sur lui-même en 3D.
struct Shield3D: View {
    var color: Color = Palette.success
    var symbol = "checkmark.shield.fill"
    var size: CGFloat = 54
    var spinning = true
    @State private var turn = false

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.35), color.opacity(0)], center: .center, startRadius: 2, endRadius: size * 0.75))
                .frame(width: size * 1.5, height: size * 1.5)
            Image(systemName: symbol)
                .font(.system(size: size * 0.78, weight: .bold))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.6), radius: 8, x: 0, y: 4)
                .rotation3DEffect(.degrees(turn ? 360 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .animation(spinning ? .easeInOut(duration: 3.2).repeatForever(autoreverses: false) : .default, value: turn)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .onAppear { turn = true }
    }
}

/// Explosion de particules (réussite).
struct ParticleBurst: View {
    var count = 28
    var colors: [Color] = [Palette.accent, Palette.success, Palette.blue, Palette.purple, Color(hex: 0xFFD27A)]
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * Double.pi
                let dist = CGFloat(110 + (i * 37) % 90)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors[i % colors.count])
                    .frame(width: i % 3 == 0 ? 9 : 6, height: i % 3 == 0 ? 9 : 6)
                    .rotationEffect(.degrees(go ? Double(i * 47) : 0))
                    .offset(x: go ? CGFloat(cos(angle)) * dist : 0, y: go ? CGFloat(sin(angle)) * dist + 30 : 0)
                    .opacity(go ? 0 : 1)
                    .animation(.easeOut(duration: 1.3 + Double(i % 5) * 0.12), value: go)
            }
        }
        .allowsHitTesting(false)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { go = true } }
    }
}

/// Nombre qui défile jusqu'à sa valeur (« 12,4 Go libérés »).
private struct CountModifier: AnimatableModifier {
    var value: Double
    let format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    func body(content: Content) -> some View { Text(format(value)) }
}

struct CountUp: View {
    let target: Double
    var duration: Double = 1.4
    let format: (Double) -> String
    @State private var shown: Double = 0

    var body: some View {
        Text("").modifier(CountModifier(value: shown, format: format))
            .onAppear { withAnimation(.easeOut(duration: duration)) { shown = target } }
            .onChange(of: target) { v in withAnimation(.easeOut(duration: 0.4)) { shown = v } }
    }
}

/// Reflet lumineux qui traverse un élément en boucle.
struct Shine: ViewModifier {
    @State private var move = false
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { g in
                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.55), Color.white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.35)
                    .rotationEffect(.degrees(20))
                    .offset(x: move ? g.size.width * 1.2 : -g.size.width * 0.6)
                    .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false), value: move)
            }
            .allowsHitTesting(false)
            .blendMode(.plusLighter)
        )
        .onAppear { move = true }
    }
}

extension View {
    func shine() -> some View { modifier(Shine()) }
}

/// Compteur en direct d'une analyse : nombre de fichiers et fichier en cours.
struct LiveScanCounter: View {
    @Environment(\.palette) private var p
    let files: Int
    let current: String
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Fmt.number(files)) fichiers examinés")
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(p.text)
            Text(current.replacingOccurrences(of: FS.home.path, with: "~"))
                .font(.system(size: 10.5, design: .monospaced)).foregroundColor(p.muted)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 520)
        }
    }
}
