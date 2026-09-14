import Foundation
import Combine
import CoreLocation

@MainActor
final class WeatherViewModel: ObservableObject {

    @Published var city: String = "Paris"
    @Published var state: WeatherState = WeatherState()
    @Published var sports: [SportEvaluation] = []
    @Published var lastUpdated: Date? = nil
    @Published var alertes: [AlerteMeteo] = []

    /// Prévision heure par heure, et ce qu'on en déduit.
    @Published var previsionsHoraires: [PrevisionHeure] = []
    /// Température vue par chaque centre, pour la tuile « Accord des
    /// modèles » : « ECMWF 16,7 · ICON 17,1 · … ».
    @Published var modelesTemperature: [(modele: String, valeur: Double)] = []
    @Published var creneaux: [MeilleurCreneau] = []
    @Published var pluieImminente: [InstantPluie] = []
    @Published var hier: (min: Double, max: Double)? = nil

    // MARK: - Mode démo

    /// Force une condition, un moment ou une alerte (menu Plus → Mode démo).
    /// L'état réel reste de côté : la simulation est rejouée par-dessus à
    /// chaque rafraîchissement, et tout redevient vrai quand on l'arrête.
    @Published var simulation = Simulation.depuisArguments(CommandLine.arguments) ?? Simulation() {
        didSet { rejouerSimulation() }
    }
    private var etatReel: WeatherState?
    private var bulletins: [AlerteMeteo] = []          // officiels, toujours vrais
    private var multiReel: MultiModelSnapshot?
    private var ensembleReel: EnsembleSnapshot?
    private var pluieReelle: [InstantPluie] = []
    private var modelesReels: [(modele: String, valeur: Double)] = []
    private var hierReel: (min: Double, max: Double)? = nil

    private func rejouerSimulation() {
        guard let etatReel else { return }
        state = simulation.appliquer(a: etatReel)
        sports = evaluerSports()
        recalculerAlertes()
        pluieImminente = simulation.pluie(reelle: pluieReelle)
        modelesTemperature = simulation.modeles(reels: modelesReels)
        hier = simulation.hier(reel: hierReel)
    }

    private let service = WeatherService.shared

    /// Dernière météo connue, écrite sur disque.
    ///
    /// Le cache du service vit en mémoire : il est vide à chaque
    /// lancement, et l'utilisateur regardait un spinner muet pendant que
    /// tout se rechargeait. On garde donc un instantané léger pour avoir
    /// quelque chose à montrer immédiatement — quitte à le remplacer
    /// deux secondes plus tard par les vraies valeurs.
    private struct Apercu: Codable {
        let ville: String
        let temperature: Double
        let ressenti: Double
        let condition: String
        let vent: Double
        let humidite: Int
        let date: Date
    }

    private static let cleApercu = "dernierApercu_v1"

    /// Vrai tant qu'on affiche un instantané en attendant les vraies données.
    @Published private(set) var apercuRestaure = false

    /// Instancier un DateFormatter coûte cher, et ces propriétés sont
    /// relues par SwiftUI à chaque redessin. Le format ne changeant jamais,
    /// on le crée une seule fois. (Sûr ici : la classe est @MainActor, et
    /// DateFormatter est de toute façon thread-safe en lecture.)
    /// Écrit l'instantané après chaque chargement réussi.
    private func sauverApercu() {
        // Toujours l'état réel : un instantané « Neige » simulé serait
        // restauré tel quel au prochain lancement.
        let s = etatReel ?? state
        let a = Apercu(ville: city, temperature: s.temperature,
                       ressenti: s.feelsLike, condition: s.condition,
                       vent: s.windSpeed, humidite: s.humidity, date: Date())
        if let data = try? JSONEncoder().encode(a) {
            UserDefaults.standard.set(data, forKey: Self.cleApercu)
        }
    }

    /// Restaure l'instantané au lancement, s'il date de moins de 12 h.
    /// Au-delà, mieux vaut un écran vide qu'une température de la veille.
    func restaurerApercu() {
        guard let data = UserDefaults.standard.data(forKey: Self.cleApercu),
              let a = try? JSONDecoder().decode(Apercu.self, from: data),
              Date().timeIntervalSince(a.date) < 12 * 3600 else { return }
        city = a.ville
        state.temperature = a.temperature
        state.feelsLike = a.ressenti
        state.condition = a.condition
        state.windSpeed = a.vent
        state.humidity = a.humidite
        lastUpdated = a.date
        apercuRestaure = true
    }

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Public API

