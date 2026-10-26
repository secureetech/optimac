import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Couleurs d'OptiMac. Orange SecureeTech en couleur principale, thème clair par défaut.
struct Palette {
    let bg: Color
    let sidebar: Color
    let card: Color
    let cardAlt: Color
    let border: Color
    let text: Color
    let muted: Color
    let subtle: Color
    let accentText: Color
    let selection: Color
    let dangerText: Color
    let warningText: Color
    let successText: Color
    let isDark: Bool

    static let accent = Color(hex: 0xFF7A1A)
    static let onAccent = Color(hex: 0x1A1206)
    static let danger = Color(hex: 0xE5484D)
    static let warning = Color(hex: 0xF5A524)
    static let success = Color(hex: 0x2FB67C)
    static let blue = Color(hex: 0x3B82F6)
    static let purple = Color(hex: 0x9B6BFF)

    static let light = Palette(
        bg: Color(hex: 0xF4F5F7), sidebar: Color(hex: 0xFFFFFF), card: Color(hex: 0xFFFFFF),
        cardAlt: Color(hex: 0xF7F8FA), border: Color(hex: 0xE3E5EA), text: Color(hex: 0x16171B),
        muted: Color(hex: 0x5B5F6B), subtle: Color(hex: 0xEEF0F3), accentText: Color(hex: 0xB4500A),
        selection: Color(hex: 0xFF7A1A, alpha: 0.12), dangerText: Color(hex: 0xC8282E),
        warningText: Color(hex: 0x9A5B00), successText: Color(hex: 0x1D7F53), isDark: false)

    static let dark = Palette(
        bg: Color(hex: 0x121317), sidebar: Color(hex: 0x17181D), card: Color(hex: 0x1E2027),
        cardAlt: Color(hex: 0x1A1C22), border: Color(hex: 0x2A2D36), text: Color(hex: 0xF2F2F4),
        muted: Color(hex: 0xA3A6B1), subtle: Color(hex: 0x2A2D36), accentText: Color(hex: 0xFFB27A),
        selection: Color(hex: 0xFF7A1A, alpha: 0.16), dangerText: Color(hex: 0xFF8A8A),
        warningText: Color(hex: 0xFFC46B), successText: Color(hex: 0x3DDC97), isDark: true)

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Transmet la bonne palette (claire ou sombre) à toute l'interface.
struct Themed<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .environment(\.palette, Palette.of(scheme))
            .accentColor(Palette.accent)
    }
}
