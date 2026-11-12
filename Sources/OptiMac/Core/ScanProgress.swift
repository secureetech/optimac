import Foundation

/// Avancement d'une analyse, partagé entre le moteur (en arrière-plan) et l'interface.
final class ScanProgress {
    private let lock = NSLock()
    private var files = 0
    private var current = ""
    private var label = ""
    private var local = 0.0
    private var base = 0.0
    private var span = 1.0

    /// Un fichier de plus a été examiné.
    func tick(_ path: String) {
        lock.lock(); files += 1; current = path; lock.unlock()
    }

    /// Portion de la jauge réservée à l'étape en cours (ex. 0,35 → 0,70).
    func setRange(base: Double, span: Double) {
        lock.lock(); self.base = base; self.span = span; local = 0; lock.unlock()
    }

    func set(local: Double, label: String? = nil) {
        lock.lock()
        self.local = min(1, max(0, local))
        if let label { self.label = label }
        lock.unlock()
    }

    func snapshot() -> (files: Int, current: String, fraction: Double, label: String) {
        lock.lock(); defer { lock.unlock() }
        return (files, current, min(1, base + span * local), label)
    }
}
