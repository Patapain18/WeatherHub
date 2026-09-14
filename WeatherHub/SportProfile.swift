import Foundation
import SwiftUI

// MARK: - Sport favori avec seuils personnalisés

struct FavoriteSport: Identifiable, Codable, Equatable {
    let id: String           // ex: "running"
    var name: String
    var icon: String         // SF Symbol
    var isEnabled: Bool = true

    // Seuils personnalisés
    var maxWindKmh: Double        // km/h max toléré
    var minTempC: Double          // °C min toléré
    var maxTempC: Double          // °C max toléré
    var maxUVIndex: Double        // UV max toléré
    var maxPrecipProb: Int        // % précipitation max toléré
    var maxWindGustsKmh: Double   // km/h rafales max

    // Seuils prédéfinis raisonnables par sport
    static func defaults() -> [FavoriteSport] {
        [
            FavoriteSport(id: "running",    name: "Running",         icon: "figure.run",
                          isEnabled: true,
                          maxWindKmh: 30, minTempC: 0,  maxTempC: 32, maxUVIndex: 8,  maxPrecipProb: 40, maxWindGustsKmh: 40),
            FavoriteSport(id: "cycling",    name: "Vélo",            icon: "bicycle",
                          isEnabled: true,
                          maxWindKmh: 25, minTempC: 5,  maxTempC: 35, maxUVIndex: 9,  maxPrecipProb: 30, maxWindGustsKmh: 35),
            FavoriteSport(id: "basketball", name: "Basket",          icon: "basketball",
                          isEnabled: false,
                          maxWindKmh: 35, minTempC: 5,  maxTempC: 38, maxUVIndex: 10, maxPrecipProb: 20, maxWindGustsKmh: 45),
            FavoriteSport(id: "tennis",     name: "Tennis",          icon: "tennis.racket",
                          isEnabled: false,
                          maxWindKmh: 20, minTempC: 8,  maxTempC: 35, maxUVIndex: 9,  maxPrecipProb: 15, maxWindGustsKmh: 30),
            FavoriteSport(id: "swimming",   name: "Natation",        icon: "figure.pool.swim",
                          isEnabled: false,
                          maxWindKmh: 50, minTempC: 22, maxTempC: 45, maxUVIndex: 11, maxPrecipProb: 60, maxWindGustsKmh: 60),
            FavoriteSport(id: "hiking",     name: "Randonnée",       icon: "figure.hiking",
                          isEnabled: false,
                          maxWindKmh: 40, minTempC: 0,  maxTempC: 30, maxUVIndex: 8,  maxPrecipProb: 35, maxWindGustsKmh: 50),
            FavoriteSport(id: "yoga",       name: "Yoga extérieur",  icon: "figure.mind.and.body",
                          isEnabled: false,
                          maxWindKmh: 20, minTempC: 15, maxTempC: 30, maxUVIndex: 7,  maxPrecipProb: 10, maxWindGustsKmh: 25),
            FavoriteSport(id: "soccer",     name: "Football",        icon: "soccerball",
                          isEnabled: false,
                          maxWindKmh: 40, minTempC: 2,  maxTempC: 36, maxUVIndex: 10, maxPrecipProb: 50, maxWindGustsKmh: 50),
        ]
    }
}

// MARK: - Niveau de condition selon le profil

enum ProfileConditionLevel {
    case perfect   // Toutes les conditions dans les seuils
    case good      // 1 seuil légèrement dépassé
    case acceptable// 2 seuils dépassés
    case bad       // Conditions clairement hors seuils

    var label: String {
        switch self {
        case .perfect:    return "Idéal"
        case .good:       return "Bon"
        case .acceptable: return "Acceptable"
        case .bad:        return "Déconseillé"
        }
    }

    var color: Color {
        switch self {
        case .perfect:    return .green
        case .good:       return Color(red: 0.4, green: 0.8, blue: 0.4)
        case .acceptable: return .orange
        case .bad:        return .red
        }
    }

