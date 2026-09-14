import SwiftUI

// MARK: - Tab definition

enum AppTab: String, CaseIterable {
    case weather     = "weather"
    case horaire     = "horaire"
    case carte       = "carte"
    case sport       = "sport"
    case profile     = "profile"
    case whatsNew    = "whatsNew"
    case suggestions = "suggestions"

    /// Ceux qui ont leur place dans la barre. Les autres restent
    /// accessibles par le menu « Plus » : sept onglets côte à côte, c'est
    /// trop pour être lisible, et Nouveautés/Suggestions se consultent
    /// rarement.
    static let principaux: [AppTab] = [.weather, .horaire, .carte, .sport, .profile]
    static let secondaires: [AppTab] = [.whatsNew, .suggestions]

    var icon: String {
        switch self {
        case .weather:     return "cloud.sun.fill"
        case .horaire:     return "clock.fill"
        case .carte:       return "map.fill"
        case .sport:       return "figure.run"
        case .profile:     return "person.crop.circle.fill"
        case .whatsNew:    return "sparkles"
        case .suggestions: return "lightbulb.fill"
        }
    }

    var label: String {
        switch self {
        case .weather:     return "Météo"
        case .horaire:     return "Heures"
        case .carte:       return "Carte"
        case .sport:       return "Sport"
        case .profile:     return "Profil"
        case .whatsNew:    return "Nouveautés"
        case .suggestions: return "Suggestions"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {

    /// Le modèle appartient désormais à l'App et non à cette vue :
    /// la barre de menus doit lire les mêmes données.
    @ObservedObject var vm: WeatherViewModel
    @StateObject private var accountStore = UserAccountStore.shared
    @State private var selectedTab: AppTab = .weather
    @State private var showWhatsNew: Bool = false
    @State private var showOnboarding: Bool = false

    /// La barre se rétracte quand on fait défiler vers le bas et revient
    /// dès qu'on remonte — comme Safari sur iPhone.
    @State private var barreVisible = true
    @State private var dernierOffset: CGFloat = 0

    /// La bulle de sélection est UNE seule vue qui se déplace, pas un
    /// fond par onglet. `matchedGeometryEffect` anime son trajet quand
    /// elle change de place ; le Namespace identifie « la même bulle »
    /// d'un onglet à l'autre.
    @Namespace private var espaceBulle

    /// Élément survolé par la souris, s'il y en a un.
    @State private var survol: PositionBulle? = nil

    private enum PositionBulle: Hashable {
        case onglet(AppTab)
        case plus
    }

    /// Où doit être la bulle : sous la souris si elle survole quelque
    /// chose, sinon sous l'onglet sélectionné.
    private var positionBulle: PositionBulle {
        if let survol { return survol }
        return AppTab.secondaires.contains(selectedTab) ? .plus : .onglet(selectedTab)
    }

    private var positionSelection: PositionBulle {
        AppTab.secondaires.contains(selectedTab) ? .plus : .onglet(selectedTab)
    }
    @AppStorage("appearanceMode") private var appearanceMode: String = "dark"

    /// Thème réellement appliqué à la fenêtre. Suit `preferredColorScheme`,
    /// donc aussi le choix « Système ».
    @Environment(\.colorScheme) private var schemaCouleur
    @Environment(\.accessibilityReduceMotion) private var reduitAnimations
    @Environment(\.controlActiveState) private var etatFenetre

    /// La nuit, le ciel est sombre quel que soit le thème : on force la
    /// palette sombre (texte blanc), sinon le thème clair écrivait en noir
    /// sur du noir — vu au banc d'essai, illisible.
    private var schemaEffectif: ColorScheme {
        vm.phaseSolaire.estNuit ? .dark : schemaCouleur
    }

    var body: some View {
        ZStack {
            // MARK: Background
            backgroundLayer
            readabilityScrim

            // MARK: Main content
            ZStack(alignment: .bottom) {
                ZStack {
                    switch selectedTab {
                    case .weather:
                        WeatherTabView(vm: vm)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                                removal:   .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96))
                            ))
                    case .horaire:
                        HoraireTabView(vm: vm)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal:   .scale(scale: 1.06).combined(with: .opacity)
                            ))
                    case .carte:
                        CarteTabView(vm: vm)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal:   .scale(scale: 1.06).combined(with: .opacity)
                            ))
                    case .sport:
                        SportTabView(vm: vm)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal:   .scale(scale: 1.06).combined(with: .opacity)
                            ))
                    case .profile:
                        SportProfileView(vm: vm)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal:   .scale(scale: 1.06).combined(with: .opacity)
                            ))
                    case .whatsNew:
                        WhatsNewTabView()
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal:   .scale(scale: 1.06).combined(with: .opacity)
                            ))
                    case .suggestions:
                        SuggestionsTabView()
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal:   .scale(scale: 1.06).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.spring(duration: 0.45, bounce: 0.15), value: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Réserve la hauteur de la barre en bas des listes, pour
                // que la dernière carte puisse défiler au-dessus d'elle
                // — sans ça, elle resterait à moitié cachée.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 74)
                }

                // MARK: Barre flottante
                barreFlottante
                    .padding(.bottom, 18)
                    // Cachée : elle glisse sous le bord et s'efface. Un
                    // simple `opacity` la laisserait bloquer les clics.
                    .offset(y: barreVisible ? 0 : 130)
                    .opacity(barreVisible ? 1 : 0)
                    .allowsHitTesting(barreVisible)
            }
            .environment(\.colorScheme, schemaEffectif)
            .onPreferenceChange(OffsetDefilementKey.self) { offset in
                if let offset { reagirAuDefilement(offset) }
            }
            .onChange(of: selectedTab) { _, _ in
                // Nouvel onglet = nouvelle liste, toujours en haut :
                // la barre doit être là pour qu'on puisse en changer.
                dernierOffset = 0
                withAnimation(.spring(duration: 0.3)) { barreVisible = true }
            }

            // MARK: Popup "Quoi de neuf"
            if showWhatsNew, let version = VersionHistory.current {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { withAnimation(.spring(duration: 0.4)) { showWhatsNew = false } }
                WhatsNewPopup(version: version) {
                    withAnimation(.spring(duration: 0.4, bounce: 0.2)) { showWhatsNew = false }
                }
                .zIndex(1000)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }

            // MARK: Onboarding overlay (macOS — pas de fullScreenCover)
            if showOnboarding {
                OnboardingView {
                    withAnimation(.spring(duration: 0.6, bounce: 0.15)) { showOnboarding = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if !VersionHistory.hasSeenCurrentVersion {
                            withAnimation(.spring(duration: 0.5)) { showWhatsNew = true }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2000)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .onAppear {
            // On remet la dernière météo connue à l'écran avant même de
            // lancer la requête : mieux vaut une valeur d'il y a une heure,
            // signalée comme telle, qu'un spinner vide.
            vm.restaurerApercu()
            vm.fetchWeather()
            if !accountStore.isOnboarded {
                showOnboarding = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !VersionHistory.hasSeenCurrentVersion && accountStore.isOnboarded {
                    withAnimation { showWhatsNew = true }
                }
            }
        }
    }

    // MARK: - Tab bar

    /// Version « compacte » (maquette B) : icônes seules, et l'onglet actif
    /// s'étire pour montrer son nom — on sait toujours où l'on est sans
    /// afficher six étiquettes. Les autres noms arrivent au survol
    /// (`.help`). 50 pt de haut au lieu de 64 : la grille respire.
    private var barreFlottante: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.principaux, id: \.self) { tab in
                tabBarItem(tab)
            }

            Divider()
                .background(Color.surface.opacity(0.2))
                .frame(height: 22)
                .padding(.horizontal, 3)

            menuPlus
        }
        .padding(5)
        // Deux fonds superposés : le matériau pour le flou, un voile
        // dans la couleur inverse du texte pour garantir le contraste
        // quel que soit ce qui passe derrière.
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.texteInverse.opacity(0.22), in: Capsule())
        .overlay(Capsule().stroke(Color.surface.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 10)
    }

    /// Les onglets secondaires et le thème, regroupés.
    /// Quand un onglet secondaire est actif, le bouton prend son icône et
    /// son nom : on voit toujours où l'on est.
    private var menuPlus: some View {
        let secondaireActif = AppTab.secondaires.contains(selectedTab)
        return Menu {
            Section {
                ForEach(AppTab.secondaires, id: \.self) { tab in
                    Button { selectionner(tab) } label: {
                        Label(tab.label, systemImage: tab.icon)
                    }
                }
            }
            Section("Thème") {
                Button { withAnimation { appearanceMode = "dark" } } label: {
                    Label("Sombre", systemImage: "moon.fill")
                }
                Button { withAnimation { appearanceMode = "light" } } label: {
                    Label("Clair", systemImage: "sun.max.fill")
                }
                Button { withAnimation { appearanceMode = "system" } } label: {
                    Label("Système", systemImage: "circle.lefthalf.filled")
                }
            }
            // Mode démo : forcer une météo pour tester l'interface. Un
            // Picker dans un Menu devient un sous-menu à coche sur macOS.
            Section("Mode démo") {
                Picker(selection: $vm.simulation.condition) {
                    Text("Météo réelle").tag(Simulation.Condition?.none)
                    Divider()
                    ForEach(Simulation.Condition.ordinaires) { c in
                        Label(c.libelle, systemImage: c.icone).tag(Optional(c))
                    }
                    Divider()
                    ForEach(Simulation.Condition.extremes) { c in
                        Label(c.libelle, systemImage: c.icone).tag(Optional(c))
                    }
                } label: { Label("Condition", systemImage: "cloud.sun") }
                Picker(selection: $vm.simulation.moment) {
                    Text("Heure réelle").tag(Simulation.Moment?.none)
                    Divider()
                    ForEach(Simulation.Moment.allCases) { m in
                        Label(m.libelle, systemImage: m.icone).tag(Optional(m))
                    }
                } label: { Label("Moment", systemImage: "clock") }
                Toggle(isOn: $vm.simulation.alerte) { Label("Alerte fictive", systemImage: "exclamationmark.triangle") }
                if vm.simulation.estActive {
                    Button { withAnimation { vm.simulation = Simulation() } } label: {
                        Label("Arrêter la simulation", systemImage: "xmark.circle")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: secondaireActif ? selectedTab.icon : "ellipsis")
                    .font(.system(size: secondaireActif ? 19 : 17, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        secondaireActif ? Color.texte : Color.texte.opacity(0.5),
                        secondaireActif ? Color.cyan  : Color.texte.opacity(0.25)
                    )
                if secondaireActif {
                    Text(selectedTab.label)
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.texte)
                        .fixedSize().transition(.opacity)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(.texte.opacity(0.4))
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background {
                if positionBulle == .plus { bulle }
            }
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .help("Plus d'onglets et thème")
        .onHover { dedans in survoler(dedans ? .plus : nil) }
        .accessibilityLabel(secondaireActif ? selectedTab.label : "Plus d'onglets et thème")
    }

    /// Le sens du défilement se lit dans la variation de position du
    /// haut du contenu : il diminue quand on descend, augmente quand on
    /// remonte.
    private func reagirAuDefilement(_ offset: CGFloat) {
        defer { dernierOffset = offset }
        let delta = offset - dernierOffset

        // Un saut de plusieurs centaines de points n'est pas un
        // défilement : c'est un changement d'onglet ou une remise en
        // page. On l'ignore plutôt que d'y réagir.
        guard abs(delta) < 200 else { return }

        // Seuil : en dessous, c'est le rebond en fin de liste ou un
        // tremblement de trackpad, pas une intention.
        guard abs(delta) > 6 else { return }

        let versLeBas = delta < 0
        guard barreVisible == versLeBas else { return }   // déjà dans le bon état
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
            barreVisible = !versLeBas
        }
    }

    /// Fond gris toujours ; halo cyan seulement quand la bulle repose sur
    /// l'onglet réellement sélectionné — en survol d'un autre onglet, le
    /// halo disparaît pour ne pas laisser croire qu'on a changé de page.
    private var bulle: some View {
        ZStack {
            Capsule()
                .fill(Color.surface.opacity(0.12))
            if positionBulle == positionSelection {
                Capsule()
                    .fill(Color.cyan.opacity(0.06))
                    .blur(radius: 6)
            }
        }
        .matchedGeometryEffect(id: "bulle", in: espaceBulle)
    }

    private func survoler(_ position: PositionBulle?) {
        withAnimation(.spring(duration: 0.38, bounce: 0.22)) { survol = position }
    }

    private func selectionner(_ tab: AppTab) {
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { selectedTab = tab }
    }

    private func tabBarItem(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isSelected ? Color.texte : Color.texte.opacity(0.5),
                        isSelected ? Color.cyan   : Color.texte.opacity(0.25)
                    )
                    .shadow(color: isSelected ? .cyan.opacity(0.5) : .clear, radius: 8, x: 0, y: 2)
                    .animation(.spring(duration: 0.4, bounce: 0.5), value: isSelected)

                // Le nom n'existe que sur l'onglet actif : l'HStack s'élargit
                // et se resserre avec l'animation de sélection.
                if isSelected {
                    Text(tab.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.texte)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.leading, isSelected ? 12 : 10)
            .padding(.trailing, isSelected ? 14 : 10)
            .frame(height: 40)
            .background {
                // La bulle n'existe qu'à UN endroit à la fois : c'est ce
                // qui permet à matchedGeometryEffect de l'animer d'un
                // onglet à l'autre au lieu d'en faire apparaître une neuve.
                if positionBulle == .onglet(tab) { bulle }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.label)
        .onHover { dedans in survoler(dedans ? .onglet(tab) : nil) }
    }

    // MARK: - Voile de lisibilité

    /// Assombrit progressivement le fond vers le bas — là où les dégradés
    /// météo sont les plus clairs, et là où se trouve la barre d'onglets.
    /// Remplace l'ancien voile uniforme à 6 %, qui ne suffisait pas :
    /// par beau temps le texte blanc tombait à 2,82:1 (seuil AA = 4,5:1).
    private var readabilityScrim: some View {
        LinearGradient(
            colors: schemaEffectif == .dark
                ? [Color.black.opacity(0.06), Color.black.opacity(0.30)]
                : [Color.white.opacity(0.00), Color.white.opacity(0.18)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)   // décoratif : ne doit jamais capter un clic
        .accessibilityHidden(true) // …ni encombrer la lecture VoiceOver
    }

    // MARK: - Fond dégradé dynamique

    /// Le ciel. Sur un Mac avec Metal (tous), c'est la couche GPU
    /// `CielMetal` : le dégradé, et toutes les intempéries — ordinaires,
    /// extrêmes, éclairs compris — calculées pixel par pixel. Le dégradé
    /// SwiftUI ne sert plus que de repli, immobile.
    @ViewBuilder private var backgroundLayer: some View {
        if CielMetal.disponible {
            let rgb = skyRGB(for: vm.backgroundConditionKey)
            let phase = vm.phaseSolaire
            // Averse : du débit (≥ 4 mm/h) ou un code WMO d'averse (80–82, 65)
            let mm = vm.state.precipitationMm
            let averse = mm >= 4 || [65, 81, 82].contains(vm.state.weatherCode)
            let cle = vm.backgroundConditionKey
            let intensite: Float = cle == "drizzle" ? 0.45
                                 : cle == "rain" && !averse ? Float(0.55 + min(mm, 3) / 8)   // 0,55 → 0,93
                                 : 1
            // Le vent : la force donne l'inclinaison (0,15 → 0,65), la direction
            // donne le sens. `windDirection` est la direction D'OÙ vient le vent
            // (convention météo) : un vent d'est (90°) pousse vers l'ouest, donc
            // vers la gauche de l'écran — c'est le sens positif du shader ;
            // un vent d'ouest (270°) penche tout vers la droite. Nord ou sud :
            // presque droit, comme dans la réalité.
            let direction = Double(vm.state.windDirection) * .pi / 180
            let vent = Float(sin(direction) * (0.15 + min(vm.state.windSpeed, 60) / 120))
            CielMetal(haut: rgb[0], bas: rgb[1],
                      condition: ConditionMetal.depuis(cle: cle, estNuit: phase.estNuit, averse: averse),
                      intensite: intensite,
                      encreSombre: schemaEffectif == .light,
                      vent: vent,
                      // D'est en ouest, plus haut à midi. Le sommet est à 17 % de la
                      // hauteur : le disque (8 %) passe sous le champ de recherche
                      // au lieu de se cacher derrière.
                      soleil: [Float(0.12 + phase.progression * 0.76), Float(0.80 - phase.elevation * 0.63)],
                      elevation: Float(phase.elevation),
                      crepuscule: Float(phase.teinteCrepusculaire),
                      eclat: eclatSoleil(progression: phase.progression),
                      anime: !reduitAnimations && etatFenetre != .inactive)
                .ignoresSafeArea()
        } else {
            LinearGradient(
                gradient: Gradient(colors: skyColors(for: vm.backgroundConditionKey)),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.spring(duration: 2.0, bounce: 0.0), value: vm.backgroundConditionKey)
        }
    }

    /// Couleurs du ciel : la météo donne la teinte, l'heure donne la
    /// luminosité. Les valeurs sont manipulées en RGB brut plutôt qu'en
    /// `Color`, parce que SwiftUI ne sait pas mélanger deux `Color`.
    private typealias RGB = (r: Double, g: Double, b: Double)

    private func skyColors(for key: String) -> [Color] {
        skyRGB(for: key).map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    /// Les deux couleurs du ciel en RGB brut — c'est ce que reçoit le GPU.
    private func skyRGB(for key: String) -> [RGB] {
        let jour = schemaCouleur == .dark ? cielSombre(key) : cielClair(key)
        let nuit = cielNuit(key)
        let phase = vm.phaseSolaire

        // Transition nuit → jour entre une élévation de −0,15 et +0,25 :
        // le ciel s'éclaircit un peu avant que le soleil ne passe l'horizon,
        // comme dans la réalité.
        let t = min(max((phase.elevation + 0.15) / 0.40, 0), 1)
        var couleurs = zip(nuit, jour).map { melange($0, $1, t) }

        // Braise du lever et du coucher, plus marquée en bas de l'écran
        // — c'est près de l'horizon que le ciel s'embrase.
        let feu = phase.teinteCrepusculaire
        if feu > 0.02 {
            let braise: [RGB] = [(0.30, 0.16, 0.34), (0.78, 0.36, 0.24)]
            couleurs = couleurs.enumerated().map { i, c in
                melange(c, braise[i], feu * (i == 0 ? 0.45 : 0.70))
            }
        }
        return couleurs
    }

    /// L'éclat du soleil au fil de la journée, tel que Mathis l'a réglé
    /// sur la maquette : 0,20 le matin, 0,25 à midi, 0,30 l'après-midi,
    /// 0,20 au coucher. Interpolé entre ces quatre points sur la
    /// progression du soleil (0 = lever, 1 = coucher).
    private func eclatSoleil(progression p: Double) -> Float {
        let points: [(Double, Double)] = [(0.18, 0.20), (0.50, 0.25), (0.74, 0.30), (0.97, 0.20)]
        if p <= points[0].0 { return Float(points[0].1) }
        for i in 1..<points.count where p <= points[i].0 {
            let (p0, e0) = points[i - 1], (p1, e1) = points[i]
            return Float(e0 + (e1 - e0) * (p - p0) / (p1 - p0))
        }
        return Float(points.last!.1)
    }

    /// Interpolation linéaire entre deux couleurs.
    private func melange(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    /// Ciels de nuit. Sombres par construction : le texte blanc y ressort
    /// à 15:1 ou mieux, mesuré.
    private func cielNuit(_ key: String) -> [RGB] {
        switch key {
        case "rain":    return [(0.06,0.07,0.12), (0.10,0.11,0.17)]
        case "drizzle": return [(0.08,0.09,0.15), (0.12,0.13,0.20)]
        case "thunder": return [(0.05,0.03,0.11), (0.02,0.01,0.05)]
        case "snow":    return [(0.12,0.15,0.24), (0.20,0.24,0.34)]
        case "clear":   return [(0.02,0.04,0.13), (0.06,0.09,0.22)]
        case "cloud":   return [(0.10,0.12,0.20), (0.16,0.18,0.28)]
        case "fog":     return [(0.11,0.12,0.14), (0.17,0.18,0.20)]
        // Régimes extrêmes
        case "tornado": return [(0.06,0.06,0.05), (0.02,0.02,0.02)]
        case "storm":   return [(0.05,0.06,0.10), (0.08,0.09,0.13)]
        case "hail":    return [(0.08,0.09,0.13), (0.12,0.13,0.18)]
        case "heat":    return [(0.16,0.06,0.10), (0.28,0.10,0.08)]
        case "cold":    return [(0.03,0.07,0.18), (0.08,0.14,0.28)]
        case "dust":    return [(0.14,0.10,0.05), (0.20,0.14,0.07)]
        case "cyclone": return [(0.03,0.05,0.07), (0.01,0.02,0.03)]
        case "blizzard": return [(0.12,0.14,0.20), (0.20,0.22,0.30)]
        case "sleet":   return [(0.05,0.08,0.14), (0.08,0.12,0.20)]
        case "deluge":  return [(0.04,0.06,0.10), (0.06,0.08,0.13)]
        default:        return [(0.03,0.05,0.14), (0.02,0.03,0.09)]
        }
    }

    /// Ciels du mode clair, de jour.
    private func cielClair(_ key: String) -> [RGB] {
        switch key {
        case "rain":    return [(0.52,0.58,0.66), (0.78,0.82,0.87)]
        case "drizzle": return [(0.58,0.64,0.72), (0.82,0.86,0.90)]
        case "thunder": return [(0.55,0.53,0.64), (0.74,0.73,0.82)]
        case "snow":    return [(0.70,0.78,0.88), (0.90,0.94,0.98)]
        case "clear":   return [(0.44,0.68,0.94), (0.76,0.87,0.97)]
        case "cloud":   return [(0.62,0.67,0.75), (0.85,0.88,0.92)]
        case "fog":     return [(0.66,0.69,0.72), (0.87,0.89,0.91)]
        // Régimes extrêmes — la tornade garde ce vert-gris des ciels d'orage violent
        case "tornado": return [(0.50,0.52,0.44), (0.70,0.72,0.66)]
        case "storm":   return [(0.46,0.52,0.62), (0.70,0.75,0.82)]
        case "hail":    return [(0.58,0.62,0.70), (0.80,0.83,0.88)]
        case "heat":    return [(0.98,0.72,0.40), (1.00,0.88,0.66)]
        case "cold":    return [(0.62,0.76,0.92), (0.86,0.93,0.98)]
        case "dust":    return [(0.80,0.66,0.42), (0.92,0.84,0.66)]
        case "cyclone": return [(0.40,0.47,0.54), (0.62,0.68,0.74)]
        case "blizzard": return [(0.75,0.78,0.84), (0.90,0.92,0.95)]
        case "sleet":   return [(0.60,0.70,0.82), (0.82,0.88,0.94)]
        case "deluge":  return [(0.44,0.52,0.64), (0.66,0.72,0.82)]
        default:        return [(0.50,0.62,0.84), (0.80,0.87,0.95)]
        }
    }

    /// Ciels du mode sombre, de jour — les couleurs d'origine de l'app.
    private func cielSombre(_ key: String) -> [RGB] {
        switch key {
        case "rain":    return [(0.20,0.22,0.30), (0.08,0.09,0.14)]
        case "drizzle": return [(0.28,0.30,0.38), (0.10,0.12,0.18)]
        case "thunder": return [(0.10,0.07,0.18), (0.03,0.02,0.06)]
        case "snow":    return [(0.22,0.27,0.36), (0.38,0.43,0.52)]
        case "clear":   return [(0.05,0.38,0.80), (0.22,0.62,0.98)]
        case "cloud":   return [(0.38,0.44,0.58), (0.18,0.22,0.34)]
        case "fog":     return [(0.28,0.31,0.34), (0.42,0.45,0.48)]
        // Régimes extrêmes — assez sombres pour le texte blanc (≥ 4,5:1 avec le voile)
        case "tornado": return [(0.20,0.22,0.17), (0.07,0.08,0.07)]
        case "storm":   return [(0.16,0.19,0.27), (0.05,0.06,0.10)]
        case "hail":    return [(0.24,0.26,0.32), (0.10,0.11,0.16)]
        case "heat":    return [(0.55,0.22,0.05), (0.80,0.42,0.10)]
        case "cold":    return [(0.10,0.18,0.34), (0.30,0.44,0.62)]
        case "dust":    return [(0.42,0.30,0.14), (0.24,0.16,0.08)]
        case "cyclone": return [(0.08,0.12,0.16), (0.03,0.05,0.08)]
        case "blizzard": return [(0.26,0.28,0.34), (0.42,0.45,0.52)]
        case "sleet":   return [(0.16,0.22,0.32), (0.10,0.14,0.22)]
        case "deluge":  return [(0.12,0.16,0.24), (0.05,0.07,0.12)]
        default:        return [(0.08,0.14,0.32), (0.04,0.07,0.18)]
        }
    }
}

// MARK: - Effet Metal : la chaleur qui déforme

/// Applique le shader `chaleur` (Effets.metal) à une vue, animé à 20 i/s.
///
/// Ce qu'on a mesuré : le shader lui-même ne coûte rien, mais SwiftUI
/// re-rasterise TOUTE la vue à chaque changement de paramètre — sur la
/// grille entière, +27 points de CPU. D'où le choix de ne déformer que
/// l'en-tête : petit, et c'est là que l'effet se voit le mieux (le 39°).
/// Pour déformer tout un écran, il faudrait une couche Metal dédiée
/// (MTKView) ou SpriteKit, pas un effet de vue.
struct EffetChaleur: ViewModifier {
    let actif: Bool
    @Environment(\.accessibilityReduceMotion) private var reduit
    @Environment(\.controlActiveState) private var etatFenetre

    func body(content: Content) -> some View {
        if actif && !reduit && etatFenetre != .inactive {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                // Le temps est ramené sous 1 000 s avant de passer en Float :
                // un Float ne garde que ~7 chiffres, et « secondes depuis
                // 2001 » en a 9 — le sinus ne bougerait plus.
                let t = Float(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000))
                content.visualEffect { vue, proxy in
                    vue.distortionEffect(
                        ShaderLibrary.chaleur(.float(t), .float2(proxy.size), .float(1)),
                        maxSampleOffset: CGSize(width: 8, height: 5))
                }
            }
        } else {
            content
        }
    }
}

