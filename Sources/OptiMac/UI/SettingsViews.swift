import SwiftUI
import AppKit
import Combine

// MARK: - Paramètres

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var updater: Updater
    @Environment(\.palette) private var p
    @State private var key = ""
    @State private var legal: LegalDoc?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionTitle(title: "Paramètres").appear(0)

                // Licence
                GlassCard(tint: Palette.accent) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            IconBubble(symbol: "crown.fill", color: Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Strong(license.statusLabel, size: 16)
                                if let e = license.expiresAt, license.isPremium {
                                    Muted("Valable jusqu'au \(Fmt.date(e))\(license.keyPrefix.map { " · clé \($0)…" } ?? "")")
                                } else {
                                    Muted("Activez Premium avec votre clé de licence SecureeTech (ST-XXXX-XXXX-XXXX).")
                                }
                            }
                            Spacer()
                            if license.isPremium && !license.isTrial {
                                Button("Libérer ce Mac") {
                                    if Confirm.ask("Libérer ce Mac ?", "La licence pourra être utilisée sur un autre ordinateur. Ce Mac repassera en version gratuite.", ok: "Libérer") {
                                        Task { await license.deactivate() }
                                    }
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                        }
                        if !license.isPremium || license.isTrial {
                            HStack(spacing: 8) {
                                TextField("ST-XXXX-XXXX-XXXX", text: $key)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(GlassBackground(radius: 12))
                                Button(license.busy ? "Activation…" : "Activer") {
                                    Task { if await license.activate(key: key) { key = "" } }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(key.count < 8 || license.busy)
                                Button("Acheter") { Links.open(Links.premium) }.buttonStyle(GlassButtonStyle())
                            }
                        }
                        if let m = license.message { Muted(m) }
                        if let w = license.warning { Tag(text: w, color: Palette.warning) }
                    }
                }
                .appear(1)

                // Apparence
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Strong("Apparence")
                        row("Thème") {
                            Picker("", selection: $settings.appearance) {
                                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 280)
                        }
                        row("Taille du texte") {
                            Picker("", selection: $settings.textSize) {
                                ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 280)
                        }
                    }
                }
                .appear(2)

                // Démarrage et automatisme
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Strong("Démarrage et automatismes")
                        toggle("Lancer OptiMac à l'ouverture de session", $settings.launchAtLogin)
                        toggle("Ouvrir la fenêtre au démarrage du Mac", $settings.openWindowAtLogin)
                        toggle("Vérification de sécurité chaque semaine", $settings.weeklyCheck)
                        row("Nettoyage automatique") {
                            HStack(spacing: 6) {
                                if !license.isPremium { PremiumTag() }
                                Picker("", selection: Binding(get: { settings.autoClean }, set: { v in
                                    if v != .off && model.needsPremium(.autoClean) { return }
                                    settings.autoClean = v
                                })) {
                                    ForEach(AutoClean.allCases) { Text($0.label).tag($0) }
                                }
                                .frame(width: 180)
                            }
                        }
                    }
                }
                .appear(3)

                // Notifications
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Strong("Notifications")
                        toggle("Fin d'un nettoyage", $settings.notifCleanDone)
                        toggle("Fin d'une analyse", $settings.notifScanDone)
                        toggle("Menaces détectées", $settings.notifThreats)
                        toggle("Conseils au démarrage", $settings.notifStartup)
                        toggle("Rappels sur ce qui peut être nettoyé (Premium)", $settings.notifPremium)
                    }
                }
                .appear(4)

                // Accès complet au disque
                GlassCard(tint: Permissions.hasFullDiskAccess ? Palette.success : Palette.warning) {
                    HStack(spacing: 12) {
                        IconBubble(symbol: Permissions.hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                                   color: Permissions.hasFullDiskAccess ? Palette.success : Palette.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Strong("Accès complet au disque")
                            Muted(Permissions.hasFullDiskAccess ? "Autorisé : OptiMac peut nettoyer et protéger tout le Mac."
                                  : "Non autorisé : certains dossiers (Mail, Safari, messages) ne peuvent pas être nettoyés.")
                        }
                        Spacer()
                        if !Permissions.hasFullDiskAccess {
                            Button("Autoriser") { Links.open(Links.fullDiskAccess) }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .appear(5)

                // Mise à jour + à propos
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Logo(size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Strong("OptiMac \(SystemInfo.appVersion)", size: 15)
                                Muted("Édité par H2OCONSULTING - FZCO · Dubaï, Émirats arabes unis")
                            }
                            Spacer()
                            if let v = updater.latest, let u = updater.url {
                                Button("Installer la version \(v)") { Links.open(u) }.buttonStyle(PrimaryButtonStyle())
                            } else {
                                Button("Rechercher une mise à jour") {
                                    Task {
                                        await updater.check()
                                        if updater.latest == nil { model.notify("OptiMac est à jour") }
                                    }
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                        }
                        HStack(spacing: 8) {
                            Button("Conditions d'utilisation") { legal = .cgu }.buttonStyle(GlassButtonStyle())
                            Button("Contrat de licence") { legal = .eula }.buttonStyle(GlassButtonStyle())
                            Button("Confidentialité") { legal = .privacy }.buttonStyle(GlassButtonStyle())
                            Button("Mentions légales") { legal = .mentions }.buttonStyle(GlassButtonStyle())
                        }
                        HStack(spacing: 14) {
                            Muted("Assistance : \(Links.support) · \(Links.email)")
                            Spacer()
                            Button("Ouvrir le journal d'erreurs") {
                                NSWorkspace.shared.open(FS.lib("Logs/OptiMac"))
                            }
                            .buttonStyle(PlainHover())
                            .font(.system(size: 11.5))
                            .foregroundColor(p.muted)
                        }
                    }
                }
                .appear(6)
            }
            .padding(26)
        }
        .sheet(item: $legal) { doc in LegalSheet(doc: doc) }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundColor(p.text)
            Spacer()
            c()
        }
    }

    private func toggle(_ title: String, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: b) {
            Text(title).font(.system(size: 13)).foregroundColor(p.text)
        }
        .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
    }
}