    var icon: String {
        switch self {
        case .perfect:    return "checkmark.seal.fill"
        case .good:       return "checkmark.circle.fill"
        case .acceptable: return "exclamationmark.circle.fill"
        case .bad:        return "xmark.circle.fill"
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Sensibilité : chaque sport ne craint pas les mêmes choses
// ═══════════════════════════════════════════════════════════════════

/// Combien de points, sur 100, chaque facteur peut coûter à ce sport.
///
/// La somme dépasse volontairement 100 : il suffit alors de deux facteurs
/// au maximum pour ramener le score à zéro, ce qui est le comportement
/// voulu (vent de tempête ET pluie battante = injouable, pas « 45/100 »).
struct PoidsSport {
    let vent: Double
    let rafales: Double
    let froid: Double
    let chaud: Double
    let uv: Double
    let pluie: Double
}

enum SensibiliteSport {

    /// Ces poids ne sont délibérément PAS rangés dans `FavoriteSport` :
    /// cette structure est `Codable` et persistée dans UserDefaults. Y
    /// ajouter des champs obligatoires ferait échouer le décodage des
    /// préférences déjà enregistrées, et les réglages seraient réinitialisés
    /// en silence. Une table à part évite toute migration.
    static func pour(_ id: String) -> PoidsSport {
        switch id {
        // Le vent dévie la balle, la pluie rend le court injouable.
        case "tennis":     return PoidsSport(vent: 30, rafales: 20, froid: 12, chaud: 12, uv: 10, pluie: 35)
        // À vélo, ce sont les rafales qui font tomber, pas le vent établi.
        case "cycling":    return PoidsSport(vent: 25, rafales: 30, froid: 15, chaud: 15, uv: 12, pluie: 30)
        // Effort long et exposé : la chaleur et les UV priment sur le vent.
        case "running":    return PoidsSport(vent: 12, rafales: 10, froid: 18, chaud: 28, uv: 20, pluie: 18)
        // On y va POUR la chaleur : « trop chaud » ne pénalise pas, et la
        // pluie compte peu quand on est déjà dans l'eau.
        case "swimming":   return PoidsSport(vent: 10, rafales: 12, froid: 40, chaud:  0, uv: 22, pluie:  8)
        case "hiking":     return PoidsSport(vent: 15, rafales: 18, froid: 22, chaud: 20, uv: 18, pluie: 25)
        // Équilibre et tapis : le vent est l'ennemi numéro un.
        case "yoga":       return PoidsSport(vent: 28, rafales: 22, froid: 25, chaud: 15, uv: 12, pluie: 35)
        case "basketball": return PoidsSport(vent: 18, rafales: 15, froid: 15, chaud: 18, uv: 12, pluie: 32)
        case "soccer":     return PoidsSport(vent: 15, rafales: 15, froid: 15, chaud: 18, uv: 12, pluie: 22)
        default:           return PoidsSport(vent: 20, rafales: 18, froid: 18, chaud: 18, uv: 15, pluie: 25)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Pénalités continues
// ═══════════════════════════════════════════════════════════════════

/// Remplace les tests binaires `if valeur > seuil`.
///
/// Le problème du seuil sec : un vent à 30,1 km/h coûtait exactement
/// autant qu'un vent à 60 km/h, et 29,9 km/h ne coûtait rien du tout.
/// Ici la pénalité monte progressivement et vaut 0,5 pile au seuil réglé
/// par l'utilisateur.
enum Penalite {

    /// Rampe douce de 0 à 1 entre `bas` et `haut`, en *smoothstep*
    /// (3t² − 2t³). Sa pente est nulle aux deux extrémités : le score
    /// ne « saute » jamais. C'est la même courbe que celle utilisée pour
    /// lisser le bruit du ciel dans Ciel.metal (`bruit()`).
    static func rampe(_ v: Double, bas: Double, haut: Double) -> Double {
        guard haut > bas else { return v >= haut ? 1 : 0 }
        let t = Swift.min(Swift.max((v - bas) / (haut - bas), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Dépassement d'un seuil positif (vent, rafales, UV, % de pluie).
    /// La zone de transition est proportionnelle au seuil : ±40 %.
    static func depassement(_ v: Double, seuil: Double) -> Double {
        guard seuil > 0 else { return v > 0 ? 1 : 0 }
        return rampe(v, bas: seuil * 0.6, haut: seuil * 1.4)
    }

    /// Trop chaud. La transition est en DEGRÉS et non en pourcentage :
    /// une marge proportionnelle sur un seuil de 32 °C commencerait à
    /// pénaliser dès 19 °C, ce qui n'a aucun sens.
    static func tropChaud(_ t: Double, seuil: Double, marge: Double = 5) -> Double {
        rampe(t, bas: seuil - marge, haut: seuil + marge)
    }

    /// Trop froid : même rampe, mais dans l'autre sens. On inverse les
    /// signes pour réutiliser la même fonction.
    static func tropFroid(_ t: Double, seuil: Double, marge: Double = 5) -> Double {
        rampe(-t, bas: -(seuil + marge), haut: -(seuil - marge))
    }
}

/// Ce qu'un facteur météo a coûté au score, et pourquoi.
struct FacteurPenalite: Identifiable {
    let id = UUID()
    let nom: String
    let icone: String
    let penalite: Double        // 0 → 1
    let pointsPerdus: Double    // penalite × poids du facteur pour ce sport
    let detail: String
}

// MARK: - Résultat d'évaluation pour un sport

struct SportEvaluation: Identifiable {
    let id = UUID()
    let sport: FavoriteSport

    /// Score 0–100. 100 = aucune contrainte météo pour CE sport.
    let score: Int

    /// Incertitude du score, en points, héritée du désaccord entre les
    /// modèles de prévision. Un « 72 ± 3 » et un « 72 ± 18 » ne se
    /// décident pas de la même façon.
    let marge: Int

    let level: ProfileConditionLevel
    /// Facteurs triés du plus pénalisant au moins pénalisant.
    let facteurs: [FacteurPenalite]
    let conseils: [String]

    /// « 72 ± 9 » — ou simplement « 72 » si on n'a qu'une seule source.
    var scoreTexte: String { marge > 0 ? "\(score) ± \(marge)" : "\(score)" }

    /// Ce qui pénalise le plus, en une ligne — ou rien à signaler.
    var resume: String {
        guard let pire = facteurs.first, pire.penalite > 0.05 else {
            return "Aucune contrainte pour ce sport"
        }
        return "\(pire.nom) : −\(Int(pire.pointsPerdus.rounded())) pts"
    }

    // ── Compatibilité avec les vues déjà écrites ────────────────────
    // SportProfileView lit `reasons` et `tips`.
    // On les recalcule à partir des facteurs plutôt que de réécrire
    // ces vues : seuls les facteurs qui pèsent vraiment sont cités.
    var reasons: [String] { facteurs.filter { $0.penalite > 0.12 }.map(\.detail) }
    var tips: [String] { conseils }
}

// MARK: - Moteur d'évaluation unifié

/// Le moteur UNIQUE de l'app.
///
/// Il remplace deux systèmes qui coexistaient et pouvaient se contredire :
/// `generateSportConditions()` (5 sports, seuils écrits en dur, verdict à
/// 3 niveaux) et l'ancien `SportEvaluator` (8 sports réglables, mais qui
/// comptait les seuils dépassés un par un sans jamais regarder de combien).
struct SportEvaluator {

    static func evaluate(sport: FavoriteSport, state: WeatherState) -> SportEvaluation {

        // L'orage n'est pas une pénalité parmi d'autres : c'est un veto.
        // Aucun réglage de seuil ne rend la foudre acceptable.
        if state.condition.lowercased().contains("thunder") {
            return SportEvaluation(
                sport: sport, score: 0, marge: 0, level: .bad,
                facteurs: [FacteurPenalite(nom: "Orage", icone: "cloud.bolt.fill",
                                           penalite: 1, pointsPerdus: 100,
                                           detail: "⛈ Orages — dangereux en extérieur")],
                conseils: ["Reportez votre séance ou pratiquez en intérieur."])
        }

        let (score, facteurs) = calculer(sport: sport, state: state, temperature: state.temperature)

        // ── Propagation de l'incertitude ────────────────────────────
        // Deux sources, additionnées :
        //  · l'effet MESURÉ de la dispersion en température — on rejoue
        //    le calcul aux deux extrêmes annoncés par les modèles ;
        //  · le désaccord sur le reste (pluie, vent, nuages), qu'on ne
        //    peut pas rejouer faute de bornes, approché par l'accord
        //    global déjà calculé par le moteur d'ensemble.
        var marge = 0.0
        if state.modelCount > 1 {
            let bas  = calculer(sport: sport, state: state, temperature: state.temperatureLow).0
            let haut = calculer(sport: sport, state: state, temperature: state.temperatureHigh).0
            marge += abs(haut - bas) / 2
            marge += Double(100 - state.reliability) * 0.20
        }

        return SportEvaluation(
            sport: sport,
            score: Int(score.rounded()),
            marge: Int(marge.rounded()),
            level: niveau(pour: score),
            facteurs: facteurs,
            conseils: conseils(pour: facteurs, sport: sport))
    }

    /// Le calcul lui-même. `temperature` est un paramètre plutôt qu'une
    /// lecture directe de `state` : c'est ce qui permet de rejouer le
    /// score aux bornes des modèles pour en déduire la marge.
    private static func calculer(sport: FavoriteSport, state: WeatherState,
                                 temperature: Double) -> (Double, [FacteurPenalite]) {

        let poids = SensibiliteSport.pour(sport.id)
        var facteurs: [FacteurPenalite] = []

        func ajoute(_ nom: String, _ icone: String, _ penalite: Double,
                    _ poidsFacteur: Double, _ detail: String) {
            guard poidsFacteur > 0, penalite > 0.01 else { return }
            facteurs.append(FacteurPenalite(nom: nom, icone: icone, penalite: penalite,
                                            pointsPerdus: penalite * poidsFacteur,
                                            detail: detail))
        }

        ajoute("Vent", "wind",
               Penalite.depassement(state.windSpeed, seuil: sport.maxWindKmh), poids.vent,
               "💨 Vent : \(Int(state.windSpeed)) km/h (votre limite : \(Int(sport.maxWindKmh)))")

        ajoute("Rafales", "wind.circle.fill",
               Penalite.depassement(state.windGusts, seuil: sport.maxWindGustsKmh), poids.rafales,
               "💨 Rafales : \(Int(state.windGusts)) km/h (votre limite : \(Int(sport.maxWindGustsKmh)))")

        ajoute("Froid", "thermometer.snowflake",
               Penalite.tropFroid(temperature, seuil: sport.minTempC), poids.froid,
               "🌡 \(Int(temperature))° (votre minimum : \(Int(sport.minTempC))°)")

        ajoute("Chaleur", "thermometer.sun.fill",
               Penalite.tropChaud(temperature, seuil: sport.maxTempC), poids.chaud,
               "🌡 \(Int(temperature))° (votre maximum : \(Int(sport.maxTempC))°)")

        ajoute("UV", "sun.max.fill",
               Penalite.depassement(state.uvIndex, seuil: sport.maxUVIndex), poids.uv,
               "☀️ UV \(String(format: "%.1f", state.uvIndex)) (votre limite : \(Int(sport.maxUVIndex)))")

        ajoute("Pluie", "cloud.rain.fill",
               Penalite.depassement(Double(state.precipitationProb), seuil: Double(sport.maxPrecipProb)),
               poids.pluie,
               "🌧 Risque de pluie \(state.precipitationProb)% (votre limite : \(sport.maxPrecipProb)%)")

        let perte = facteurs.reduce(0) { $0 + $1.pointsPerdus }
        let score = Swift.max(0, Swift.min(100, 100 - perte))
        return (score, facteurs.sorted { $0.pointsPerdus > $1.pointsPerdus })
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Meilleur créneau de la journée
    // ═══════════════════════════════════════════════════════════════

    /// Rejoue l'évaluation pour chaque heure à venir et retient la
    /// meilleure plage.
    ///
    /// Le moteur ne change pas : on lui présente simplement un
    /// `WeatherState` par heure, construit à partir de la prévision
    /// horaire. Un sport « idéal maintenant » peut très bien être
    /// déconseillé dans trois heures — c'est ça qu'on veut montrer.
    static func meilleurCreneau(sport: FavoriteSport,
                                heures: [PrevisionHeure],
                                base: WeatherState,
                                dureeSeance: Int = 2) -> MeilleurCreneau? {
        guard heures.count >= dureeSeance else { return nil }

        let creneaux: [CreneauSport] = heures.map { h in
            var etat = base
            etat.temperature = h.temperature
            etat.feelsLike = h.ressenti
            etat.windSpeed = h.vent
            etat.windGusts = h.rafales
            etat.uvIndex = h.uv
            etat.precipitationProb = h.probaPluie
            let eval = evaluate(sport: sport, state: etat)
            return CreneauSport(date: h.date, score: eval.score,
                                frein: eval.facteurs.first?.nom)
        }

        // Moyenne glissante sur la durée d'une séance : une heure isolée
        // à 95 entre deux heures à 40 ne fait pas un bon créneau.
        func moyenne(_ i: Int) -> Double {
            let tranche = creneaux[i ..< Swift.min(i + dureeSeance, creneaux.count)]
            return Double(tranche.reduce(0) { $0 + $1.score }) / Double(tranche.count)
        }
        let dernier = creneaux.count - dureeSeance
        guard dernier >= 0 else { return nil }

        var meilleurI = 0, meilleureNote = -1.0
        var pireI = 0, pireNote = 101.0
        for i in 0...dernier {
            let m = moyenne(i)
            if m > meilleureNote { meilleureNote = m; meilleurI = i }
            if m < pireNote { pireNote = m; pireI = i }
        }

        let finIdx = Swift.min(meilleurI + dureeSeance, creneaux.count - 1)

        // On ne signale une plage à éviter que si elle est nettement
        // moins bonne — sinon on invente un problème là où il n'y en a pas.
        var aEviter: (Date, Date, String)? = nil
        if meilleureNote - pireNote >= 20, pireNote < 60 {
            let freinPire = creneaux[pireI].frein ?? "conditions"
            aEviter = (creneaux[pireI].date,
                       creneaux[Swift.min(pireI + dureeSeance, creneaux.count - 1)].date,
                       freinPire)
        }

        return MeilleurCreneau(sport: sport,
                               debut: creneaux[meilleurI].date,
                               fin: creneaux[finIdx].date,
                               score: Int(meilleureNote.rounded()),
                               heures: creneaux,
                               aEviter: aEviter)
    }

    private static func niveau(pour score: Double) -> ProfileConditionLevel {
        switch score {
        case 80...:   return .perfect
        case 60..<80: return .good
        case 35..<60: return .acceptable
        default:      return .bad
        }
    }

    /// Un conseil par facteur qui pèse réellement, dans l'ordre d'importance.
    private static func conseils(pour facteurs: [FacteurPenalite], sport: FavoriteSport) -> [String] {
        let notables = facteurs.filter { $0.penalite > 0.2 }
        guard !notables.isEmpty else {
            return ["Toutes vos conditions sont remplies — bon entraînement !"]
        }
        return notables.prefix(3).map { f in
            switch f.nom {
            case "Vent", "Rafales": return "Choisissez un itinéraire abrité."
            case "Froid":           return "Couvrez-vous et rallongez l'échauffement."
            case "Chaleur":         return "Hydratez-vous toutes les 20 min et évitez 12h–16h."
            case "UV":              return "Crème solaire SPF 50+ et casquette."
            case "Pluie":           return "Vérifiez la météo heure par heure avant de partir."
            default:                return "Adaptez votre séance aux conditions."
            }
        }
    }
}

// MARK: - Persistance UserDefaults

class SportProfileStore: ObservableObject {

    static let shared = SportProfileStore()
    private let key = "favoriteSports_v1"

    @Published var sports: [FavoriteSport] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FavoriteSport].self, from: data) {
            sports = decoded
        } else {
            sports = FavoriteSport.defaults()
        }
    }

    var enabled: [FavoriteSport] { sports.filter { $0.isEnabled } }

    func toggle(_ sport: FavoriteSport) {
        if let idx = sports.firstIndex(where: { $0.id == sport.id }) {
            sports[idx].isEnabled.toggle()
        }
    }

    func update(_ sport: FavoriteSport) {
        if let idx = sports.firstIndex(where: { $0.id == sport.id }) {
            sports[idx] = sport
        }
    }

    func reset() {
        sports = FavoriteSport.defaults()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sports) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