    func fetchWeather(forceRefresh: Bool = false) {
        state.isLoading = true
        state.errorMessage = nil

        Task {
            do {
                let result = try await service.fetchAll(city: city, forceRefresh: forceRefresh)
                apply(result)
            } catch let err as WeatherServiceError {
                state.isLoading = false
                state.errorMessage = err.errorDescription
            } catch {
                state.isLoading = false
                state.errorMessage = error.localizedDescription
            }
        }
    }

    /// Bascule sur la ville correspondant à une position GPS.
    ///
    /// Le nom vient de `CLGeocoder`, le géocodeur inverse d'Apple :
    /// pas d'appel réseau à nous, pas de clé, et il rend le nom localisé.
    func utiliserMaPosition(_ position: CLLocation) async {
        guard let lieux = try? await CLGeocoder().reverseGeocodeLocation(position),
              let nom = lieux.first?.locality ?? lieux.first?.name else { return }
        city = nom
        fetchWeather()
    }

    /// Forcer un rechargement complet (bouton rafraîchir)
    func refresh() { fetchWeather(forceRefresh: true) }

    // MARK: - Apply service result → WeatherState

    private func apply(_ result: WeatherServiceResult) {
        let cur = result.current

        state = WeatherState(
            temperature:       cur.temperature,
            condition:         cur.condition,
            weatherCode:       cur.weatherCode,
            windSpeed:         cur.windSpeed,
            reliability:       result.reliability,
            forecast:          result.forecast.map { day in
                ForecastItem(
                    label:   day.label,
                    icon:    iconForWMO(day.weatherCode),
                    minTemp: Int(day.tempMin),
                    maxTemp: Int(day.tempMax),
                    uvMax:   day.uvMax
                )
            },
            isLoading:         false,
            errorMessage:      nil,
            humidity:          cur.humidity,
            uvIndex:           cur.uvIndex,
            sunrise:           cur.sunrise,
            sunset:            cur.sunset,
            aqi:               cur.aqi,
            aqiLabel:          cur.aqiLabel,
            aqiIndice:         cur.aqiIndice,
            aqiSources:        cur.aqiSources,
            aqiAccord:         cur.aqiAccord,
            aqiDominant:       cur.aqiDominant,
            feelsLike:         cur.feelsLike,
            visibility:        cur.visibility,
            windDirection:     cur.windDirection,
            pressure:          cur.pressure,
            dewPoint:          cur.dewPoint,
            windGusts:         cur.windGusts,
            precipitationMm:   cur.precipitationMm,
            precipitationProb: cur.precipitationProb,
            cloudCover:        cur.cloudCover,
            cacheHit:          result.cacheHit,
            temperatureSpread: result.multi?.temperature?.spread ?? 0,
            temperatureLow:    result.multi?.temperature?.low ?? 0,
            temperatureHigh:   result.multi?.temperature?.high ?? 0,
            modelCount:        result.multi?.modeles ?? 0,
            ensembleMembers:   result.ensemble?.membres ?? 0,
            pays:              cur.pays
        )
        etatReel = state
        state = simulation.appliquer(a: state)
        multiReel = result.multi; ensembleReel = result.ensemble
        // Les alertes maison tout de suite (elles sont calculées, pas
        // téléchargées) ; les bulletins officiels arrivent après.
        recalculerAlertes()

        lastUpdated = result.fetchedAt
        sports = evaluerSports()
        apercuRestaure = false
        sauverApercu()

        // Les alertes arrivent après coup : elles peuvent demander un
        // appel réseau (NWS, MeteoAlarm) et ne doivent pas retarder
        // l'affichage de la météo.
        Task { [city, pays = state.pays] in
            bulletins = await service.bulletinsOfficiels(city: city, pays: pays)
            recalculerAlertes()
        }

        // Tout ce qui suit est du confort : ça arrive après la météo et
        // ne doit jamais retarder son affichage.
        Task { [state, city] in
            async let horaires = service.previsionHoraire(city: city, heures: 48)
            async let pluie = service.pluieProchaine(city: city)
            async let veille = service.hier(city: city)

            let h = await horaires
            previsionsHoraires = h
            if let s = await service.serieHoraire(city: city, variable: "temperature_2m", heures: 1) {
                modelesReels = s.parModele
                modelesTemperature = simulation.modeles(reels: modelesReels)
            }
            // Le créneau se cherche sur les 24 prochaines heures : au-delà,
            // « 16 h – 18 h » ne dirait plus de quel jour on parle.
            let prochaines24 = Array(h.prefix(24))
            creneaux = SportProfileStore.shared.sports
                .compactMap { SportEvaluator.meilleurCreneau(sport: $0, heures: prochaines24, base: state) }
                .sorted { $0.score > $1.score }
            pluieReelle = await pluie
            pluieImminente = simulation.pluie(reelle: pluieReelle)
            hierReel = await veille
            hier = simulation.hier(reel: hierReel)
        }
    }

