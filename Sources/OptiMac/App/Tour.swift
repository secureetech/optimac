import AppKit
import SwiftUI

/// Visite automatique de l'interface avec captures d'écran (pour voir OptiMac sans Mac).
/// Lancée par la compilation GitHub : OptiMac --tour <dossier>
extension AppDelegate {
    func runTour(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settings.welcomeShown = true
        settings.appearance = .light
        settings.applyAppearance()
        showWindow()
        window?.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 820), display: true)

        Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            func shot(_ name: String) async {
                await wait(1.6)
                self.capture(to: dir.appendingPathComponent(name + ".png"))
            }

            await wait(2.5)
            await shot("01-accueil")
            model.startScan()
            await wait(3)
            await shot("02-analyse-en-cours")
            for _ in 0..<60 where model.phase == .scanning { await wait(1) }
            await shot("03-resultats")

            let screens: [(Section, String)] = [(.clean, "04-nettoyage"), (.space, "05-espace-disque"), (.protect, "06-protection"),
                                                (.apps, "07-applications"), (.network, "08-reseau"), (.health, "09-sante"),
                                                (.tools, "10-outils"), (.settings, "11-parametres")]
            for (sec, name) in screens {
                model.section = sec
                await wait(sec == .space ? 8 : 3)
                await shot(name)
            }

            model.section = .home
            model.premiumFeature = .unlimitedCleanup
            model.showPremium = true
            await shot("12-offre-premium")
            model.showPremium = false

            settings.appearance = .dark
            settings.applyAppearance()
            model.section = .home
            await wait(1)
            await shot("13-accueil-sombre")
            model.section = .protect
            await shot("14-protection-sombre")
            NSApp.terminate(nil)
        }
    }

    func capture(to url: URL) {
        guard let w = window else { return }
        var cg: CGImage?
        cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution])
        let rep: NSBitmapImageRep
        if let cg {
            rep = NSBitmapImageRep(cgImage: cg)
        } else if let v = w.contentView, let r = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: r)
            rep = r
        } else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
