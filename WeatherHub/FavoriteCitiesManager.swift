import Foundation
import SwiftUI

// MARK: - Ville favorite

struct FavoriteCity: Identifiable, Codable {
    let id: String        // Nom normalisé
    var name: String      // Nom affiché
    var emoji: String     // Emoji pays/région
    var addedAt: Date = Date()
}

// MARK: - Manager

final class FavoriteCitiesManager: ObservableObject {

    static let shared = FavoriteCitiesManager()
    private let key = "favoriteCities_v1"
    private let maxCities = 8

    @Published var cities: [FavoriteCity] {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([FavoriteCity].self, from: data) {
            cities = decoded
        } else {
            // Villes par défaut
            cities = [
                FavoriteCity(id: "paris",  name: "Paris",  emoji: "🇫🇷"),
                FavoriteCity(id: "lyon",   name: "Lyon",   emoji: "🇫🇷"),
            ]
        }
    }

    func add(_ name: String, emoji: String = "📍") {
        let id = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !cities.contains(where: { $0.id == id }),
              cities.count < maxCities else { return }
        cities.insert(FavoriteCity(id: id, name: name, emoji: emoji), at: 0)
    }

    func remove(_ city: FavoriteCity) {
        cities.removeAll { $0.id == city.id }
    }

    func contains(_ name: String) -> Bool {
        let id = name.lowercased().trimmingCharacters(in: .whitespaces)
        return cities.contains { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cities) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
