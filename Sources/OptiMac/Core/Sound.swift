import AppKit

/// Sons et retours haptiques d'OptiMac (fichiers fabriqués par scripts/generer-sons.py).
enum Sound: String, CaseIterable {
    case click, start, tick, found, success, alert, boost, whoosh

    private static var cache: [Sound: NSSound] = [:]
    private static var lastTick = Date.distantPast
    /// Coupé pendant la visite automatique (captures d'écran de la compilation).
    static var muted = false

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundsEnabled") }
    }

    static var volume: Float {
        get { UserDefaults.standard.object(forKey: "soundsVolume") as? Float ?? 0.8 }
        set { UserDefaults.standard.set(newValue, forKey: "soundsVolume") }
    }

    func play() {
        guard Sound.enabled, !Sound.muted else { return }
        // Les « tics » de progression restent discrets : quatre par seconde au plus.
        if self == .tick {
            if Date().timeIntervalSince(Sound.lastTick) < 0.22 { return }
            Sound.lastTick = Date()
        }
        DispatchQueue.main.async {
            let s: NSSound
            if let cached = Sound.cache[self], !cached.isPlaying {
                s = cached
            } else if let u = Bundle.main.url(forResource: self.rawValue, withExtension: "wav", subdirectory: "Sounds")
                        ?? Bundle.main.url(forResource: self.rawValue, withExtension: "wav"),
                      let loaded = NSSound(contentsOf: u, byReference: true) {
                s = loaded
                Sound.cache[self] = loaded
            } else { return }
            s.volume = Sound.volume
            s.play()
        }
        Haptic.forSound(self)
    }
}

/// Petites vibrations du trackpad (Force Touch).
enum Haptic {
    static func tap() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    static func strong() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
    static func forSound(_ s: Sound) {
        switch s {
        case .success, .alert, .boost, .start: strong()
        case .click, .found: tap()
        default: break
        }
    }
}
