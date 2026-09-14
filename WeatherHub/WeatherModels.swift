import Foundation
import SwiftUI   // NiveauAlerte expose une Color

// MARK: - Weather Models

struct WeatherState {
    var temperature: Double = 0
    var condition: String = ""
    var weatherCode: Int = 0         // code WMO d'Open-Meteo (96/99 = orage de grêle)
    var windSpeed: Double = 0
    var reliability: Int = 0
    var forecast: [ForecastItem] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // ── Données riches ──────────────────────────────
    var humidity: Int = 0            // % humidité
    var uvIndex: Double = 0          // indice UV 0-11+
    var sunrise: Date? = nil         // lever du soleil
    var sunset: Date? = nil          // coucher du soleil
    var aqi: Int = 0                 // Air Quality Index 1-5
    var aqiLabel: String = ""        // ex: "Bon", "Moyen"
    var aqiIndice: Double = 0        // indice européen 0–120, médiane des sources
    var aqiSources: Int = 0          // combien de modèles ont répondu
    var aqiAccord: Int = 0           // % d'accord entre eux
    var aqiDominant: String = ""     // le polluant qui fait l'indice, ex. « O₃ »
    var feelsLike: Double = 0        // ressenti en °C
    var visibility: Double = 0       // km
    var windDirection: Int = 0       // degrés 0-360
    var pressure: Double = 1013      // hPa
    var dewPoint: Double = 0         // point de rosée °C
    var windGusts: Double = 0        // km/h rafales
    var precipitationMm: Double = 0  // mm dernière heure
    var precipitationProb: Int = 0   // % probabilité
    var cloudCover: Int = 0          // % couverture nuageuse
    var cacheHit: Bool = false       // données servies depuis le cache

    // ── Incertitude issue de l'ensemble multi-modèles ───────────────
    var temperatureSpread: Double = 0  // °C, écart-type entre modèles
    var temperatureLow: Double = 0     // °C, modèle le plus froid
    var temperatureHigh: Double = 0    // °C, modèle le plus chaud
    var modelCount: Int = 0            // combien de centres ont répondu
    var ensembleMembers: Int = 0       // membres perturbés exploités
    var pays: String = ""              // code ISO, pour les alertes officielles
}

// MARK: - UV Level

enum UVLevel {
    case low, moderate, high, veryHigh, extreme

    static func from(_ value: Double) -> UVLevel {
        switch value {
        case ..<3:  return .low
        case ..<6:  return .moderate
        case ..<8:  return .high
        case ..<11: return .veryHigh
        default:    return .extreme
        }
    }

    var label: String {
        switch self {
        case .low:      return "Faible"
        case .moderate: return "Modéré"
        case .high:     return "Élevé"
        case .veryHigh: return "Très élevé"
        case .extreme:  return "Extrême"
        }
    }

    var color: String {
        switch self {
        case .low:      return "green"
        case .moderate: return "yellow"
        case .high:     return "orange"
        case .veryHigh: return "red"
        case .extreme:  return "purple"
        }
    }
}

// MARK: - AQI Level

enum AQILevel {
    static func label(for aqi: Int) -> String {
        switch aqi {
        case 1: return "Bon"
        case 2: return "Acceptable"
        case 3: return "Modéré"
        case 4: return "Mauvais"
        case 5: return "Très mauvais"
        default: return "—"
        }
    }

    static func colorName(for aqi: Int) -> String {
        switch aqi {
        case 1: return "green"
        case 2: return "yellow"
        case 3: return "orange"
        case 4, 5: return "red"
        default: return "gray"
        }
    }
}

// MARK: - Indice européen de qualité de l'air

/// L'indice de l'Agence européenne pour l'environnement, recalculé par nous
/// depuis les concentrations. Chaque source (CAMS, OpenWeather, capteurs)
/// publie son propre indice avec son propre barème ; en repartant des
/// µg/m³, elles sont toutes jugées à la même règle, et on peut les
/// comparer — c'est ce qui rend la médiane et l'accord honnêtes.
///
/// Six niveaux de 20 points : 0–20 bon, 20–40 acceptable, 40–60 modéré,
/// 60–80 mauvais, 80–100 très mauvais, 100+ extrêmement mauvais.
/// L'indice global est le PIRE des polluants.
enum IndiceEuropeen {

    /// Bornes des six niveaux (µg/m³), du bon à l'extrêmement mauvais.
    static let bornes: [(polluant: String, seuils: [Double])] = [
        ("PM2.5", [0, 10, 20, 25, 50, 75, 800]),
        ("PM10",  [0, 20, 40, 50, 100, 150, 1200]),
        ("NO₂",   [0, 40, 90, 120, 230, 340, 1000]),
        ("O₃",    [0, 50, 100, 130, 240, 380, 800]),
        ("SO₂",   [0, 100, 200, 350, 500, 750, 1250]),
    ]

    /// Sous-indice d'un polluant : interpolation linéaire dans son niveau,
    /// 20 points par niveau. 25 µg/m³ de PM2.5 → borne haute du niveau 3 → 60.
    static func sousIndice(_ concentration: Double, seuils: [Double]) -> Double {
        for k in 0..<(seuils.count - 1) where concentration <= seuils[k + 1] {
            let bas = seuils[k], haut = seuils[k + 1]
            return Double(k) * 20 + (concentration - bas) / (haut - bas) * 20
        }
        return 120
    }

    /// L'indice global et le polluant qui le fixe.
    static func indice(pm25: Double?, pm10: Double?, no2: Double?, o3: Double?, so2: Double?)
        -> (valeur: Double, dominant: String)? {
        let mesures: [(String, Double?)] = [("PM2.5", pm25), ("PM10", pm10), ("NO₂", no2), ("O₃", o3), ("SO₂", so2)]
        var pire: (valeur: Double, dominant: String)?
        for (nom, c) in mesures {
            guard let c, let b = bornes.first(where: { $0.polluant == nom }) else { continue }
            let v = sousIndice(c, seuils: b.seuils)
            if pire == nil || v > pire!.valeur { pire = (v, nom) }
        }
        return pire
    }

