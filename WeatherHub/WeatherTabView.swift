import SwiftUI

struct WeatherTabView: View {
    @ObservedObject var vm: WeatherViewModel
    @StateObject private var citiesManager = FavoriteCitiesManager.shared

    /// Ce que l'utilisateur est en train de taper.
    /// Séparé de `vm.city` pour que la carte ne change qu'à la validation.
    @State private var cityInput: String = ""

    /// Grandeur dont on regarde le détail. `nil` = aucune feuille ouverte.
    @State private var detailOuvert: DetailMeteo? = nil

    /// Villes proposées pendant la frappe, et si la liste est visible.
    @StateObject private var localisation = LocationManager()
    @State private var suggestions: [VilleSuggestion] = []
    @State private var listeVisible = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            SondeDefilement()
            VStack(spacing: 18) {
                searchBar
                favoris
                if let error = vm.state.errorMessage { errorBanner(message: error) }
                if let pluie = vm.prochainePluie { bandeauPluie(dans: pluie.minutes) }
                if !vm.alertes.isEmpty { bandeauAlertes }

                // L'en-tête vit hors de la grille, comme sur Apple Météo :
                // une seule grande température, tout le reste en tuiles.
                // Preuve de concept Metal : sous la canicule, l'en-tête ondule
                // dans la chaleur (shader `chaleur`, Effets.metal). Seulement
                // l'en-tête : voir EffetChaleur pour la raison (coût CPU).
                enTete
                    .modifier(EffetChaleur(actif: vm.backgroundConditionKey == "heat"))
                // Sans données fraîches (aperçu restauré, premier chargement),
                // les tuiles afficheraient des zéros qui ont l'air vrais :
                // « Nuages 0 % · Ciel dégagé ». On les grise en attendant.
                grille
                    .redacted(reason: donneesEnAttente ? .placeholder : [])
                    .opacity(donneesEnAttente ? 0.55 : 1)
                    .disabled(donneesEnAttente)
                forecastCard
                    .redacted(reason: donneesEnAttente ? .placeholder : [])
                    .opacity(donneesEnAttente ? 0.55 : 1)
            }
            // Quatre tuiles de ~170 pt : au-delà elles s'étirent sans rien
            // gagner en lisibilité, on plafonne donc la largeur et on centre.
            .frame(maxWidth: 720)
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        // Le champ part de la ville courante, et se resynchronise si elle
        // change ailleurs (clic sur une ville favorite, par exemple).
        .sheet(item: $detailOuvert) { detail in
            DetailMeteoSheet(detail: detail, vm: vm)
        }
        // La position arrive de façon asynchrone : on réagit quand
        // CoreLocation la publie, pas au moment du clic.
        .onChange(of: localisation.location) { _, position in
            guard let position else { return }
            Task { await vm.utiliserMaPosition(position) }
        }
        .onAppear {
            cityInput = vm.city
            // Le champ de recherche est le premier champ de la fenêtre :
            // macOS lui donne le focus et sélectionne « Blois » — une touche
            // effaçait la ville. On rend la main après l'ouverture.
            // Deux essais : selon le lancement, la fenêtre n'est pas encore
            // « key » à 0,4 s (vu au banc d'essai, la sélection revenait).
            for delai in [0.4, 1.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delai) {
                    (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible })?.makeFirstResponder(nil)
                }
            }
        }
        .onChange(of: vm.city) { _, nouvelle in cityInput = nouvelle }
        // `task(id:)` relance à chaque frappe ET annule la précédente :
        // le sleep n'arrive à son terme que si l'utilisateur s'arrête de
        // taper 300 ms. Une requête par mot, pas une par lettre.
        .task(id: cityInput) {
            let saisie = cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard saisie.count >= 2, saisie.lowercased() != vm.city.lowercased() else {
                suggestions = []; listeVisible = false; return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let trouvees = await WeatherService.shared.chercherVilles(saisie)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                suggestions = trouvees
                listeVisible = !trouvees.isEmpty
            }
        }
    }

    /// Vrai tant qu'aucune donnée fraîche n'est arrivée : aperçu restauré
    /// du dernier lancement, ou tout premier chargement.
    private var donneesEnAttente: Bool {
        vm.apercuRestaure || (vm.state.isLoading && vm.state.condition.isEmpty)
    }

    /// Valide la recherche. C'est le seul endroit qui écrit dans `vm.city`.
    private func submitCity() {
        let saisie = cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saisie.isEmpty else { return }
        vm.city = saisie
        vm.fetchWeather()
    }

    // MARK: - Recherche ──────────────────────────────────────────────

    private var searchBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.texte.opacity(0.45)).font(.subheadline)
                    TextField("Ville…", text: $cityInput)
                        .textFieldStyle(.plain)
                        .foregroundColor(.texte)
                        .onSubmit { choisirPremiereOuValider() }
                    if !cityInput.isEmpty {
                        Button {
                            cityInput = ""; suggestions = []; listeVisible = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.texte.opacity(0.35)).font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .fondCarte().cornerRadius(12)

                if listeVisible && !suggestions.isEmpty { listeSuggestions }
            }

            Button { localisation.requestLocation() } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.texte.opacity(0.65))
                    .padding(9).fondCarte().clipShape(Circle())
                    .accessibilityLabel("Météo de ma position")
            }
            .buttonStyle(.plain)
            .help("Utiliser ma position")

            Button { vm.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel("Actualiser la météo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.texte.opacity(0.65))
                    .padding(9).fondCarte().clipShape(Circle())
            }
            .buttonStyle(.plain).disabled(vm.state.isLoading)
        }
    }

    /// « Pluie dans 20 min » — l'information la plus concrète qu'une
    /// app météo puisse donner, tirée des précipitations au quart d'heure.
    private func bandeauPluie(dans minutes: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.rain.fill")
                .font(.title3).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(minutes <= 15 ? "Pluie imminente" : "Pluie dans \(minutes) min")
                    .font(.subheadline.bold()).foregroundColor(.texte)
                Text("D'après les précipitations au quart d'heure")
                    .font(.caption2).foregroundColor(.texte.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.16))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.4), lineWidth: 1))
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pluie prévue dans \(minutes) minutes")
    }

    // MARK: - Alertes ───────────────────────────────────────────────

    private var bandeauAlertes: some View {
        VStack(spacing: 8) {
            ForEach(vm.alertes) { alerte in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alerte.icone)
                        .font(.title3)
                        .foregroundColor(alerte.niveau.couleur)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(alerte.titre)
                                .font(.subheadline.bold()).foregroundColor(.texte)
                            if let p = alerte.probabilite {
                                Text("\(p) %")
                                    .font(.caption2.bold()).foregroundColor(.texte)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(alerte.niveau.couleur.opacity(0.3))
                                    .cornerRadius(5)
                            }
                        }
                        if !alerte.detail.isEmpty {
                            Text(alerte.detail)
                                .font(.caption).foregroundColor(.texte.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // La provenance est affichée : un bulletin officiel
                        // et une estimation maison ne se valent pas.
                        Text(alerte.estOfficielle
                             ? "Bulletin officiel · \(alerte.source)"
                             : "Estimation WeatherHub d'après les modèles")
                            .font(.caption2)
                            .foregroundColor(.texte.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(alerte.niveau.label) : \(alerte.titre). \(alerte.detail)")
                .background(alerte.niveau.couleur.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(alerte.niveau.couleur.opacity(0.45), lineWidth: 1)
                )
                .cornerRadius(14)
            }
        }
        .animation(.spring(duration: 0.4), value: vm.alertes.count)
    }

    private var listeSuggestions: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { ville in
                Button { choisir(ville) } label: {
                    HStack(spacing: 9) {
                        Text(ville.drapeau).font(.body)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ville.nom)
                                .font(.subheadline.bold()).foregroundColor(.texte)
                            if !ville.sousTitre.isEmpty {
                                Text(ville.sousTitre)
                                    .font(.caption2).foregroundColor(.texte.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(ville.populationTexte)
                            .font(.caption2).foregroundColor(.texte.opacity(0.35))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if ville.id != suggestions.last?.id {
                    Divider().background(Color.surface.opacity(0.08))
                }
            }
        }
        .fondCarte()
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.surface.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Applique la ville choisie dans la liste.
    private func choisir(_ ville: VilleSuggestion) {
        // On donne au service les coordonnées exactes : sans ça il
        // rechercherait le nom seul et pourrait tomber sur une homonyme.
        WeatherService.shared.memoriser(ville)
        cityInput = ville.nom
        suggestions = []
        listeVisible = false
        vm.city = ville.nom
        vm.fetchWeather()
    }

    /// Entrée : on prend la première suggestion si la liste est ouverte,
    /// sinon on valide le texte tel quel.
    private func choisirPremiereOuValider() {
        if listeVisible, let premiere = suggestions.first { choisir(premiere) }
        else { submitCity() }
    }

    /// Ce que VoiceOver annonce pour la carte principale : une phrase
    /// complète plutôt qu'une suite de fragments isolés (« Paris »,
    /// « 16,9 », « °C », « Clear », « Fiabilité », « 92 % »…).
    private var resumeVocal: String {
        guard !vm.state.condition.isEmpty else { return "Météo en cours de chargement" }
        var phrase = "\(vm.city.capitalized), \(Int(vm.state.temperature)) degrés, \(vm.state.condition)"
        phrase += ", ressenti \(Int(vm.state.feelsLike)) degrés"
        if vm.state.modelCount > 1 {
            phrase += ", accord des modèles \(vm.state.reliability) pour cent"
        }
        return phrase
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text(message).font(.subheadline).foregroundColor(.texte)
        }
        .padding(12).background(Color.red.opacity(0.3)).cornerRadius(14)
    }

    // MARK: - En-tête ───────────────────────────────────────────────

    /// Ville, température géante, condition, écart avec hier. Pas de
    /// carte autour : le ciel de fond fait office de carte.
    private var enTete: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(vm.city.capitalized)
                        .font(.system(size: 22, weight: .semibold)).foregroundColor(.texte)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.4), value: vm.city)
                    if !vm.state.pays.isEmpty {
                        Text(vm.state.pays).font(.system(size: 13)).foregroundColor(.texte.opacity(0.48))
                    }
                    etoileFavori
                    // Pour ne jamais prendre une neige simulée pour la vraie.
                    if vm.simulation.estActive {
                        Button { withAnimation { vm.simulation = Simulation() } } label: {
                            Text("MODE DÉMO")
                                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                                .foregroundColor(.black.opacity(0.8))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.orange).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Météo simulée — cliquer pour revenir à la météo réelle")
                    }
                }
                if vm.state.isLoading && !vm.apercuRestaure {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .texte))
                        .scaleEffect(1.2).padding(.vertical, 26)
                } else {
                    Text(typoMoins(String(format: "%.0f°", vm.state.temperature)))
                        .font(.system(size: 82, weight: .bold, design: .rounded))
                        .tracking(-3)
                        .foregroundColor(.texte)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .contentShape(Rectangle())
                        .onTapGesture { detailOuvert = .temperature }
                        .help("Voir la température sur 48 h")
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.spring(duration: 0.5, bounce: 0.2), value: vm.state.temperature)
                    HStack(spacing: 8) {
                        Text(vm.conditionLibelle).font(.system(size: 15, weight: .medium)).foregroundColor(.texte.opacity(0.8))
                        if let comparaison = vm.comparaisonHier {
                            Text("·").foregroundColor(.texte.opacity(0.4))
                            Text(comparaison).font(.system(size: 13)).foregroundColor(.texte.opacity(0.55))
                        }
                    }
                    if !vm.uncertaintyString.isEmpty {
                        Text(vm.uncertaintyString)
                            .font(.system(size: 11)).foregroundColor(.texte.opacity(0.45))
                            .help(vm.spreadRangeString)
                    }
                    if !vm.lastUpdatedString.isEmpty {
                        Text(vm.lastUpdatedString).font(.system(size: 10)).foregroundColor(.texte.opacity(0.3))
                    }
                }
            }
            Spacer()
            Image(systemName: vm.weatherIcon)
                .font(.system(size: 64))
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconPrimaryColor(condition: vm.state.condition),
                                 iconSecondaryColor(condition: vm.state.condition))
                .shadow(color: iconPrimaryColor(condition: vm.state.condition).opacity(0.4), radius: 16, x: 0, y: 4)
                .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                .animation(.spring(duration: 0.6, bounce: 0.3), value: vm.weatherIcon)
                .padding(.top, 10)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resumeVocal)
    }

    private var etoileFavori: some View {
        Button {
            if citiesManager.contains(vm.city) {
                if let c = citiesManager.cities.first(where: { $0.name.lowercased() == vm.city.lowercased() }) {
                    citiesManager.remove(c)
                }
            } else { citiesManager.add(vm.city) }
        } label: {
            Image(systemName: citiesManager.contains(vm.city) ? "star.fill" : "star")
                .font(.system(size: 13)).foregroundColor(.yellow)
        }
        .buttonStyle(.plain)
        .help(citiesManager.contains(vm.city) ? "Retirer des favoris" : "Ajouter aux favoris")
        .accessibilityLabel(citiesManager.contains(vm.city)
                            ? "Retirer \(vm.city) des favoris"
                            : "Ajouter \(vm.city) aux favoris")
    }

    // MARK: - Villes favorites ──────────────────────────────────────

    /// Une rangée de pastilles sous la recherche : un clic, une ville.
    @ViewBuilder private var favoris: some View {
        if !citiesManager.cities.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(citiesManager.cities) { city in
                        let active = vm.city.lowercased() == city.name.lowercased()
                        Button {
                            vm.city = city.name; vm.fetchWeather()
                        } label: {
                            HStack(spacing: 4) {
                                Text(city.emoji).font(.caption)
                                Text(city.name).font(.caption.bold())
                            }
                            .foregroundColor(active ? .texteInverse : .texte)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(active ? AnyShapeStyle(Color.texte) : AnyShapeStyle(.ultraThinMaterial.opacity(0.58)))
                            .background(active ? Color.clear : Color.texteInverse.opacity(0.18))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - La grille de tuiles ───────────────────────────────────

    /// Cinq rangées de quatre colonnes ; les tuiles larges en occupent
    /// deux. `Grid` ne sait pas fusionner des cellules, d'où les HStack,
    /// et le GeometryReader donne la largeur exacte d'une colonne :
    /// sans elle, HStack répartirait la place selon le contenu.
    private var grille: some View {
        GeometryReader { g in
            let c = (g.size.width - 30) / 4     // une colonne (3 interstices de 10)
            let large = c * 2 + 10              // deux colonnes + l'interstice
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TuileSoleil(vm: vm).frame(width: large)
                    TuileUV(vm: vm) { detailOuvert = .uv }.frame(width: c)
                    TuileVent(vm: vm) { detailOuvert = .vent }.frame(width: c)
                }
                HStack(spacing: 10) {
                    TuileAccord(vm: vm) { detailOuvert = .temperature }.frame(width: large)
                    TuileRessenti(vm: vm) { detailOuvert = .ressenti }.frame(width: c)
                    TuileHumidite(vm: vm) { detailOuvert = .humidite }.frame(width: c)
                }
                HStack(spacing: 10) {
                    TuileTendance(vm: vm).frame(width: large)
                    TuilePrecipitations(vm: vm) { detailOuvert = .pluieProb }.frame(width: c)
                    TuileNuages(vm: vm) { detailOuvert = .nuages }.frame(width: c)
                }
                HStack(spacing: 10) {
                    TuileSport(vm: vm).frame(width: large)
                    TuileHier(vm: vm).frame(width: c)
                    TuileRafales(vm: vm) { detailOuvert = .rafales }.frame(width: c)
                }
                HStack(spacing: 10) {
                    TuileVisibilite(vm: vm) { detailOuvert = .visibilite }.frame(width: c)
                    TuilePression(vm: vm).frame(width: c)
                    TuileAir(vm: vm) { detailOuvert = .airQuality }.frame(width: c)
                    TuileRosee(vm: vm).frame(width: c)
                }
            }
        }
        // GeometryReader n'a pas de hauteur propre : on lui donne celle
        // des cinq rangées, sinon il s'écrase à zéro dans le ScrollView.
        .frame(height: hauteurTuile * 5 + 40)
    }

    // MARK: - Prévisions 7 jours ────────────────────────────────────

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.texte.opacity(0.66))
                Text("PRÉVISIONS 7 JOURS")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.9)
                    .foregroundColor(.texte.opacity(0.48))
            }

            if vm.state.forecast.isEmpty && !vm.state.isLoading {
                Text("Données indisponibles").foregroundColor(.texte.opacity(0.5)).font(.subheadline)
            } else {
                let tmin = vm.state.forecast.map(\.minTemp).min() ?? 0
                let tmax = vm.state.forecast.map(\.maxTemp).max() ?? 1
                ForEach(vm.state.forecast) { day in
                    HStack(spacing: 10) {
                        Text(day.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.texte.opacity(0.8)).frame(width: 40, alignment: .leading)
                        Image(systemName: day.icon)
                            .font(.system(size: 15))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(iconPrimaryColor(condition: vm.state.condition),
                                             iconSecondaryColor(condition: vm.state.condition))
                            .frame(width: 24)
                        Text("UV \(Int(day.uvMax))")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(uvColor(for: day.uvMax))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(uvColor(for: day.uvMax).opacity(0.18)).cornerRadius(5)
                            .frame(width: 44)
                        Text(typoMoins("\(day.minTemp)°"))
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.texte.opacity(0.55))
                            .frame(width: 34, alignment: .trailing)
                        // La barre situe la journée dans la plage de la semaine :
                        // on voit d'un coup d'œil les jours chauds et les froids.
                        GeometryReader { g in
                            let plage = max(1, Double(tmax - tmin))
                            let x0 = g.size.width * Double(day.minTemp - tmin) / plage
                            let x1 = g.size.width * Double(day.maxTemp - tmin) / plage
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.surface.opacity(0.14))
                                Capsule()
                                    .fill(LinearGradient(colors: [.cyan, .orange], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, x1 - x0)).offset(x: x0)
                            }
                        }
                        .frame(height: 5)
                        Text(typoMoins("\(day.maxTemp)°"))
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.texte)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    if day.id != vm.state.forecast.last?.id {
                        Divider().background(Color.surface.opacity(0.1))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .fondCarte().cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.surface.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
    }

    // MARK: - Helpers ───────────────────────────────────────────────

    private func uvColor(for v: Double) -> Color {
        switch UVLevel.from(v) {
        case .low: return .green; case .moderate: return .yellow
        case .high: return .orange; case .veryHigh: return .red; case .extreme: return .purple
        }
    }
}

