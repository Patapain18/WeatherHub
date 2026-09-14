import Foundation
import MapKit

// MARK: - Sport Venue

struct SportVenue: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let sportType: SportVenueType
    var weatherAdvice: VenueWeatherAdvice = .unknown
}

enum SportVenueType: String, CaseIterable {
    case running     = "Piste de course"
    case cycling     = "Piste cyclable"
    case tennis      = "Tennis"
    case basketball  = "Basket"
    case soccer      = "Football"
    case swimming    = "Piscine"
    case gym         = "Salle de sport"
    case park        = "Parc"

    var sfSymbol: String {
        switch self {
        case .running:    return "figure.run"
        case .cycling:    return "bicycle"
        case .tennis:     return "tennis.racket"
        case .basketball: return "basketball"
        case .soccer:     return "soccerball"
        case .swimming:   return "figure.pool.swim"
        case .gym:        return "dumbbell"
        case .park:       return "leaf"
        }
    }

    var isOutdoor: Bool {
        switch self {
        case .gym, .swimming: return false
        default: return true
        }
    }

    /// Termes de recherche MapKit pour ce type de lieu
    var searchTerms: [String] {
        switch self {
        case .running:    return ["piste de course", "running track", "jogging"]
        case .cycling:    return ["piste cyclable", "véloroute", "bike path"]
        case .tennis:     return ["court de tennis", "tennis"]
        case .basketball: return ["terrain de basket", "basketball court"]
        case .soccer:     return ["terrain de football", "stade", "football"]
        case .swimming:   return ["piscine", "swimming pool"]
        case .gym:        return ["salle de sport", "fitness", "gym"]
        case .park:       return ["parc", "jardin public", "park"]
        }
    }
}

enum VenueWeatherAdvice {
    case recommended    // ✅ Conditions idéales
    case acceptable     // ⚠️ Praticable avec précautions
    case notRecommended // ❌ Déconseillé
    case unknown

    var emoji: String {
        switch self {
        case .recommended:    return "✅"
        case .acceptable:     return "⚠️"
        case .notRecommended: return "❌"
        case .unknown:        return "—"
        }
    }

    var label: String {
        switch self {
        case .recommended:    return "Idéal"
        case .acceptable:     return "Praticable"
        case .notRecommended: return "Déconseillé"
        case .unknown:        return "Inconnu"
        }
    }

    var reason: String {
        "Basé sur la météo actuelle"
    }
}

// MARK: - Nearby Search Service

@MainActor
final class NearbySearchService {

    /// Cherche les équipements sportifs autour d'une coordonnée, dans un rayon en mètres
    func search(near coordinate: CLLocationCoordinate2D, radiusMeters: Double = 2000) async -> [SportVenue] {
        var results: [SportVenue] = []

        for type in SportVenueType.allCases {
            let term = type.searchTerms.first ?? type.rawValue
            let venues = await searchMapKit(term: term, coordinate: coordinate, radius: radiusMeters, type: type)
            results.append(contentsOf: venues)
        }

        // Dédoublonnage par nom similaire
        return deduplicate(results)
    }

    private func searchMapKit(
        term: String,
        coordinate: CLLocationCoordinate2D,
        radius: Double,
        type: SportVenueType
    ) async -> [SportVenue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            return response.mapItems.prefix(3).map { item in
                SportVenue(
                    name: item.name ?? type.rawValue,
                    coordinate: item.placemark.coordinate,
                    sportType: type
                )
            }
        } catch {
            return []
        }
    }

    private func deduplicate(_ venues: [SportVenue]) -> [SportVenue] {
        var seen: Set<String> = []
        return venues.filter { venue in
            let key = venue.name.lowercased().prefix(12).description
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Weather Advice Calculator

struct WeatherAdviceCalculator {

    static func advice(for venue: SportVenue, condition: String, temp: Double, wind: Double) -> VenueWeatherAdvice {
        let c = condition.lowercased()
        let isRain    = c.contains("rain") || c.contains("drizzle")
        let isThunder = c.contains("thunder")
        let isSnow    = c.contains("snow")
        let isWindy   = wind > 25
        let isCold    = temp < 3
        let isHot     = temp > 34

        // Lieux couverts → toujours OK sauf orage électrique extrême
        if !venue.sportType.isOutdoor {
            return isThunder ? .acceptable : .recommended
        }

        // Lieux extérieurs
        if isThunder { return .notRecommended }
        if isSnow    { return .notRecommended }

        switch venue.sportType {
        case .running:
            if isRain            { return .notRecommended }
            if isWindy || isCold { return .acceptable }
            if isHot             { return .acceptable }
            return .recommended

        case .cycling:
            if isRain || isWindy { return .notRecommended }
            if isCold            { return .acceptable }
            return .recommended

        case .tennis:
            if isRain            { return .notRecommended }
            if isWindy           { return .acceptable }
            return .recommended

        case .basketball:
            if isRain            { return .notRecommended }
            if isWindy           { return .acceptable }
            return .recommended

        case .soccer:
            if isRain || isWindy { return .acceptable }
            return .recommended

        case .park:
            if isRain            { return .acceptable }
            return .recommended

        default:
            return isRain ? .acceptable : .recommended
        }
    }

    static func reasonDetail(for venue: SportVenue, condition: String, temp: Double, wind: Double) -> String {
        let c = condition.lowercased()
        let isRain    = c.contains("rain") || c.contains("drizzle")
        let isThunder = c.contains("thunder")
        let isSnow    = c.contains("snow")
        let isWindy   = wind > 25

        if isThunder { return "Orages — dangereux en extérieur" }
        if isSnow    { return "Neige — terrain impraticable" }
        if isRain && venue.sportType.isOutdoor {
            switch venue.sportType {
            case .running:    return "Pluie — risque de glissade"
            case .cycling:    return "Pluie — chaussée glissante"
            case .tennis:     return "Pluie — court glissant"
            case .basketball: return "Pluie — terrain glissant"
            default:          return "Pluie — conditions difficiles"
            }
        }
        if isWindy { return "Vent fort (\(Int(wind)) km/h)" }
        if temp < 3 { return "Températures très basses (\(Int(temp))°C)" }
        if temp > 34 { return "Forte chaleur (\(Int(temp))°C)" }
        return "Conditions favorables"
    }
}