    /// De l'indice 0–120 au niveau 1–5 de l'app : les deux derniers
    /// niveaux européens (très / extrêmement mauvais) sont fusionnés.
    static func niveau(_ indice: Double) -> Int { min(5, Int(indice / 20) + 1) }
}

/// Une source de qualité de l'air : un modèle (CAMS Europe, CAMS global,
/// OpenWeather) ou une mesure (les capteurs citoyens).
struct SourceAir {
    let nom: String
    let estMesure: Bool
    let heures: [Date]                 // vide pour une mesure instantanée
    let indice: [Double?]              // indice européen heure par heure
    let maintenant: Double?            // l'indice à l'heure courante
    let dominant: String?              // le polluant qui fait l'indice maintenant
    let concentrations: [(polluant: String, valeur: Double)]   // maintenant, µg/m³
    let nbCapteurs: Int                // pour une mesure : combien de capteurs
}

/// Les sources réunies : la médiane heure par heure, comme pour la
/// température. Les capteurs sont gardés à part — ils ne voient que les
/// particules, les mélanger aux modèles tirerait la médiane vers le bas
/// les jours d'ozone.
struct QualiteAirEnsemble {
    let sources: [SourceAir]
    let heures: [Date]
    let mediane: [Double?]
    let bas: [Double?]
    let haut: [Double?]

    var modeles: [SourceAir] { sources.filter { !$0.estMesure } }
    var mesures: [SourceAir] { sources.filter { $0.estMesure } }
    var nbModeles: Int { modeles.count }

    /// Ce que disent les modèles maintenant : médiane, dispersion, bornes.
    var maintenant: EnsembleValue? { EnsembleValue.from(modeles.map(\.maintenant)) }
    var niveau: Int { maintenant.map { IndiceEuropeen.niveau($0.median) } ?? 0 }

    /// Accord entre modèles, 0–100. À 15 points d'écart-type on est à
    /// « moitié d'accord » : c'est presque un niveau entier de différence.
    var accord: Int { Int(((maintenant?.confiance(echelle: 15) ?? 0.5) * 100).rounded()) }

    /// Le polluant le plus souvent désigné par les modèles.
    var dominant: String? {
        let noms = modeles.compactMap(\.dominant)
        return Dictionary(grouping: noms, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}

struct ForecastItem: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let minTemp: Int
    let maxTemp: Int
    let uvMax: Double
}

// MARK: - Sport Condition

// MARK: - OpenWeather API Response Shapes

struct OWCurrentResponse: Decodable {
    let main: OWMain
    let weather: [OWWeather]
    let wind: OWWind
    let sys: OWSys
    let visibility: Double?
}

struct OWMain: Decodable {
    let temp: Double
    let feels_like: Double
    let humidity: Int
    let pressure: Double?
}

struct OWWeather: Decodable {
    let main: String
}

struct OWWind: Decodable {
    let speed: Double
    let deg: Int?
}

struct OWSys: Decodable {
    let sunrise: TimeInterval
    let sunset: TimeInterval
    /// Code ISO du pays — sert à router vers le bon service d'alertes.
    /// Il était déjà dans la réponse, simplement pas décodé.
    let country: String?
}

struct OWGeoItem: Decodable {
    let lat: Double
    let lon: Double
    /// Région administrative, ex. « Centre-Val de Loire ».
    /// Sert à juger si un bulletin national nous concerne.
    let state: String?
}

// MARK: - OpenWeather Air Pollution (prévision horaire, 4 jours)

/// On ne lit plus l'indice 1–5 d'OpenWeather (son propre barème, plus
/// laxiste que l'européen) mais les CONCENTRATIONS, pour recalculer
/// l'indice européen nous-mêmes — la même règle pour toutes les sources.
struct OWAirForecastResponse: Decodable {
    let list: [OWAirForecastEntry]
}

struct OWAirForecastEntry: Decodable {
    let dt: Int                      // epoch UTC
    let components: OWAirComponents
}

struct OWAirComponents: Decodable {
    let pm2_5: Double?
    let pm10: Double?
    let no2: Double?
    let o3: Double?
    let so2: Double?
}

// MARK: - Sensor.Community (capteurs citoyens)

/// Une mesure d'un capteur du réseau Sensor.Community (ex-Luftdaten) :
/// des particules mesurées par un SDS011 sur un balcon, pas un modèle.
struct SCMesure: Decodable {
    let timestamp: String
    let sensor: SCCapteur
    let sensordatavalues: [SCValeur]
}

struct SCCapteur: Decodable {
    let id: Int
    let sensor_type: SCTypeCapteur
}

struct SCTypeCapteur: Decodable {
    let name: String
}

struct SCValeur: Decodable {
    let value_type: String           // « P1 » = PM10, « P2 » = PM2.5
    let value: String                // oui, une chaîne
}

// MARK: - Open-Meteo API Response Shapes (v2 — current + daily détaillé)

/// Réponse combinée Open-Meteo avec current ET daily
struct OMCurrentForecastResponse: Decodable {
    let current: OMCurrentData
    let daily:   OMDailyDetailed
}

/// Données "current" temps réel d'Open-Meteo
struct OMCurrentData: Decodable {
    let temperature_2m:        Double
    let relative_humidity_2m:  Int?
    let apparent_temperature:  Double?
    let precipitation:         Double?
    let weather_code:          Int?
    let cloud_cover:           Int?
    let pressure_msl:          Double?
    let wind_speed_10m:        Double   // km/h (Open-Meteo renvoie déjà km/h)
    let wind_direction_10m:    Int?
    let wind_gusts_10m:        Double?
    let uv_index:              Double?
    let dew_point_2m:          Double?
}

/// Prévisions journalières enrichies
struct OMDailyDetailed: Decodable {
    let time:                          [String]
    let weathercode:                   [Int]
    let temperature_2m_max:            [Double]
    let temperature_2m_min:            [Double]
    let uv_index_max:                  [Double]?
    let precipitation_sum:             [Double]?
    let precipitation_probability_max: [Int]?
    let wind_speed_10m_max:            [Double]?
    let sunrise:                       [String]?
    let sunset:                        [String]?
}

// MARK: - Anciens shapes (toujours utilisés pour compatibilité ViewModel)

struct OMForecastResponse: Decodable {
    let daily: OMDaily
    let hourly: OMHourly?
}

struct OMDaily: Decodable {
    let time: [String]
    let weathercode: [Int]
    let temperature_2m_max: [Double]
    let temperature_2m_min: [Double]
    let uv_index_max: [Double]?
}

struct OMHourly: Decodable {
    let uv_index: [Double]?
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Ensemble multi-modèles
// ═══════════════════════════════════════════════════════════════════

/// Une grandeur météo telle que la voient PLUSIEURS modèles de prévision.
///
/// ECMWF, le DWD allemand, la NOAA américaine et Météo-France font tourner
/// des modèles différents sur les mêmes observations, et ils ne tombent pas
/// d'accord. Cet écart n'est pas du bruit à gommer : c'est *l'incertitude
/// de la prévision*, et c'est une information à part entière.
struct EnsembleValue {