// MARK: - Mentions légales

enum LegalDoc: String, Identifiable {
    case cgu, eula, privacy, mentions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cgu: return "Conditions générales d'utilisation"
        case .eula: return "Contrat de licence"
        case .privacy: return "Politique de confidentialité"
        case .mentions: return "Mentions légales"
        }
    }
    var text: String {
        let editor = "H2OCONSULTING - FZCO, Dubaï, Émirats arabes unis"
        switch self {
        case .mentions:
            return """
            OptiMac est édité par \(editor).
            Marque : SecureeTech — secureetech.com
            Contact : \(Links.email) — \(Links.support) (du lundi au vendredi, de 10 h à 17 h).
            """
        case .cgu:
            return """
            1. Objet. OptiMac est un logiciel de nettoyage, d'optimisation et de protection pour Mac, édité par \(editor).
            2. Version gratuite. La version gratuite permet d'analyser le Mac, de nettoyer jusqu'à 500 Mo par opération et de détecter les menaces. Certaines fonctions sont réservées à la version Premium.
            3. Version Premium. La version Premium est accessible par abonnement ou par une clé de licence SecureeTech. Un essai gratuit de 5 jours est proposé au premier lancement.
            4. Précautions. OptiMac ne supprime jamais vos documents personnels sans votre confirmation. Les éléments supprimés par l'Espace disque passent par la corbeille. Une sauvegarde régulière de vos données reste recommandée.
            5. Responsabilité. Le logiciel est fourni en l'état. L'éditeur ne pourra être tenu responsable d'une perte de données résultant d'une utilisation non conforme.
            6. Droit applicable. Les présentes conditions sont régies par le droit des Émirats arabes unis, sous réserve des dispositions impératives applicables au consommateur dans son pays de résidence.
            """
        case .eula:
            return """
            \(editor) vous accorde une licence personnelle, non exclusive et non transférable d'utilisation d'OptiMac.
            Une licence Premium est valable pour le nombre de Mac indiqué lors de l'achat. Vous pouvez libérer un Mac dans les Paramètres pour utiliser la licence sur un autre.
            Il est interdit de décompiler, modifier, revendre ou redistribuer le logiciel.
            La licence prend fin automatiquement en cas de non-respect de ces conditions.
            """
        case .privacy:
            return """
            OptiMac analyse votre Mac localement : le contenu de vos fichiers n'est jamais envoyé.
            Pour la licence et les mises à jour, OptiMac envoie au serveur SecureeTech (api.secureetech.com) un identifiant anonyme de ce Mac, son nom, la version de macOS et la version d'OptiMac.
            En cas d'erreur, un rapport technique (sans donnée personnelle) peut être envoyé pour améliorer le logiciel.
            Si vous demandez à être rappelé, votre prénom et votre numéro de téléphone sont transmis à SecureeTech uniquement pour vous rappeler.
            Pour toute question ou suppression de vos données : \(Links.email).
            """
        }
    }
}

