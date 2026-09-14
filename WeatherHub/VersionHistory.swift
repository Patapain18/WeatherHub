import Foundation

// MARK: - Version Entry

struct AppVersion: Identifiable {
    let id = UUID()
    let number: String       // ex: "1.2.0"
    let date: String         // ex: "Avril 2026"
    let title: String        // ex: "Carte des sports"
    let features: [VersionFeature]
    var isCurrentVersion: Bool = false
}

struct VersionFeature: Identifiable {
    let id = UUID()
    let icon: String         // SF Symbol
    let title: String
    let description: String
    let type: FeatureType
}

enum FeatureType {
    case new        // ✦ Nouveauté
    case improved   // ↑ Amélioration
    case fixed      // ✓ Correction

    var label: String {
        switch self {
        case .new:      return "Nouveau"
        case .improved: return "Amélioré"
        case .fixed:    return "Corrigé"
        }
    }

    var color: String { // pour usage SwiftUI via extension
        switch self {
        case .new:      return "new"
        case .improved: return "improved"
        case .fixed:    return "fixed"
        }
    }
}

// MARK: - Changelog data

struct VersionHistory {

    static let all: [AppVersion] = [

        // ── Version actuelle ────────────────────────────────────────────
        AppVersion(
            number: "1.5.0",
            date: "Avril 2026",
            title: "Profil sportif & Données avancées",
            features: [
                VersionFeature(
                    icon: "person.crop.circle.fill",
                    title: "Profil sportif personnalisé",
                    description: "Choisissez vos sports favoris et définissez vos propres seuils : vent max, température, UV, précipitations. L'app évalue chaque sport selon VOS critères.",
                    type: .new
                ),
                VersionFeature(
                    icon: "slider.horizontal.3",
                    title: "Seuils personnalisables",
                    description: "8 sports disponibles avec 6 seuils ajustables chacun (vent, rafales, temp min/max, UV, précipitations). Persistés entre les sessions.",
                    type: .new
                ),
                VersionFeature(
                    icon: "line.3.horizontal.decrease.circle.fill",
                    title: "Carte améliorée — Filtres par sport",
                    description: "Filtrez les équipements par type de sport (running, vélo, tennis...) avec un compteur de lieux trouvés par catégorie.",
                    type: .improved
                ),
                VersionFeature(
                    icon: "circle.dashed",
                    title: "Rayon de recherche précis",
                    description: "Slider de 500 m à 10 km par pas de 250 m, au lieu des 3 boutons fixes.",
                    type: .improved
                ),
                VersionFeature(
                    icon: "sun.max.fill",
                    title: "Indice UV en temps réel",
                    description: "UV actuel avec barre dégradée verte→violette, niveau texte (Faible à Extrême) et prise en compte dans les conseils sport.",
                    type: .new
                ),
                VersionFeature(
                    icon: "aqi.medium",
                    title: "Qualité de l'air (AQI)",
                    description: "Indice de qualité de l'air 1-5 en temps réel avec couleur et libellé (Bon, Acceptable, Modéré...).",
                    type: .new
                ),
                VersionFeature(
                    icon: "sunrise.fill",
                    title: "Lever & coucher du soleil",
                    description: "Heures précises avec un arc solaire animé montrant la position du soleil en temps réel.",
                    type: .new
                ),
                VersionFeature(
                    icon: "moon.fill",
                    title: "Mode sombre / clair / système",
                    description: "Menu thème dans la barre de navigation avec persistance automatique entre les sessions.",
                    type: .new
                ),
                VersionFeature(
                    icon: "arrow.clockwise",
                    title: "Rafraîchissement manuel",
                    description: "Bouton de rechargement forcé avec indicateur de mise à jour et mention cache.",
                    type: .new
                ),
                VersionFeature(
                    icon: "wind.circle.fill",
                    title: "Rafales, nuages & précipitations",
                    description: "Nouvelle carte atmosphère : rafales de vent, probabilité de pluie, couverture nuageuse et cumul de précipitations.",
                    type: .new
                ),
            ],
            isCurrentVersion: true
        ),

        // ── Historique ──────────────────────────────────────────────────
        AppVersion(
            number: "1.4.0",
            date: "Avril 2026",
            title: "Service météo avancé",
            features: [
                VersionFeature(
                    icon: "server.rack",
                    title: "Architecture WeatherService",
                    description: "Nouvelle couche service dédiée avec cache intelligent (10 min actuel, 30 min prévisions), retry automatique et gestion d'erreurs typée.",
                    type: .improved
                ),
                VersionFeature(
                    icon: "calendar",
                    title: "Prévisions 7 jours",
                    description: "Les prévisions passent de 3 à 7 jours avec min/max et indice UV par jour.",
                    type: .improved
                ),
                VersionFeature(
                    icon: "humidity.fill",
                    title: "Données météo riches",
                    description: "Humidité, ressenti, visibilité et direction du vent enrichissent la carte principale.",
                    type: .new
                ),
            ]
        ),
        AppVersion(
            number: "1.3.0",
            date: "Avril 2026",
            title: "Carte des sports & Nouveautés",
            features: [
                VersionFeature(
                    icon: "map.fill",
                    title: "Carte des équipements",
                    description: "Découvrez les terrains, pistes et salles de sport autour de vous, avec un avis météo en temps réel pour chaque lieu.",
                    type: .new
                ),
                VersionFeature(
                    icon: "location.fill",
                    title: "Géolocalisation",
                    description: "L'app détecte automatiquement votre position pour afficher les équipements sportifs à proximité.",
                    type: .new
                ),
                VersionFeature(
                    icon: "bell.badge.fill",
                    title: "Popup Quoi de neuf",
                    description: "À chaque mise à jour, découvrez les nouveautés en un coup d'œil dès l'ouverture.",
                    type: .new
                ),
                VersionFeature(
                    icon: "envelope.fill",
                    title: "Suggestions",
                    description: "Envoyez vos idées d'amélioration directement depuis l'application.",
                    type: .new
                ),
                VersionFeature(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Navigation corrigée",
                    description: "Le bouton de changement d'onglet restait bloqué — c'est maintenant résolu.",
                    type: .fixed
                ),
            ]
        ),
        AppVersion(
            number: "1.2.0",
            date: "Mars 2026",
            title: "Sport & Conditions",
            features: [
                VersionFeature(
                    icon: "figure.run",
                    title: "Onglet Sport",
                    description: "Consultez les conditions pour 5 sports différents avec des conseils détaillés.",
                    type: .new
                ),
                VersionFeature(
                    icon: "cloud.sun.rain",
                    title: "Animations météo",
                    description: "Pluie, neige et soleil animés selon les conditions réelles.",
                    type: .new
                ),
                VersionFeature(
                    icon: "chart.bar.fill",
                    title: "Prévisions 3 jours",
                    description: "Les prévisions affichent les vraies min/max sur 3 jours consécutifs.",
                    type: .improved
                ),
            ]
        ),
        AppVersion(
            number: "1.1.0",
            date: "Février 2026",
            title: "Double source météo",
            features: [
                VersionFeature(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Double API",
                    description: "OpenWeatherMap + Open-Meteo combinés pour un indice de fiabilité précis.",
                    type: .new
                ),
                VersionFeature(
                    icon: "gauge.with.needle",
                    title: "Indice de fiabilité",
                    description: "Score en % indiquant la cohérence entre les deux sources météo.",
                    type: .new
                ),
            ]
        ),
        AppVersion(
            number: "1.0.0",
            date: "Janvier 2026",
            title: "Lancement",
            features: [
                VersionFeature(
                    icon: "cloud.sun.fill",
                    title: "Météo en temps réel",
                    description: "Première version avec météo par ville et fond dynamique.",
                    type: .new
                ),
            ]
        ),
    ]

    static var current: AppVersion? {
        all.first(where: { $0.isCurrentVersion })
    }

    // MARK: - UserDefaults helpers

    private static let lastSeenKey = "lastSeenVersion"

    static var hasSeenCurrentVersion: Bool {
        UserDefaults.standard.string(forKey: lastSeenKey) == current?.number
    }

    static func markCurrentVersionAsSeen() {
        UserDefaults.standard.set(current?.number, forKey: lastSeenKey)
    }
}