    /// Valeur retenue : la MÉDIANE, pas la moyenne.
    /// Un modèle isolé qui déraille (GFS annonçant 100 % de nuages quand
    /// les trois autres disent 55 %) déplace la moyenne, pas la médiane.
    let median: Double

    /// Écart-type entre les modèles. C'est la mesure de l'incertitude :
    /// petit = les modèles s'accordent, grand = personne ne sait.
    let spread: Double

    let low: Double
    let high: Double

    /// Combien de modèles ont réellement fourni cette valeur.
    /// Ils ne publient pas tous les mêmes variables — Météo-France, par
    /// exemple, ne renvoie pas la probabilité de précipitation.
    let count: Int

    /// Calcule la statistique à partir des valeurs de chaque modèle.
    /// Les `nil` (variable non publiée) sont écartés, pas comptés comme 0.
    static func from(_ valeurs: [Double?]) -> EnsembleValue? {
        let v = valeurs.compactMap { $0 }
        guard !v.isEmpty else { return nil }

        let triees = v.sorted()
        let n = triees.count
        let mediane = n % 2 == 1 ? triees[n / 2]
                                 : (triees[n / 2 - 1] + triees[n / 2]) / 2

        let moyenne = v.reduce(0, +) / Double(n)
        let variance = v.reduce(0) { $0 + ($1 - moyenne) * ($1 - moyenne) } / Double(n)

        return EnsembleValue(median: mediane, spread: variance.squareRoot(),
                             low: triees[0], high: triees[n - 1], count: n)
    }

    /// Confiance entre 0 et 1.
    /// Vaut 1 quand les modèles disent tous la même chose, et exactement
    /// 0,5 quand la dispersion atteint `echelle`. La courbe décroît sans
    /// jamais toucher 0 : même un fort désaccord reste une information.
    ///
    /// Un seul modèle disponible ⇒ 0,5 : on ne peut RIEN dire de l'accord,
    /// ce qui n'est ni bon ni mauvais signe.
    func confiance(echelle: Double) -> Double {
        guard echelle > 0 else { return 0.5 }
        guard count > 1 else { return 0.5 }
        let r = spread / echelle
        return 1 / (1 + r * r)
    }

    /// Pour l'affichage : « 20,7 °C ± 0,3 »
    func texte(unite: String, decimales: Int = 1) -> String {
        String(format: "%.\(decimales)f %@", median, unite)
    }
}

/// Dispersion à partir de laquelle on considère que les modèles ne sont
/// « plus qu'à moitié d'accord » (confiance = 50 %).
/// Calibré sur des écarts réellement observés à courte échéance.
enum EchelleDesaccord {
    static let temperature = 1.5    // °C
    static let vent        = 6.0    // km/h
    static let probaPluie  = 20.0   // points de %
    static let nuages      = 25.0   // points de % — les modèles divergent
                                    // beaucoup sur la nébulosité
    static let uv          = 1.5    // points d'indice UV
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Alertes météo
// ═══════════════════════════════════════════════════════════════════

enum NiveauAlerte: Int, Comparable, CaseIterable {
    case info = 0        // à savoir
    case vigilance = 1   // soyez attentif
    case danger = 2      // conditions dangereuses
    case extreme = 3     // danger vital

    static func < (a: NiveauAlerte, b: NiveauAlerte) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .info:      return "Information"
        case .vigilance: return "Vigilance"
        case .danger:    return "Danger"
        case .extreme:   return "Danger extrême"
        }
    }

    var couleur: Color {
        switch self {
        case .info:      return .blue
        case .vigilance: return .yellow
        case .danger:    return .orange
        case .extreme:   return .red
        }
    }

    var icone: String {
        switch self {
        case .info:      return "info.circle.fill"
        case .vigilance: return "exclamationmark.triangle.fill"
        case .danger:    return "exclamationmark.octagon.fill"
        case .extreme:   return "exclamationmark.3"
        }
    }
}

struct AlerteMeteo: Identifiable {
    let id = UUID()
    let titre: String
    let detail: String
    let niveau: NiveauAlerte
    let icone: String
    /// D'où vient l'alerte : nos calculs, ou un service officiel.
    /// La distinction est affichée — une alerte calculée n'a pas
    /// la même valeur qu'un bulletin de Météo-France ou du NWS.
    let source: String
    /// Part des membres de l'ensemble qui franchissent le seuil.
    let probabilite: Int?
    let fin: Date?

    var estOfficielle: Bool { source != "WeatherHub" }
}

// MARK: - Régimes extrêmes

/// Les situations où la météo n'est plus un décor mais un danger. Dérivées
/// de l'état : le mot d'OpenWeather (« Tornado », « Squall », « Dust »),
/// le code WMO d'Open-Meteo (96/99 = orage de grêle), les rafales et la
/// température. Aucune API ne dit « tornade » à part OpenWeather, et
/// seulement quand une station l'observe — d'où le mode démo pour tester.
enum RegimeExtreme: String, CaseIterable {
    case tornade, cyclone, grele, blizzard, tempete, verglas, deluge, poussiere, canicule, grandFroid