    // MARK: - Computed helpers UI

    var temperatureString: String  { String(format: "%.1f°C", state.temperature) }
    var feelsLikeString: String    { String(format: "%.1f°C", state.feelsLike) }
    var dewPointString: String     { String(format: "%.1f°C", state.dewPoint) }
    var reliabilityString: String  { "\(state.reliability)%" }

    /// « ± 0,3 °C · 4 modèles, 40 membres » — vide si on n'a qu'une source,
    /// car un écart-type sur une seule valeur ne veut rien dire.
    var uncertaintyString: String {
        guard state.modelCount > 1 else { return "" }
        var s = String(format: "± %.1f °C · %d modèles", state.temperatureSpread, state.modelCount)
        if state.ensembleMembers > 0 { s += ", \(state.ensembleMembers) membres" }
        return s
    }

    /// L'écart brut entre le modèle le plus froid et le plus chaud.
    var spreadRangeString: String {
        guard state.modelCount > 1 else { return "" }
        return String(format: "de %.1f à %.1f °C", state.temperatureLow, state.temperatureHigh)
    }
    var weatherIcon: String        { regimeExtreme?.icone ?? iconForCondition(state.condition) }

    /// Tornade, tempête, grêle, canicule, grand froid, poussière — ou rien.
    var regimeExtreme: RegimeExtreme? { RegimeExtreme.detecter(state) }

    /// Ce que le décor (ciel, effets) doit représenter : le régime extrême
    /// s'il y en a un, sinon le mot d'OpenWeather.
    var conditionDecor: String { regimeExtreme?.cle ?? state.condition }

    /// Le libellé de l'en-tête : « Canicule » plutôt que « Clear » à 39 °C.
    var conditionLibelle: String { regimeExtreme?.libelle ?? state.condition }
    var uvLevel: UVLevel           { UVLevel.from(state.uvIndex) }
    var sunriseString: String      { state.sunrise.map { timeString($0) } ?? "--:--" }
    var sunsetString: String       { state.sunset.map  { timeString($0) } ?? "--:--" }

    var windDirectionLabel: String {
        let dirs = ["N","NE","E","SE","S","SO","O","NO"]
        return dirs[Int((Double(state.windDirection) / 45.0).rounded()) % 8]
    }

    var lastUpdatedString: String {
        guard let d = lastUpdated else { return "" }
        if apercuRestaure {
            return "Dernière mesure connue · mise à jour en cours…"
        }
        return "Mis à jour à \(Self.formatHeure.string(from: d))\(state.cacheHit ? " (cache)" : "")"
    }

    /// Position du soleil pour la ville affichée. Recalculée à chaque
    /// lecture : le décor suit l'heure sans qu'on ait à rafraîchir.
    var phaseSolaire: PhaseSolaire {
        PhaseSolaire.maintenant(lever: state.sunrise, coucher: state.sunset)
    }

    var backgroundConditionKey: String {
        if let regime = regimeExtreme { return regime.cle }
        let c = state.condition.lowercased()
        // La bruine avant la pluie : elle a ses propres ciels (plus pâles)
        // et sa pluie fine — ils étaient inaccessibles, la bruine tombait
        // dans « rain ».
        if c.contains("drizzle") { return "drizzle" }
        if c.contains("rain")    { return "rain" }
        if c.contains("cloud")   { return "cloud" }
        if c.contains("clear")   { return "clear" }
        if c.contains("snow")    { return "snow" }
        if c.contains("thunder") { return "thunder" }
        // Groupe « Atmosphere » d'OpenWeather : Fog, Mist, Haze…
        // Sans cette ligne, le dégradé "fog" de ContentView était du code mort.
        if c.contains("fog") || c.contains("mist") || c.contains("haze") { return "fog" }
        return "default"
    }

