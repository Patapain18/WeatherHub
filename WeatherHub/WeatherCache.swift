import Foundation

// MARK: - Cache météo avec TTL (Time To Live)

/// Cache léger en mémoire. Évite les appels API redondants.
/// Les données météo actuelles expirent après 10 min, les prévisions après 30 min.
final class WeatherCache {

    static let shared = WeatherCache()
    private init() {}

    private struct Entry {
        let data: Any
        let expiry: Date
        var isValid: Bool { Date() < expiry }
    }

    private var store: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "weatherhub.cache", attributes: .concurrent)

    // MARK: - TTL constants
    static let currentWeatherTTL: TimeInterval = 10 * 60   // 10 min
    static let forecastTTL:       TimeInterval = 30 * 60   // 30 min
    static let airQualityTTL:     TimeInterval = 20 * 60   // 20 min

    // MARK: - Public API

    func get<T>(_ key: String, as type: T.Type) -> T? {
        queue.sync {
            guard let entry = store[key], entry.isValid else { return nil }
            return entry.data as? T
        }
    }

    func set<T>(_ value: T, for key: String, ttl: TimeInterval) {
        queue.async(flags: .barrier) {
            self.store[key] = Entry(data: value, expiry: Date().addingTimeInterval(ttl))
        }
    }

    func invalidate(city: String) {
        queue.async(flags: .barrier) {
            self.store = self.store.filter { !$0.key.hasPrefix(city) }
        }
    }

    func invalidateAll() {
        queue.async(flags: .barrier) { self.store = [:] }
    }

    /// Retourne le temps restant avant expiration d'une clé (pour debug/UI)
    func remainingTTL(for key: String) -> TimeInterval? {
        queue.sync {
            guard let entry = store[key], entry.isValid else { return nil }
            return entry.expiry.timeIntervalSinceNow
        }
    }

    // MARK: - Cache Keys
    struct Keys {
        static func current(_ city: String)    -> String { "\(city).current" }
        static func forecast(_ city: String)   -> String { "\(city).forecast" }
        static func airQuality(_ city: String) -> String { "\(city).aqi" }
        static func geo(_ city: String)        -> String { "\(city).geo" }
    }
}