    /// La clé de décor : ciel, effets de fond, tuile Soleil.
    var cle: String {
        switch self {
        case .tornade: return "tornado";  case .cyclone: return "cyclone";  case .grele: return "hail"
        case .blizzard: return "blizzard"; case .tempete: return "storm";   case .verglas: return "sleet"
        case .deluge: return "deluge";    case .poussiere: return "dust";   case .canicule: return "heat"
        case .grandFroid: return "cold"
        }
    }
    var libelle: String {
        switch self {
        case .tornade: return "Tornade";   case .cyclone: return "Cyclone";     case .grele: return "Orage de grêle"
        case .blizzard: return "Blizzard"; case .tempete: return "Tempête";     case .verglas: return "Pluie verglaçante"
        case .deluge: return "Déluge";     case .poussiere: return "Tempête de poussière"
        case .canicule: return "Canicule"; case .grandFroid: return "Grand froid"
        }
    }
    var icone: String {
        switch self {
        case .tornade: return "tornado";          case .cyclone: return "hurricane";       case .grele: return "cloud.hail.fill"
        case .blizzard: return "wind.snow";       case .tempete: return "wind";            case .verglas: return "cloud.sleet.fill"
        case .deluge: return "cloud.heavyrain.fill"; case .poussiere: return "sun.dust.fill"
        case .canicule: return "thermometer.sun.fill"; case .grandFroid: return "thermometer.snowflake"
        }
    }

    /// Détection, du plus grave au moins grave : une tornade sous 38 °C
    /// reste une tornade. Cyclone, ouragan et typhon sont le même
    /// phénomène (vent soutenu ≥ 118 km/h, force 12) nommé selon l'océan.
    static func detecter(_ s: WeatherState) -> RegimeExtreme? {
        let c = s.condition.lowercased(), code = s.weatherCode
        let neige = c.contains("snow") || (71...77).contains(code) || [85, 86].contains(code)
        let pluie = c.contains("rain") || c.contains("drizzle") || (51...67).contains(code) || (80...82).contains(code)
        if c.contains("tornado")                                          { return .tornade }
        if s.windSpeed >= 118 || s.windGusts >= 150                       { return .cyclone }
        if [96, 99].contains(code) || c.contains("hail")                  { return .grele }
        if neige && s.windGusts >= 60                                     { return .blizzard }
        if c.contains("squall") || s.windGusts >= 100                     { return .tempete }
        if [56, 57, 66, 67].contains(code) || (pluie && s.temperature <= 0) { return .verglas }
        if s.precipitationMm >= 30                                        { return .deluge }
        if c.contains("dust") || c.contains("sand") || c.contains("ash")  { return .poussiere }
        if s.temperature >= 38 || s.feelsLike >= 40                       { return .canicule }
        if s.temperature <= -12 || s.feelsLike <= -18                     { return .grandFroid }
        return nil
    }
}

// MARK: - Moteur d'alertes calculées

/// Produit des alertes à partir des modèles, partout dans le monde.
///
/// Ce moteur ne remplace PAS les services officiels : il ne sait pas
/// détecter une tornade (aucun modèle global ne le fait — seuls les
/// radars et les bulletins du NWS le peuvent). Il repère des situations
/// à risque et, quand l'ensemble le permet, chiffre leur probabilité.
struct MoteurAlertes {

    /// Seuils. Rassemblés ici pour être discutables d'un coup d'œil
    /// plutôt qu'éparpillés dans le code.
    enum Seuils {
        static let rafalesVigilance = 60.0   // km/h
        static let rafalesDanger    = 80.0
        static let rafalesExtreme   = 100.0
        static let capeVigilance    = 1000.0 // J/kg
        static let capeDanger       = 2500.0
        static let chaleurVigilance = 33.0   // °C
        static let chaleurDanger    = 38.0
        static let froidVigilance   = -5.0
        static let froidDanger      = -10.0
        static let pluieVigilance   = 15.0   // mm/h
        static let pluieDanger      = 30.0
        static let uvVigilance      = 8.0
        static let uvExtreme        = 11.0
    }

