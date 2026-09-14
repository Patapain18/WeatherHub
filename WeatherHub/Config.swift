// MARK: - Configuration
// La clé API vit dans Cles.swift, qui est ignoré par git : ce fichier-ci
// peut être partagé, la clé jamais.

enum Config {
    static let openWeatherAPIKey = Cles.openWeather
    static let appVersion = "1.5.0"

    enum API {
        static let openWeatherBase = "https://api.openweathermap.org"
        static let openMeteoBase   = "https://api.open-meteo.com"
        static let openMeteoEnsemble = "https://ensemble-api.open-meteo.com"
        static let openMeteoAir      = "https://air-quality-api.open-meteo.com"
        static let rainViewerAPI     = "https://api.rainviewer.com/public/weather-maps.json"
        static let openWeatherTuiles = "https://tile.openweathermap.org/map"
    }
}