struct LegalSheet: View {
    @Environment(\.presentationMode) private var presentation
    let doc: LegalDoc
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(doc.title).font(.system(size: 20, weight: .bold, design: .rounded))
            ScrollView {
                Text(doc.text).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Fermer") { presentation.wrappedValue.dismiss() }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(26)
        .frame(width: 620, height: 480)
    }
}

// MARK: - Offre Premium

struct PremiumSheet: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    @State private var key = ""

    private let perks: [(String, String)] = [
        ("trash.fill", "Nettoyage complet, sans limite de 500 Mo"),
        ("shield.lefthalf.fill", "Suppression et quarantaine des menaces"),
        ("globe", "Réparation des navigateurs détournés en un clic"),
        ("bolt.fill", "Suppression forcée des logiciels récalcitrants"),
        ("chart.pie.fill", "100 % des résultats : doublons, gros fichiers, photos"),
        ("clock.fill", "Nettoyage automatique et maintenance avancée"),
        ("phone.fill", "Assistance prioritaire SecureeTech")
    ]

    var body: some View {
        Modal(width: 600, onClose: { model.showPremium = false }) {
            VStack(spacing: 18) {
                Logo(size: 64)
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("OptiMac").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        PremiumTag().scaleEffect(1.3)
                    }
                    if let f = model.premiumFeature {
                        Text("« \(f.title) » fait partie de Premium.").font(.system(size: 14, weight: .semibold)).foregroundColor(Palette.accent)
                    } else {
                        Muted("Débloquez toute la puissance d'OptiMac.", size: 14)
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(0..<perks.count, id: \.self) { i in
                        let perk = perks[i]
                        HStack(spacing: 10) {
                            Image(systemName: perk.0).foregroundColor(Palette.accent).frame(width: 22)
                            Text(perk.1).font(.system(size: 13.5, weight: .medium)).foregroundColor(p.text)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(GlassBackground(radius: 18))

                HStack(spacing: 10) {
                    priceBox("1 mois", "6,90 €", nil)
                    priceBox("1 an", "49,90 €", "Le plus choisi")
                    priceBox("2 ans", "89,90 €", nil)
                }

                Button(action: { Links.open(Links.premium) }) {
                    HStack(spacing: 8) { Image(systemName: "crown.fill"); Text("Passer à Premium") }
                }
                .buttonStyle(PrimaryButtonStyle(large: true))

                HStack(spacing: 8) {
                    TextField("Vous avez une clé ? ST-XXXX-XXXX-XXXX", text: $key)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(GlassBackground(radius: 12))
                    Button(license.busy ? "…" : "Activer") {
                        Task {
                            if await license.activate(key: key) {
                                key = ""
                                model.showPremium = false
                                model.notify("Premium activé. Merci !")
                            }
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .disabled(key.count < 8 || license.busy)
                }
                if let m = license.message { Muted(m, size: 12).multilineTextAlignment(.center) }
                Muted("Une question ? Appelez le \(Links.support) (du lundi au vendredi, de 10 h à 17 h).", size: 11.5)
            }
        }
    }

    private func priceBox(_ period: String, _ price: String, _ badge: String?) -> some View {
        VStack(spacing: 4) {
            if let badge { Tag(text: badge) } else { Tag(text: " ", color: .clear) }
            Text(price).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(p.text)
            Muted(period)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(GlassBackground(radius: 16, tint: badge == nil ? nil : Palette.accent))
    }
}

// MARK: - Rappel par un technicien

struct CallbackSheet: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    @State private var name = ""
    @State private var phone = ""
    @State private var subject = "Mon Mac est lent"
    @State private var sending = false
    @State private var result: (Bool, String)?

    private let subjects = ["Mon Mac est lent", "Virus ou publicités", "Navigateur détourné", "Problème d'imprimante", "Problème de messagerie", "Autre"]

    var body: some View {
        Modal(width: 480, onClose: { model.showCallback = false }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconBubble(symbol: "phone.fill", color: Color(hex: 0x14B8A6), size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Être rappelé").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                        Muted("Un technicien SecureeTech vous rappelle (du lundi au vendredi, de 10 h à 17 h).")
                    }
                }
                field("Prénom", $name)
                field("Téléphone", $phone)
                Picker("Sujet", selection: $subject) {
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }
                if let r = result {
                    HStack(spacing: 8) {
                        Image(systemName: r.0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundColor(r.0 ? Palette.success : Palette.warning)
                        Muted(r.1)
                    }
                }
                HStack {
                    Spacer()
                    Button(sending ? "Envoi…" : "Envoyer la demande") {
                        sending = true
                        Task {
                            result = await Callback.send(firstName: name, phone: phone, subject: subject, premium: license.isPremium)
                            sending = false
                            if result?.0 == true {
                                model.log("Demande de rappel envoyée")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { model.showCallback = false }
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phone.filter(\.isNumber).count < 9 || sending)
                }
            }
        }
    }

    private func field(_ title: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Muted(title, size: 11.5)
            TextField(title, text: b)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(GlassBackground(radius: 12))
        }
    }
}

// MARK: - Premier lancement

struct WelcomeSheet: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var license: LicenseManager
    @Environment(\.palette) private var p
    @State private var step = 0
    @State private var accepted = false
    @State private var hasAccess = Permissions.hasFullDiskAccess
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Modal(width: 560) {
            VStack(spacing: 18) {
                if step == 0 {
                    Logo(size: 80)
                    Text("Bienvenue dans OptiMac").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                    Muted("Nettoyage, protection et optimisation de votre Mac, par SecureeTech.", size: 14).multilineTextAlignment(.center)
                    if license.isTrial {
                        Tag(text: "Essai Premium offert : 5 jours", color: Palette.accent).scaleEffect(1.2)
                    }
                    Toggle(isOn: $accepted) {
                        Text("J'accepte les conditions d'utilisation et le contrat de licence").font(.system(size: 12.5)).foregroundColor(p.text)
                    }
                    Button("Continuer") {
                        settings.consentAccepted = true
                        withAnimation(.spring()) { step = 1 }
                    }
                    .buttonStyle(PrimaryButtonStyle(large: true))
                    .disabled(!accepted)
                    .opacity(accepted ? 1 : 0.5)
                } else {
                    IconBubble(symbol: hasAccess ? "checkmark.shield.fill" : "lock.shield.fill", color: hasAccess ? Palette.success : Palette.accent, size: 70)
                    Text("Autorisez l'accès complet au disque").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(p.text)
                    VStack(alignment: .leading, spacing: 8) {
                        stepLine(1, "Cliquez sur « Ouvrir les réglages » ci-dessous.")
                        stepLine(2, "Cliquez sur le cadenas en bas à gauche et tapez votre mot de passe.")
                        stepLine(3, "Cochez « OptiMac » dans la liste (ou ajoutez-le avec le bouton +).")
                        stepLine(4, "Revenez ici : OptiMac le détecte tout seul.")
                    }
                    .padding(14)
                    .background(GlassBackground(radius: 16))
                    HStack(spacing: 10) {
                        if hasAccess {
                            Button("C'est parti !") { settings.welcomeShown = true }.buttonStyle(PrimaryButtonStyle(large: true))
                        } else {
                            Button("Ouvrir les réglages") { Links.open(Links.fullDiskAccess) }.buttonStyle(PrimaryButtonStyle(large: true))
                            Button("Plus tard") { settings.welcomeShown = true }.buttonStyle(GlassButtonStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onReceive(timer) { _ in
            if step == 1 { hasAccess = Permissions.hasFullDiskAccess }
        }
    }

    private func stepLine(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Palette.accent))
            Text(t).font(.system(size: 13)).foregroundColor(p.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