    static func calculer(state: WeatherState,
                         rafales: EnsembleValue?,
                         cape: EnsembleValue?,
                         ventMembres: [Double]) -> [AlerteMeteo] {
        var alertes: [AlerteMeteo] = []

        /// Part des membres de l'ensemble au-dessus d'un seuil.
        /// C'est la probabilité au sens des prévisions d'ensemble :
        /// on compte les scénarios, on ne moyenne pas.
        func probabilite(_ membres: [Double], au_dessus seuil: Double) -> Int? {
            guard membres.count >= 5 else { return nil }
            return Int((Double(membres.filter { $0 > seuil }.count) / Double(membres.count) * 100).rounded())
        }

        let c = state.condition.lowercased()

        // ── Régimes extrêmes : la consigne d'abord ──────────────────
        let regime = RegimeExtreme.detecter(state)
        switch regime {
        case .tornade:
            alertes.append(AlerteMeteo(
                titre: "Tornade signalée",
                detail: "Abritez-vous tout de suite au niveau le plus bas d'un bâtiment solide, loin des fenêtres. Ne cherchez pas à la distancer en voiture.",
                niveau: .extreme, icone: "tornado", source: "WeatherHub", probabilite: nil, fin: nil))
        case .cyclone:
            alertes.append(AlerteMeteo(
                titre: "Cyclone — vent de force 12",
                detail: "Vent soutenu à \(Int(state.windSpeed)) km/h, rafales à \(Int(state.windGusts)). Confinez-vous dans une pièce sans fenêtre, éloignez-vous du littoral et des cours d'eau, ne sortez pas pendant l'accalmie de l'œil.",
                niveau: .extreme, icone: "hurricane", source: "WeatherHub", probabilite: nil, fin: nil))
        case .blizzard:
            alertes.append(AlerteMeteo(
                titre: "Blizzard",
                detail: "Neige soufflée à \(Int(state.windGusts)) km/h, visibilité quasi nulle. Ne prenez pas la route ; si vous êtes bloqué, restez dans le véhicule.",
                niveau: .danger, icone: "wind.snow", source: "WeatherHub", probabilite: nil, fin: nil))
        case .verglas:
            alertes.append(AlerteMeteo(
                titre: "Pluie verglaçante",
                detail: "La pluie gèle au contact du sol : chaussées, trottoirs et lignes électriques sous une couche de glace. Évitez de conduire et de marcher sur les surfaces lisses.",
                niveau: .danger, icone: "cloud.sleet.fill", source: "WeatherHub", probabilite: nil, fin: nil))
        case .deluge:
            alertes.append(AlerteMeteo(
                titre: "Déluge — risque d'inondation",
                detail: "\(Int(state.precipitationMm)) mm par heure. Ne traversez jamais une route inondée, à pied ou en voiture ; montez à l'étage si l'eau monte.",
                niveau: .extreme, icone: "cloud.heavyrain.fill", source: "WeatherHub", probabilite: nil, fin: nil))
        case .grele:
            alertes.append(AlerteMeteo(
                titre: "Orage de grêle",
                detail: "Mettez véhicules et personnes à l'abri ; ne restez ni sous un arbre ni sous une verrière.",
                niveau: .danger, icone: "cloud.hail.fill", source: "WeatherHub", probabilite: nil, fin: nil))
        case .poussiere:
            alertes.append(AlerteMeteo(
                titre: "Air chargé de poussières",
                detail: "Visibilité réduite et air irritant : fermez les fenêtres, évitez l'effort dehors.",
                niveau: .vigilance, icone: "sun.dust.fill", source: "WeatherHub", probabilite: nil, fin: nil))
        default: break
        }

        // ── Orage ───────────────────────────────────────────────────
        if c.contains("thunder") {
            alertes.append(AlerteMeteo(
                titre: "Orage en cours",
                detail: "Évitez les espaces découverts, les arbres isolés et les points hauts.",
                niveau: .danger, icone: "cloud.bolt.rain.fill",
                source: "WeatherHub", probabilite: nil, fin: nil))
        } else if let cape = cape, cape.median >= Seuils.capeVigilance {
            let fort = cape.median >= Seuils.capeDanger
            alertes.append(AlerteMeteo(
                titre: fort ? "Fort potentiel orageux" : "Potentiel orageux",
                detail: "Énergie convective de \(Int(cape.median)) J/kg" +
                        (cape.count > 1 ? " (les modèles vont de \(Int(cape.low)) à \(Int(cape.high)))" : "") +
                        ". Des orages peuvent se déclencher.",
                niveau: fort ? .danger : .vigilance, icone: "cloud.bolt.fill",
                source: "WeatherHub", probabilite: nil, fin: nil))
        }

        // ── Vent et rafales ─────────────────────────────────────────
        // (pas en doublon d'une consigne qui parle déjà du vent)
        if let r = rafales, r.median >= Seuils.rafalesVigilance,
           ![.tornade, .cyclone, .blizzard].contains(regime) {
            let niveau: NiveauAlerte = r.median >= Seuils.rafalesExtreme ? .extreme
                                     : r.median >= Seuils.rafalesDanger ? .danger : .vigilance
            var detail = "Rafales attendues à \(Int(r.median)) km/h"
            if r.count > 1 { detail += ", les modèles annoncent de \(Int(r.low)) à \(Int(r.high)) km/h" }
            detail += ". Attention aux chutes de branches et aux objets non fixés."
            alertes.append(AlerteMeteo(
                titre: niveau == .extreme ? "Rafales de tempête" : "Vent fort",
                detail: detail, niveau: niveau, icone: "wind",
                source: "WeatherHub",
                probabilite: probabilite(ventMembres, au_dessus: Seuils.rafalesVigilance * 0.7),
                fin: nil))
        }

        // ── Chaleur / froid ─────────────────────────────────────────
        if state.temperature >= Seuils.chaleurVigilance {
            let fort = state.temperature >= Seuils.chaleurDanger
            alertes.append(AlerteMeteo(
                titre: fort ? "Chaleur dangereuse" : "Forte chaleur",
                detail: "\(Int(state.temperature)) °C, ressenti \(Int(state.feelsLike)) °C. " +
                        "Hydratez-vous, évitez l'effort entre 12 h et 16 h.",
                niveau: fort ? .danger : .vigilance, icone: "thermometer.sun.fill",
                source: "WeatherHub", probabilite: nil, fin: nil))
        } else if state.temperature <= Seuils.froidVigilance {
            let fort = state.temperature <= Seuils.froidDanger
            alertes.append(AlerteMeteo(
                titre: fort ? "Froid dangereux" : "Grand froid",
                detail: "\(Int(state.temperature)) °C, ressenti \(Int(state.feelsLike)) °C. " +
                        "Risque d'hypothermie en cas d'exposition prolongée.",
                niveau: fort ? .danger : .vigilance, icone: "thermometer.snowflake",
                source: "WeatherHub", probabilite: nil, fin: nil))
        }

        // ── Pluie intense ───────────────────────────────────────────
        if state.precipitationMm >= Seuils.pluieVigilance, regime != .deluge {
            let fort = state.precipitationMm >= Seuils.pluieDanger
            alertes.append(AlerteMeteo(
                titre: fort ? "Pluies intenses" : "Fortes pluies",
                detail: String(format: "%.1f mm sur la dernière heure. Risque de ruissellement.", state.precipitationMm),
                niveau: fort ? .danger : .vigilance, icone: "cloud.heavyrain.fill",
                source: "WeatherHub", probabilite: nil, fin: nil))
        }

        // ── UV ──────────────────────────────────────────────────────
        if state.uvIndex >= Seuils.uvVigilance {
            let extreme = state.uvIndex >= Seuils.uvExtreme
            alertes.append(AlerteMeteo(
                titre: extreme ? "UV extrêmes" : "UV élevés",
                detail: String(format: "Indice %.1f. Crème solaire, chapeau et ombre aux heures centrales.", state.uvIndex),
                niveau: extreme ? .danger : .vigilance, icone: "sun.max.trianglebadge.exclamationmark.fill",
                source: "WeatherHub", probabilite: nil, fin: nil))
        }

        return alertes.sorted { $0.niveau > $1.niveau }
    }
}


// MARK: - Décodage des flux d'alertes

struct NWSReponse: Decodable {
    let features: [NWSFeature]
}
struct NWSFeature: Decodable {
    let properties: NWSProprietes
}
struct NWSProprietes: Decodable {
    let event: String?
    let severity: String?
    let headline: String?
    let description: String?
    let expires: String?
}

struct MeteoAlarmReponse: Decodable {
    let warnings: [MABulletin]
}
struct MABulletin: Decodable {
    let alert: MAAlerte
}
struct MAAlerte: Decodable {
    let info: [MAInfo]
}
struct MAInfo: Decodable {
    let event: String?
    let expires: String?
    let area: [MAZone]?
    let parameter: [MAParametre]?
}
struct MAZone: Decodable {
    let areaDesc: String?
}
struct MAParametre: Decodable {
    let valueName: String?
    let value: String?
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Suggestion de ville (autocomplétion)
// ═══════════════════════════════════════════════════════════════════

struct VilleSuggestion: Identifiable, Equatable {
    let id: Int
    let nom: String
    let region: String
    let pays: String
    let codePays: String
    let population: Int
    let lat: Double
    let lon: Double