    /// Les alertes affichées : celles que le moteur calcule sur l'état
    /// AFFICHÉ (donc simulé en mode démo — c'est ainsi qu'on voit la consigne
    /// d'une tornade), plus les bulletins officiels de la vraie ville, plus
    /// l'alerte fictive si elle est cochée.
    private func recalculerAlertes() {
        let calculees: [AlerteMeteo]
        if simulation.condition != nil {
            // En simulation, les rafales du moteur sont celles de l'état forcé,
            // pas celles des modèles (qui, eux, voient la vraie météo).
            calculees = MoteurAlertes.calculer(state: state, rafales: EnsembleValue.from([state.windGusts]),
                                               cape: nil, ventMembres: [])
        } else {
            calculees = MoteurAlertes.calculer(state: state, rafales: multiReel?.rafales,
                                               cape: multiReel?.cape, ventMembres: ensembleReel?.ventMembres ?? [])
        }
        alertes = simulation.alertes(reelles: WeatherService.trier(calculees + bulletins))
    }

    /// Le mieux noté du moment. En dessous de 35/100 plus rien ne vaut
    /// la peine dehors, on renvoie donc l'intérieur.
    var bestSportAdvice: String {
        guard let meilleur = sports.first, meilleur.score >= 35 else { return "Sport intérieur" }
        return meilleur.sport.name
    }

    /// « +1,5 °C par rapport à hier » — ou rien si on n'a pas la veille.
    /// Un chiffre absolu ne dit pas grand-chose ; un écart, si.
    var comparaisonHier: String? {
        guard let hier else { return nil }
        let ecart = state.temperature - hier.max
        guard abs(ecart) >= 0.5 else { return "Comme hier" }
        return String(format: "%+.1f °C par rapport à hier", ecart)
    }

    /// Quand la pluie commence, si elle commence dans les 3 heures.
    var prochainePluie: (debut: Date, minutes: Int)? {
        guard let premier = pluieImminente.first(where: { $0.pleut }) else { return nil }
        let minutes = Int(premier.date.timeIntervalSinceNow / 60)
        guard minutes > 0 else { return nil }
        return (premier.date, minutes)
    }

    /// Le score du meilleur sport, avec sa marge — « 78 ± 6 ».
    var bestSportScore: String { sports.first?.scoreTexte ?? "" }

    /// Évalue TOUS les sports du profil et les classe du meilleur au pire.
    /// Le tri est le cœur de l'onglet Sport : la question de l'utilisateur
    /// n'est pas « le tennis est-il jouable ? » mais « que puis-je faire
    /// aujourd'hui ? ».
    private func evaluerSports() -> [SportEvaluation] {
        SportProfileStore.shared.sports
            .map { SportEvaluator.evaluate(sport: $0, state: state) }
            .sorted { $0.score > $1.score }
    }

    // MARK: - Icon helpers

    private func iconForCondition(_ condition: String) -> String {
        switch condition.lowercased() {
        // La nuit, une lune : un soleil à 23 h, c'était le contre-sens du banc d'essai.
        case "clear":        return phaseSolaire.estNuit ? "moon.stars" : "sun.max"
        case "clouds":       return phaseSolaire.estNuit ? "cloud.moon" : "cloud"
        case "rain":         return "cloud.rain"
        case "drizzle":      return "cloud.drizzle"
        case "snow":         return "snowflake"
        case "thunderstorm": return "cloud.bolt.rain"
        case "mist", "fog":  return "cloud.fog"
        default:             return "cloud"
        }
    }

    private func iconForWMO(_ code: Int) -> String {
        switch code {
        case 0:        return "sun.max"
        case 1...3:    return "cloud.sun"
        case 45, 48:   return "cloud.fog"
        case 51...67:  return "cloud.drizzle"
        case 71...77:  return "snowflake"
        case 80...82:  return "cloud.rain"
        case 95...99:  return "cloud.bolt.rain"
        default:       return "cloud"
        }
    }

    private func timeString(_ date: Date) -> String {
        Self.formatHeure.string(from: date)
    }
}

// MARK: - WeatherError (conservé pour compatibilité)
enum WeatherError: Error {
    case cityNotFound(String)
    case invalidURL
    case decodingError
}