    /// Drapeau émoji construit à partir du code ISO du pays.
    /// « FR » → 🇫🇷 : chaque lettre est décalée vers son « regional
    /// indicator symbol », et la paire forme le drapeau.
    var drapeau: String {
        codePays.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value).map(String.init)
        }.joined()
    }

    /// « Centre-Val de Loire, France » — ce qui permet de distinguer
    /// Paris (France) de Paris (Texas).
    var sousTitre: String {
        [region, pays].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var populationTexte: String {
        switch population {
        case 1_000_000...: return "\(population / 1_000_000) M hab."
        case 1_000...:     return "\(population / 1_000) k hab."
        case 1...:         return "\(population) hab."
        default:           return ""
        }
    }
}

// Réponse de l'API de géocodage Open-Meteo
struct OMGeocodingReponse: Decodable {
    let results: [OMGeocodingItem]?
}
struct OMGeocodingItem: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let country_code: String?
    let admin1: String?
    let population: Int?
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Radar de précipitations (RainViewer)
// ═══════════════════════════════════════════════════════════════════

/// Une image radar : un instant, et le chemin des tuiles qui la composent.
struct ImageRadar: Identifiable, Equatable {
    let id: Int              // horodatage Unix, unique par image
    let date: Date
    let chemin: String       // ex. "/v2/radar/1694..." — à préfixer par l'hôte
    /// Vrai pour les images de « nowcast » : une extrapolation du radar
    /// sur la demi-heure à venir, pas une mesure.
    let estPrevision: Bool
}

struct RainViewerReponse: Decodable {
    let host: String
    let radar: RainViewerRadar
}
struct RainViewerRadar: Decodable {
    let past: [RainViewerImage]
    let nowcast: [RainViewerImage]?
}
struct RainViewerImage: Decodable {
    let time: Int
    let path: String
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Position du soleil
// ═══════════════════════════════════════════════════════════════════

/// Où en est le soleil dans sa course, d'après le lever et le coucher
/// réels de la ville affichée.
///
/// L'app connaissait déjà ces deux heures — elle les affichait dans la
/// carte Lever/Coucher — mais les décors les ignoraient : un ciel « Clear »
/// était un plein midi, y compris à deux heures du matin.
struct PhaseSolaire {

    /// −1 au cœur de la nuit, 0 au lever et au coucher, 1 au zénith.
    let elevation: Double

    /// 0 au lever, 1 au coucher. Sort de [0, 1] pendant la nuit.
    /// Sert à placer le soleil d'est en ouest.
    let progression: Double

    /// 1 pile à l'heure du lever ou du coucher, retombe à 0 en une heure.
    /// C'est ce qui déclenche les teintes chaudes.
    let teinteCrepusculaire: Double

    var estNuit: Bool { elevation <= 0 }

    /// Valeur de repli quand on n'a pas encore les horaires : plein jour.
    static let inconnue = PhaseSolaire(elevation: 0.7, progression: 0.5, teinteCrepusculaire: 0)

    static func maintenant(lever: Date?, coucher: Date?, date: Date = Date()) -> PhaseSolaire {
        guard let lever, let coucher, coucher > lever else { return .inconnue }

        let dureeJour = coucher.timeIntervalSince(lever)
        let p = date.timeIntervalSince(lever) / dureeJour

        // Teinte chaude : basée sur la distance au bord le plus proche.
        let minutesDuBord = min(abs(date.timeIntervalSince(lever)),
                                abs(date.timeIntervalSince(coucher))) / 60
        let teinte = max(0, 1 - minutesDuBord / 60)

        if (0...1).contains(p) {
            // Jour : une arche simple, maximale à midi solaire.
            return PhaseSolaire(elevation: sin(p * .pi),
                                progression: p,
                                teinteCrepusculaire: teinte)
        }

        // Nuit : l'obscurité s'installe en ~4 h, puis reste pleine.
        let heuresDuBord = minutesDuBord / 60
        return PhaseSolaire(elevation: -min(1.0, heuresDuBord / 4.0),
                            progression: p < 0 ? 0 : 1,
                            teinteCrepusculaire: teinte)
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Prévision heure par heure
// ═══════════════════════════════════════════════════════════════════

/// Accès sécurisé par index : les séries d'Open-Meteo n'ont pas toujours
/// la même longueur d'une variable à l'autre.
extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

struct PrevisionHeure: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double
    let ressenti: Double
    let vent: Double
    let rafales: Double
    let uv: Double
    let probaPluie: Int
    let codeMeteo: Int        // code WMO, pour l'icône
    let nuages: Int           // %
    let precipitation: Double // mm
}

struct InstantPluie: Identifiable {
    let id = UUID()
    let date: Date
    let mm: Double
    let probabilite: Int
    var pleut: Bool { mm > 0.05 || probabilite >= 50 }
}

struct OMReponseMinutely: Decodable {
    let minutely_15: OMSeriesHoraires
}

struct OMArchiveReponse: Decodable {
    let daily: OMArchiveDaily
}
struct OMArchiveDaily: Decodable {
    let temperature_2m_max: [Double?]
    let temperature_2m_min: [Double?]
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Créneaux sportifs
// ═══════════════════════════════════════════════════════════════════

/// Le score d'un sport à une heure donnée.
struct CreneauSport: Identifiable {
    let id = UUID()
    let date: Date
    let score: Int
    let frein: String?     // ce qui pénalise le plus à cette heure-là
}

/// La meilleure plage de la journée pour un sport.
struct MeilleurCreneau {
    let sport: FavoriteSport
    let debut: Date
    let fin: Date
    let score: Int
    /// Toutes les heures évaluées, pour dessiner une frise.
    let heures: [CreneauSport]
    /// La pire plage, quand elle vaut la peine d'être signalée.
    let aEviter: (debut: Date, fin: Date, frein: String)?
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Mode démo
// ═══════════════════════════════════════════════════════════════════

/// Une météo forcée, pour tester l'interface sans attendre qu'il neige.
/// Chaque condition vient avec des valeurs plausibles ; le moment déplace
/// le lever et le coucher autour de l'heure courante, pour que
/// `PhaseSolaire` calcule un VRAI crépuscule ou une vraie nuit. Rien
/// n'est inventé dans les données reçues : le ViewModel garde l'état réel
/// de côté et rejoue la simulation par-dessus.
struct Simulation: Equatable {

    enum Condition: String, CaseIterable, Identifiable {
        case clear, clouds, rain, shower, drizzle, thunder, snow, fog
        // Les extrêmes : détectés par `RegimeExtreme` depuis les valeurs ci-dessous
        case tornado, cyclone, storm, hail, blizzard, freezing, deluge, heat, cold, dust
        var id: String { rawValue }

        static let ordinaires: [Condition] = [.clear, .clouds, .rain, .shower, .drizzle, .thunder, .snow, .fog]
        static let extremes: [Condition] = [.tornado, .cyclone, .storm, .hail, .blizzard, .freezing, .deluge, .heat, .cold, .dust]

        var libelle: String {
            switch self {
            case .clear: return "Dégagé";  case .clouds: return "Nuageux"; case .rain: return "Pluie"
            case .shower: return "Averse";  case .drizzle: return "Bruine"; case .thunder: return "Orage";  case .snow: return "Neige"
            case .fog: return "Brouillard"
            case .tornado: return "Tornade"; case .storm: return "Tempête"; case .hail: return "Orage de grêle"
            case .heat: return "Canicule";   case .cold: return "Grand froid"; case .dust: return "Tempête de poussière"
            case .cyclone: return "Cyclone (ouragan, typhon)"; case .blizzard: return "Blizzard"
            case .freezing: return "Pluie verglaçante";        case .deluge: return "Déluge"
            }
        }
        var icone: String {
            switch self {
            case .clear: return "sun.max.fill";        case .clouds: return "cloud.fill"
            case .rain: return "cloud.rain.fill";      case .shower: return "cloud.heavyrain.fill"; case .drizzle: return "cloud.drizzle.fill"
            case .thunder: return "cloud.bolt.rain.fill"; case .snow: return "snowflake"
            case .fog: return "cloud.fog.fill"
            case .tornado: return "tornado";           case .storm: return "wind"
            case .hail: return "cloud.hail.fill";      case .heat: return "thermometer.sun.fill"
            case .cold: return "thermometer.snowflake"; case .dust: return "sun.dust.fill"
            case .cyclone: return "hurricane";         case .blizzard: return "wind.snow"
            case .freezing: return "cloud.sleet.fill"; case .deluge: return "cloud.heavyrain.fill"
            }
        }
        /// Le libellé qu'OpenWeather renverrait — c'est lui que lisent
        /// `backgroundConditionKey`, `weatherIcon` et les effets de fond.
        var conditionOW: String {
            switch self {
            case .clear: return "Clear";     case .clouds: return "Clouds"; case .rain: return "Rain"; case .shower: return "Rain"
            case .drizzle: return "Drizzle"; case .thunder: return "Thunderstorm"; case .snow: return "Snow"
            case .fog: return "Fog"
            // Ce qu'OpenWeather renvoie vraiment : « Tornado », « Squall », « Dust ».
            // La grêle et la canicule n'ont pas de mot : c'est le code WMO
            // ou la température qui les révèlent, comme en vrai.
            case .tornado: return "Tornado"; case .storm: return "Squall"; case .hail: return "Thunderstorm"
            case .heat: return "Clear";      case .cold: return "Clear";   case .dust: return "Dust"
            // Pas de mot non plus pour ceux-là : c'est le vent, le code WMO
            // ou le cumul qui les révèlent.
            case .cyclone: return "Rain";    case .blizzard: return "Snow"; case .freezing: return "Rain"; case .deluge: return "Rain"
            }
        }
        /// Les mêmes chiffres que le banc d'essai HTML.
        var valeurs: (temperature: Double, ressenti: Double, uv: Double, vent: Double, rafales: Double,
                      humidite: Int, nuages: Int, mm: Double, proba: Int, visibilite: Double, pression: Double, rosee: Double, code: Int) {
            switch self {
            case .clear:   return (26, 27, 6, 9, 16, 38, 4, 0, 0, 10, 1024, 11, 0)
            case .clouds:  return (22, 22, 3, 12, 22, 55, 78, 0, 5, 10, 1016, 13, 3)
            case .rain:    return (16, 14, 1, 18, 34, 91, 100, 2.4, 90, 4, 1002, 15, 63)
            case .shower:  return (17, 15, 1, 24, 45, 93, 100, 9.0, 100, 2, 999, 15, 82)
            case .drizzle: return (15, 14, 1, 8, 14, 94, 100, 0.3, 70, 2.5, 1008, 14, 53)
            case .thunder: return (24, 27, 2, 26, 58, 84, 95, 6.0, 95, 3, 998, 21, 95)
            case .snow:    return (-2, -7, 1, 11, 20, 88, 100, 1.2, 80, 1.5, 1010, -4, 73)
            case .fog:     return (9, 8, 1, 3, 5, 98, 100, 0, 5, 0.4, 1028, 9, 45)
            case .tornado: return (26, 26, 1, 70, 160, 80, 100, 8.0, 95, 1.5, 985, 22, 95)
            case .storm:   return (12, 7, 1, 75, 118, 85, 100, 4.0, 90, 3, 978, 9, 65)
            case .hail:    return (19, 18, 1, 30, 65, 88, 100, 12.0, 95, 2, 995, 16, 99)
            case .heat:    return (39, 42, 10, 6, 12, 25, 3, 0, 0, 8, 1018, 14, 0)
            case .cold:    return (-14, -21, 1, 14, 26, 78, 15, 0, 5, 10, 1035, -17, 0)
            case .dust:    return (33, 33, 5, 40, 70, 12, 40, 0, 0, 0.8, 1008, 2, 0)
            case .cyclone: return (25, 25, 1, 130, 185, 92, 100, 15.0, 100, 0.8, 950, 23, 65)
            case .blizzard: return (-6, -16, 1, 55, 95, 90, 100, 3.0, 95, 0.3, 992, -8, 75)
            case .freezing: return (-1, -6, 1, 12, 22, 96, 100, 1.5, 90, 3, 1012, -2, 66)
            case .deluge:  return (18, 17, 1, 22, 40, 97, 100, 45.0, 100, 1, 990, 17, 65)
            }
        }
    }

    enum Moment: String, CaseIterable, Identifiable {
        case jour, lever, coucher, nuit
        var id: String { rawValue }
        var libelle: String {
            switch self {
            case .jour: return "Plein jour"; case .lever: return "Lever du soleil"
            case .coucher: return "Coucher du soleil"; case .nuit: return "Nuit"
            }
        }
        var icone: String {
            switch self {
            case .jour: return "sun.max"; case .lever: return "sunrise"; case .coucher: return "sunset"; case .nuit: return "moon.stars"
            }
        }
    }

    var condition: Condition? = nil
    var moment: Moment? = nil
    var alerte = false

    var estActive: Bool { condition != nil || moment != nil || alerte }

    /// Pour les tests automatisés : `WeatherHub --simuler=snow,nuit,alerte`
    /// lance l'app directement sous la neige, de nuit, avec l'alerte.
    /// Chaque morceau est facultatif ; un mot inconnu est ignoré.
    static func depuisArguments(_ arguments: [String]) -> Simulation? {
        guard let a = arguments.first(where: { $0.hasPrefix("--simuler=") }) else { return nil }
        var s = Simulation()
        for mot in a.dropFirst("--simuler=".count).split(separator: ",").map(String.init) {
            if let c = Condition(rawValue: mot) { s.condition = c }
            else if let m = Moment(rawValue: mot) { s.moment = m }
            else if mot == "alerte" { s.alerte = true }
        }
        return s.estActive ? s : nil
    }

    /// L'état réel, avec la simulation par-dessus.
    func appliquer(a etat: WeatherState) -> WeatherState {
        var s = etat
        if let condition {
            let v = condition.valeurs
            s.condition = condition.conditionOW
            s.temperature = v.temperature; s.feelsLike = v.ressenti
            s.uvIndex = v.uv; s.windSpeed = v.vent; s.windGusts = v.rafales
            s.humidity = v.humidite; s.cloudCover = v.nuages
            s.precipitationMm = v.mm; s.precipitationProb = v.proba
            s.visibility = v.visibilite; s.pressure = v.pression; s.dewPoint = v.rosee
            s.weatherCode = v.code
            s.temperatureLow = v.temperature - 0.6; s.temperatureHigh = v.temperature + 0.6
        }
        if let moment {
            let h = 3600.0, now = Date()
            switch moment {
            case .jour:    s.sunrise = now - 6 * h;  s.sunset = now + 6 * h    // midi solaire
            case .lever:   s.sunrise = now - 180;    s.sunset = now + 12 * h   // levé depuis 3 min : braise
            case .coucher: s.sunrise = now - 12 * h; s.sunset = now + 180      // se couche dans 3 min
            case .nuit:
                // Le lever et le coucher de DEMAIN, à des heures plausibles :
                // la tuile Soleil affiche « 07:30 » et non « 21:56 ».
                let cal = Calendar.current, demain = cal.date(byAdding: .day, value: 1, to: now)!
                s.sunrise = cal.date(bySettingHour: 7, minute: 30, second: 0, of: demain)
                s.sunset  = cal.date(bySettingHour: 20, minute: 10, second: 0, of: demain)
            }
        }
        // De nuit, pas d'UV, quelle que soit la condition forcée.
        if PhaseSolaire.maintenant(lever: s.sunrise, coucher: s.sunset).estNuit { s.uvIndex = 0 }
        return s
    }

    /// Une alerte fictive devant les vraies, clairement marquée.
    func alertes(reelles: [AlerteMeteo]) -> [AlerteMeteo] {
        guard alerte else { return reelles }
        let fictive = AlerteMeteo(titre: "Orages violents (simulation)",
                                  detail: "Grêle et rafales à 100 km/h possibles jusqu'à 22 h. Alerte fictive du mode démo.",
                                  niveau: .danger, icone: "cloud.bolt.rain.fill", source: "WeatherHub",
                                  probabilite: 78, fin: Date().addingTimeInterval(4 * 3600))
        return [fictive] + reelles
    }

    /// Les centres autour de la température forcée, sinon la tuile Accord
    /// afficherait « +30,4 » entre le vrai 28 °C et la neige simulée.
    func modeles(reels: [(modele: String, valeur: Double)]) -> [(modele: String, valeur: Double)] {
        guard let condition else { return reels }
        let t = condition.valeurs.temperature, ecarts = [-0.6, 0.4, 0.3, 0.6, -0.2, 0.1]
        return reels.enumerated().map { i, m in (m.modele, t + ecarts[i % ecarts.count]) }
    }

    /// Hier, cohérent avec la température forcée : « −1,3 °C par rapport à hier ».
    func hier(reel: (min: Double, max: Double)?) -> (min: Double, max: Double)? {
        guard let condition else { return reel }
        let t = condition.valeurs.temperature
        return (min: t - 6, max: t + 1.3)
    }

    /// Sous une condition pluvieuse forcée, la pluie commence dans 15 min
    /// et dure — de quoi voir le bandeau et les barres de la tuile.
    func pluie(reelle: [InstantPluie]) -> [InstantPluie] {
        guard let condition, [.rain, .shower, .drizzle, .thunder].contains(condition) else { return reelle }
        return (0..<12).map { i in
            InstantPluie(date: Date().addingTimeInterval(Double(i) * 900),
                         mm: i >= 1 ? condition.valeurs.mm / 4 : 0, probabilite: i >= 1 ? 85 : 20)
        }
    }
}

