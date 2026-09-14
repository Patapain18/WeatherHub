import Foundation

// MARK: - Données riches retournées par le service

struct CurrentWeatherData {
    // Température
    let temperature: Double       // °C (moyenne des deux sources)
    let feelsLike: Double         // °C
    let temperatureOW: Double     // OpenWeatherMap seul (pour la fiabilité)
    let temperatureOM: Double     // Open-Meteo seul
    // Conditions
    let condition: String         // ex: "Rain", "Clear"
    let weatherCode: Int          // WMO code Open-Meteo
    let cloudCover: Int           // %
    // Vent
    let windSpeed: Double         // km/h
    let windDirection: Int        // degrés 0-360
    let windGusts: Double         // km/h (rafales)
    // Atmosphère
    let humidity: Int             // %
    let pressure: Double          // hPa
    let visibility: Double        // km
    let dewPoint: Double          // °C (point de rosée)
    // UV & Air
    let uvIndex: Double           // 0-12
    let aqi: Int                  // 1-5
    let aqiLabel: String
    let aqiIndice: Double         // indice européen 0–120, médiane des sources
    let aqiSources: Int           // modèles ayant répondu
    let aqiAccord: Int            // % d'accord entre eux
    let aqiDominant: String       // polluant qui fixe l'indice
    // Soleil
    let sunrise: Date
    let sunset: Date
    // Précipitations
    let precipitationMm: Double   // mm (dernière heure)
    let precipitationProb: Int    // % probabilité actuelle
    let pays: String              // code ISO, ex. "FR"
}

struct ForecastDayData: Identifiable {
    let id = UUID()
    let date: Date
    let label: String             // "Lun", "Mar"...
    let weatherCode: Int
    let tempMin: Double
    let tempMax: Double
    let uvMax: Double
    let precipitationSum: Double  // mm
    let precipitationProb: Int    // %
    let windSpeedMax: Double      // km/h
    let sunrise: Date?
    let sunset: Date?
}

struct WeatherServiceResult {
    let current: CurrentWeatherData
    let forecast: [ForecastDayData]   // j+1 à j+6
    let fetchedAt: Date
    let cacheHit: Bool
    let multi: MultiModelSnapshot?    // les 4 centres de prévision
    let ensemble: EnsembleSnapshot?   // les 40 membres perturbés
    let air: QualiteAirEnsemble?      // les 3 sources de qualité de l'air

    /// Recopie le résultat en le marquant comme venant du cache.
    /// (Sans ça `cacheHit` restait toujours faux et la mention « (cache) »
    /// ne s'affichait jamais.)
    func marqueCache() -> WeatherServiceResult {
        WeatherServiceResult(current: current, forecast: forecast,
                             fetchedAt: fetchedAt, cacheHit: true,
                             multi: multi, ensemble: ensemble, air: air)
    }

    /// Accord entre les modèles de prévision, de 0 à 100.
    ///
    /// L'ancien calcul comparait deux températures et retranchait 10 points
    /// par degré d'écart — une échelle inventée, aveugle au vent, à la pluie
    /// et aux nuages. Celui-ci agrège l'accord réel sur quatre variables.
    ///
    /// Les poids ne sont pas neutres : la nébulosité pèse le moins, parce
    /// que les modèles divergent structurellement dessus (un écart-type de
    /// 20 points y est banal) sans que la prévision soit mauvaise.
    var reliability: Int {
        var mesures: [(confiance: Double, poids: Double)] = []
        func ajoute(_ v: EnsembleValue?, _ echelle: Double, _ poids: Double) {
            guard let v else { return }
            mesures.append((v.confiance(echelle: echelle), poids))
        }
        ajoute(multi?.temperature,    EchelleDesaccord.temperature, 3)
        ajoute(multi?.probaPluie,     EchelleDesaccord.probaPluie,  3)
        ajoute(multi?.vent,           EchelleDesaccord.vent,        2)
        ajoute(multi?.nuages,         EchelleDesaccord.nuages,      1)
        ajoute(multi?.uv,             EchelleDesaccord.uv,          2)
        ajoute(ensemble?.temperature, EchelleDesaccord.temperature, 2)

        guard !mesures.isEmpty else {
            // Repli sur l'ancienne méthode si aucun modèle n'a répondu :
            // mieux vaut une estimation grossière que pas de chiffre.
            let diff = abs(current.temperatureOW - current.temperatureOM)
            return max(0, 100 - Int(diff * 10))
        }
        let poidsTotal = mesures.reduce(0) { $0 + $1.poids }
        let somme      = mesures.reduce(0) { $0 + $1.confiance * $1.poids }
        return Int((somme / poidsTotal * 100).rounded())
    }
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Décodage des séries multi-modèles
// ═══════════════════════════════════════════════════════════════════

/// Décode un bloc `hourly` dont on ne connaît PAS les clés à la compilation.
///
/// Open-Meteo suffixe chaque variable par le modèle demandé
/// (`temperature_2m_icon_seamless`, `temperature_2m_gfs_seamless`…) ou par
/// le numéro du membre d'ensemble (`temperature_2m_member07`). Impossible
/// de déclarer 40 propriétés à la main : il faut un conteneur à clés libres.
struct OMSeriesHoraires: Decodable {

    let time: [String]
    let series: [String: [Double?]]

    /// Une CodingKey qui accepte n'importe quel nom. C'est ce qui permet
    /// à `container.allKeys` de nous rendre les clés réellement présentes
    /// dans le JSON, au lieu de celles qu'on aurait devinées.
    private struct CleLibre: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CleLibre.self)
        var temps: [String] = []
        var s: [String: [Double?]] = [:]
        for cle in c.allKeys {
            if cle.stringValue == "time" {
                temps = (try? c.decode([String].self, forKey: cle)) ?? []
            } else if let valeurs = try? c.decode([Double?].self, forKey: cle) {
                s[cle.stringValue] = valeurs
            }
        }
        time = temps
        series = s
    }

    /// Toutes les valeurs de `variable` au premier pas de temps — une par
    /// modèle ou par membre.
    ///
    /// Le test `hasPrefix(variable + "_")` est délibéré : avec un simple
    /// `hasPrefix(variable)`, demander "precipitation" ramasserait aussi
    /// "precipitation_probability", et on mélangerait des millimètres avec
    /// des pourcentages.
    /// Toutes les séries d'une variable, rangées par nom de modèle.
    /// Même précaution sur le underscore que `valeursCourantes`.
    func seriesDe(_ variable: String) -> [(modele: String, valeurs: [Double?])] {
        series
            .filter { $0.key == variable || $0.key.hasPrefix(variable + "_") }
            .map { (String($0.key.dropFirst(variable.count).drop(while: { $0 == "_" })), $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    func valeursCourantes(de variable: String) -> [Double?] {
        series
            .filter { $0.key == variable || $0.key.hasPrefix(variable + "_") }
            .compactMap { $0.value.first }
    }
}

private struct OMReponseHoraire: Decodable {
    let hourly: OMSeriesHoraires
}

// ═══════════════════════════════════════════════════════════════════
// MARK: - Photographies d'ensemble
// ═══════════════════════════════════════════════════════════════════

/// Ce que disent les quatre grands centres de prévision, chacun de son côté.
struct MultiModelSnapshot {
    let temperature: EnsembleValue?
    let vent: EnsembleValue?
    let probaPluie: EnsembleValue?
    let nuages: EnsembleValue?
    /// UV : jeu de modèles différent des autres (voir `modelesUV`),
    /// d'où une requête séparée.
    let uv: EnsembleValue?
    /// Rafales et énergie convective — la matière première des alertes.
    let rafales: EnsembleValue?
    let cape: EnsembleValue?

    /// Nombre de modèles ayant répondu sur la température.
    var modeles: Int { temperature?.count ?? 0 }
}

/// Ce que dit un ensemble de membres perturbés d'un même modèle.
///
/// Le principe : on relance le même modèle des dizaines de fois en
/// perturbant légèrement l'état initial. La dispersion des résultats dit
/// à quel point la situation est prévisible.
struct EnsembleSnapshot {
    let temperature: EnsembleValue?
    /// Vent vu par les 40 membres — permet de chiffrer une probabilité
    /// de dépassement, pas seulement une valeur moyenne.
    let vent: EnsembleValue?
    /// Toutes les valeurs de vent des membres, pour compter combien
    /// franchissent un seuil donné.
    let ventMembres: [Double]

    /// Probabilité de pluie EMPIRIQUE : la fraction de membres qui
    /// annoncent des précipitations. C'est ainsi que les vraies prévisions
    /// probabilistes produisent un « risque de pluie » — en comptant les
    /// scénarios, pas en lisant une variable.
    let probaPluieEmpirique: Int?

    let membres: Int
}

/// Une série horaire prête à tracer, avec sa bande d'incertitude.
struct SerieHoraire {

    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let mediane: Double
        /// Bornes basse et haute entre modèles. `nil` quand un seul
        /// modèle publie la variable — l'UV, par exemple.
        let bas: Double?
        let haut: Double?
    }

    let points: [Point]
    /// Ce que dit chaque modèle à l'heure courante : « ICON 20,9 · GFS 20,4 »
    let parModele: [(modele: String, valeur: Double)]

    var nbModeles: Int { parModele.count }
    /// Vrai seulement si on a de quoi tracer une vraie bande.
    var aUneBande: Bool { nbModeles > 1 }
}

// MARK: - Service météo principal

@MainActor
final class WeatherService {

    static let shared = WeatherService()

    /// Créés une fois pour toutes plutôt qu'à chaque prévision décodée.
    /// `en_US_POSIX` sur le parseur : sans lui, un Mac réglé sur un
    /// calendrier non grégorien (bouddhiste, japonais…) échouerait à lire
    /// les dates ISO de l'API, et les prévisions seraient vides.
    private static let formatDateISO: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let formatJourCourt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()
    private init() {}

    private let cache = WeatherCache.shared
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 12
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - Point d'entrée principal

    func fetchAll(city: String, forceRefresh: Bool = false) async throws -> WeatherServiceResult {

        // 1. Géocodage (toujours caché longtemps)
        let (lat, lon) = try await geocode(city: city)

        // 2. Vérifier le cache si on ne force pas le refresh
        if !forceRefresh {
            if let cached = cache.get(WeatherCache.Keys.current(city), as: WeatherServiceResult.self) {
                return cached.marqueCache()
            }
        }

        // 3. Appels parallèles avec retry automatique
        async let owTask    = retry(3) { try await self.fetchOpenWeather(lat: lat, lon: lon) }
        async let omTask    = retry(3) { try await self.fetchOpenMeteo(lat: lat, lon: lon) }
        // La qualité de l'air : trois modèles ramenés au même indice, en
        // best-effort comme l'ensemble (aucune source ne bloque le chargement).
        async let airTask   = self.qualiteAir(lat: lat, lon: lon, heures: 2, avecCapteurs: false)
        // Les deux suivantes sont facultatives : un `try?` plutôt qu'un
        // `try`, pour qu'un ensemble indisponible ne fasse pas échouer
        // tout le chargement. Toutes partent en même temps : ajouter ces
        // requêtes ne rallonge pas le temps total, seule la plus lente compte.
        async let multiTask = try? retry(2) { try await self.fetchMultiModel(lat: lat, lon: lon) }
        async let ensTask   = self.fetchEnsemble(lat: lat, lon: lon)

        let (owData, omData) = try await (owTask, omTask)
        let (multiData, ensData, airData) = await (multiTask, ensTask, airTask)

        // 4. Fusion des données
        let result = try merge(ow: owData, om: omData, air: airData, city: city,
                               multi: multiData, ensemble: ensData)

        // 5. Mise en cache
        cache.set(result, for: WeatherCache.Keys.current(city), ttl: WeatherCache.currentWeatherTTL)

        return result
    }

    // MARK: - Retry générique

    /// Réessaie en espaçant les tentatives.
    ///
    /// Le délai était de 1 s : avec `delay * attempt`, trois tentatives
    /// coûtaient 1 + 2 + 3 = 6 s, cumulées sur le géocodage puis les
    /// appels — d'où les ~15 s de spinner au démarrage. À 0,4 s on
    /// retombe à 2,4 s tout en laissant le temps à un réseau lent.
    private func retry<T>(_ maxAttempts: Int, delay: TimeInterval = 0.4, operation: () async throws -> T) async throws -> T {
        var lastError: Error = WeatherServiceError.unknown(URLError(.timedOut))
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let svcError = mapError(error)
                if !svcError.isRetryable || attempt == maxAttempts { throw svcError }
                try await Task.sleep(nanoseconds: UInt64(delay * Double(attempt) * 1_000_000_000))
            }
        }
        throw lastError
    }

    // MARK: - Fusion des données

    private func merge(ow: OWCurrentResponse, om: OMCurrentForecastResponse,
                       air: QualiteAirEnsemble?, city: String,
                       multi: MultiModelSnapshot?, ensemble: EnsembleSnapshot?) throws -> WeatherServiceResult {

        let owTemp  = ow.main.temp
        let omCurr  = om.current
        let omDaily = om.daily
        // Médiane des quatre modèles si on l'a — sinon l'ancienne moyenne
        // à deux sources. La médiane résiste au modèle qui déraille.
        let avgTemp = multi?.temperature?.median ?? (owTemp + omCurr.temperature_2m) / 2

        // Données actuelles Open-Meteo
        let windKmh   = omCurr.wind_speed_10m                          // déjà en km/h
        let gustsKmh  = omCurr.wind_gusts_10m ?? (windKmh * 1.4)      // estimation si absent
        let owWindKmh = ow.wind.speed * 3.6

        // Précipitation : valeur actuelle ou 0
        let precipNow  = omCurr.precipitation ?? 0
        // Priorité à la probabilité EMPIRIQUE de l'ensemble : c'est la
        // fraction de scénarios qui voient de la pluie, ce qui a un sens
        // physique, contrairement à une moyenne de millimètres.
        let precipProb = ensemble?.probaPluieEmpirique
            ?? multi?.probaPluie.map { Int($0.median.rounded()) }
            ?? currentPrecipProb(from: om)

        // Qualité de l'air : le niveau 1–5 vient de la médiane des modèles
        let aqiVal   = air?.niveau ?? 0
        let aqiLabel = AQILevel.label(for: aqiVal)

        let current = CurrentWeatherData(
            temperature:      avgTemp,
            feelsLike:        omCurr.apparent_temperature ?? ow.main.feels_like,
            temperatureOW:    owTemp,
            temperatureOM:    omCurr.temperature_2m,
            condition:        ow.weather.first?.main ?? "",
            weatherCode:      omCurr.weather_code ?? 0,
            cloudCover:       multi?.nuages.map { Int($0.median.rounded()) } ?? omCurr.cloud_cover ?? 0,
            windSpeed:        multi?.vent?.median ?? (windKmh + owWindKmh) / 2,
            windDirection:    omCurr.wind_direction_10m ?? ow.wind.deg ?? 0,
            windGusts:        gustsKmh,
            humidity:         omCurr.relative_humidity_2m ?? ow.main.humidity,
            pressure:         omCurr.pressure_msl ?? ow.main.pressure ?? 1013,
            visibility:       (ow.visibility ?? 10000) / 1000,
            dewPoint:         omCurr.dew_point_2m ?? dewPointApprox(temp: avgTemp, humidity: Double(ow.main.humidity)),
            uvIndex:          multi?.uv?.median ?? omCurr.uv_index ?? 0,
            aqi:              aqiVal,
            aqiLabel:         aqiLabel,
            aqiIndice:        air?.maintenant?.median ?? 0,
            aqiSources:       air?.nbModeles ?? 0,
            aqiAccord:        air?.accord ?? 0,
            aqiDominant:      air?.dominant ?? "",
            sunrise:          Date(timeIntervalSince1970: ow.sys.sunrise),
            sunset:           Date(timeIntervalSince1970: ow.sys.sunset),
            precipitationMm:  precipNow,
            precipitationProb: precipProb,
            pays:             ow.sys.country ?? ""
        )

        // Prévisions j+1 → j+6
        let forecast = buildForecast(from: omDaily)

        return WeatherServiceResult(current: current, forecast: forecast,
                                    fetchedAt: Date(), cacheHit: false,
                                    multi: multi, ensemble: ensemble, air: air)
    }

    // MARK: - Prévisions

    private func buildForecast(from daily: OMDailyDetailed) -> [ForecastDayData] {
        let total = daily.time.count
        guard total > 1 else { return [] }
        let end = Swift.min(total, 7)
        let dateFmt = Self.formatDateISO
        let dayFmt  = Self.formatJourCourt

        var result: [ForecastDayData] = []
        for i in 1..<end {
            guard let date = dateFmt.date(from: daily.time[i]) else { continue }

            // Lever / coucher : tableau optionnel, on accède avec bounds check
            let sunrise: Date? = {
                guard let arr = daily.sunrise, i < arr.count else { return nil }
                return dateFmt.date(from: String(arr[i].prefix(10)))
            }()
            let sunset: Date? = {
                guard let arr = daily.sunset, i < arr.count else { return nil }
                return dateFmt.date(from: String(arr[i].prefix(10)))
            }()

            result.append(ForecastDayData(
                date:             date,
                label:            dayFmt.string(from: date).capitalized,
                weatherCode:      daily.weathercode[i],
                tempMin:          daily.temperature_2m_min[i],
                tempMax:          daily.temperature_2m_max[i],
                uvMax:            daily.uv_index_max?[i] ?? 0,
                precipitationSum: daily.precipitation_sum?[i] ?? 0,
                precipitationProb: daily.precipitation_probability_max?[i] ?? 0,
                windSpeedMax:     daily.wind_speed_10m_max?[i] ?? 0,
                sunrise:          sunrise,
                sunset:           sunset
            ))
        }
        return result
    }

    // MARK: - Helpers

    private func currentPrecipProb(from om: OMCurrentForecastResponse) -> Int {
        // Prendre la prob de la première heure correspondante
        om.daily.precipitation_probability_max?.first ?? 0
    }

    private func dewPointApprox(temp: Double, humidity: Double) -> Double {
        // Formule de Magnus simplifiée
        let a = 17.27, b = 237.7
        let alpha = (a * temp) / (b + temp) + log(humidity / 100)
        return (b * alpha) / (a - alpha)
    }

    private func mapError(_ error: Error) -> WeatherServiceError {
        if let svcErr = error as? WeatherServiceError { return svcErr }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .networkConnectionLost: return .networkUnavailable
            case .timedOut: return .timeout
            default: return .unknown(error)
            }
        }
        return .unknown(error)
    }

    // MARK: - Networking

    private func fetch<T: Decodable>(_ urlStr: String, as type: T.Type) async throws -> T {
        let data = try await donnees(urlStr)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WeatherServiceError.decodingError(error.localizedDescription)
        }
    }

    /// La requête brute, sans décodage — pour les réponses dont la forme
    /// dépend de la question (un objet ou un tableau, voir `apercus`).
    private func donnees(_ urlStr: String) async throws -> Data {
        guard let url = URL(string: urlStr) else { throw WeatherServiceError.invalidAPIKey }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherServiceError.from(http.statusCode)
        }
        return data
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Barre latérale : la météo du moment de plusieurs villes
    // ═══════════════════════════════════════════════════════════════

    /// La météo du moment de plusieurs villes en UNE requête : Open-Meteo
    /// accepte des listes de coordonnées (`latitude=48.9,47.6`) et répond
    /// par un tableau — ou par un objet seul s'il n'y a qu'une ville, d'où
    /// le double décodage. Le géocodage de chaque ville est caché 24 h
    /// comme pour la ville principale ; le résultat 10 min. Best-effort :
    /// une ville introuvable est simplement absente du dictionnaire.
    func apercus(villes: [String]) async -> [String: ApercuVille] {
        var coords: [(nom: String, lat: Double, lon: Double)] = []
        for nom in villes {
            if let (lat, lon) = try? await geocode(city: nom) { coords.append((nom, lat, lon)) }
        }
        guard !coords.isEmpty else { return [:] }
        let cle = "apercus." + coords.map { $0.nom.lowercased() }.joined(separator: ",")
        if let caches = cache.get(cle, as: [String: ApercuVille].self) { return caches }
        let lats = coords.map { String(format: "%.4f", $0.lat) }.joined(separator: ",")
        let lons = coords.map { String(format: "%.4f", $0.lon) }.joined(separator: ",")
        let url = "\(Config.API.openMeteoBase)/v1/forecast?latitude=\(lats)&longitude=\(lons)"
            + "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=1"
        guard let data = try? await donnees(url) else { return [:] }
        let reponses: [OMApercuReponse]
        if let tableau = try? JSONDecoder().decode([OMApercuReponse].self, from: data) { reponses = tableau }
        else if let seule = try? JSONDecoder().decode(OMApercuReponse.self, from: data) { reponses = [seule] }
        else { return [:] }
        var resultat: [String: ApercuVille] = [:]
        for (c, r) in zip(coords, reponses) {
            resultat[c.nom.lowercased()] = ApercuVille(
                ville: c.nom, temperature: r.current.temperature_2m,
                tMin: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                tMax: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                codeWMO: r.current.weather_code, estJour: r.current.is_day == 1)
        }
        cache.set(resultat, for: cle, ttl: 10 * 60)
        return resultat
    }

    private func geocode(city: String) async throws -> (Double, Double) {
        if let cached = cache.get(WeatherCache.Keys.geo(city), as: (Double, Double).self) {
            return cached
        }
        let enc = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let url = "\(Config.API.openWeatherBase)/geo/1.0/direct?q=\(enc)&limit=1&appid=\(Config.openWeatherAPIKey)"
        let items = try await fetch(url, as: [OWGeoItem].self)
        guard let first = items.first else { throw WeatherServiceError.cityNotFound(city) }
        let coords = (first.lat, first.lon)
        cache.set(coords, for: WeatherCache.Keys.geo(city), ttl: 24 * 3600) // 24h
        cache.set(first.state ?? "", for: Self.cleRegion(city), ttl: 24 * 3600)
        return coords
    }

    private static func cleRegion(_ city: String) -> String {
        "region_" + city.lowercased()
    }

    /// Région déjà connue pour cette ville, si le géocodage a eu lieu.
    private func regionConnue(_ city: String) -> String {
        cache.get(Self.cleRegion(city), as: String.self) ?? ""
    }

    /// Les quatre centres de prévision majeurs, en UNE requête.
    /// `forecast_hours=1` limite la réponse à l'heure en cours (~1,5 Ko).
    private static let modelesMondiaux =
        "icon_seamless,gfs_seamless,ecmwf_ifs025,meteofrance_seamless"

    /// Modèles publiant l'indice UV. Les quatre modèles habituels n'en
    /// donnent qu'UN SEUL (GFS) : ICON, ECMWF et Météo-France ne publient
    /// pas cette variable. Ce jeu-là a été vérifié source par source.
    private static let modelesUV =
        "gfs_seamless,ukmo_seamless,metno_seamless,knmi_seamless"

    /// Tous les modèles ne publient pas toutes les variables : on choisit
    /// le jeu qui répond réellement, plutôt que d'accepter des `null`.
    private static func modeles(pour variable: String) -> String {
        variable == "uv_index" ? modelesUV : modelesMondiaux
    }

    private func fetchMultiModel(lat: Double, lon: Double) async throws -> MultiModelSnapshot {
        let variables = "temperature_2m,wind_speed_10m,precipitation_probability,cloud_cover,wind_gusts_10m,cape"
        let url = "\(Config.API.openMeteoBase)/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=\(variables)&models=\(Self.modelesMondiaux)"
            + "&forecast_hours=1&timezone=auto"

        // Les deux requêtes partent ensemble : l'UV a besoin d'un autre
        // jeu de modèles, mais ne doit pas coûter un aller-retour de plus.
        async let principale = fetch(url, as: OMReponseHoraire.self)
        async let uvTask = fetchUVMultiSource(lat: lat, lon: lon)

        let h = try await principale.hourly
        let uv = await uvTask
        return MultiModelSnapshot(
            temperature: .from(h.valeursCourantes(de: "temperature_2m")),
            vent:        .from(h.valeursCourantes(de: "wind_speed_10m")),
            probaPluie:  .from(h.valeursCourantes(de: "precipitation_probability")),
            nuages:      .from(h.valeursCourantes(de: "cloud_cover")),
            uv:          uv,
            rafales:     .from(h.valeursCourantes(de: "wind_gusts_10m")),
            cape:        .from(h.valeursCourantes(de: "cape"))
        )
    }

    /// L'UV vu par quatre modèles météo plus CAMS. Best-effort.
    private func fetchUVMultiSource(lat: Double, lon: Double) async -> EnsembleValue? {
        let url = "\(Config.API.openMeteoBase)/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=uv_index&models=\(Self.modelesUV)"
            + "&forecast_hours=1&timezone=auto"
        guard let h = try? await fetch(url, as: OMReponseHoraire.self).hourly else { return nil }
        var valeurs = h.valeursCourantes(de: "uv_index")
        if let serie = await serieCAMS(lat: lat, lon: lon, heures: 1), let v = serie.first {
            valeurs.append(v)
        }
        return EnsembleValue.from(valeurs)
    }

    /// L'ensemble à 40 membres. Volontairement en « best-effort » : cette
    /// fonction ne lance JAMAIS d'erreur et renvoie nil en cas de souci.
    /// L'ensemble est un bonus — il ne doit pas empêcher l'app d'afficher
    /// la météo si son serveur est lent ou indisponible.
    private func fetchEnsemble(lat: Double, lon: Double) async -> EnsembleSnapshot? {
        let url = "\(Config.API.openMeteoEnsemble)/v1/ensemble"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=temperature_2m,precipitation,wind_speed_10m&models=icon_global"
            + "&forecast_hours=1&timezone=auto"

        guard let h = try? await fetch(url, as: OMReponseHoraire.self).hourly else { return nil }

        let pluies = h.valeursCourantes(de: "precipitation").compactMap { $0 }
        // On compte les scénarios qui voient de la pluie, plutôt que de
        // moyenner des millimètres : 5 mm chez un membre et 0 chez 39 autres,
        // ce n'est pas « 0,1 mm partout », c'est « 2,5 % de risque ».
        let proba: Int? = pluies.isEmpty ? nil
            : Int((Double(pluies.filter { $0 > 0 }.count) / Double(pluies.count) * 100).rounded())

        let vents = h.valeursCourantes(de: "wind_speed_10m").compactMap { $0 }
        return EnsembleSnapshot(
            temperature: .from(h.valeursCourantes(de: "temperature_2m")),
            vent: .from(h.valeursCourantes(de: "wind_speed_10m")),
            ventMembres: vents,
            probaPluieEmpirique: proba,
            membres: pluies.count
        )
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Détail à la demande (panneaux d'exploration)
    // ═══════════════════════════════════════════════════════════════

    /// Noms lisibles des modèles, pour l'affichage « qui dit quoi ».
    private static let nomsModeles: [String: String] = [
        "icon_seamless": "ICON", "gfs_seamless": "GFS",
        "ecmwf_ifs025": "ECMWF", "meteofrance_seamless": "Météo-France",
        // Le jeu UV : sans ces noms, le pied du panneau afficherait « knmi_seamless ».
        "ukmo_seamless": "UKMO", "metno_seamless": "MET Norway", "knmi_seamless": "KNMI"
    ]

    private static let formatHeureISO: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Série horaire d'une variable, vue par les quatre modèles.
    ///
    /// Chargée seulement quand l'utilisateur ouvre un panneau de détail :
    /// le démarrage de l'app n'en paie pas le prix. Ne lance jamais
    /// d'erreur — un panneau sans données vaut mieux qu'un plantage.
    func serieHoraire(city: String, variable: String, heures: Int = 48) async -> SerieHoraire? {
        guard let (lat, lon) = try? await geocode(city: city) else { return nil }
        let url = "\(Config.API.openMeteoBase)/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=\(variable)&models=\(Self.modeles(pour: variable))"
            + "&forecast_hours=\(heures)&timezone=auto"

        guard let h = try? await fetch(url, as: OMReponseHoraire.self).hourly else { return nil }
        var series = h.seriesDe(variable).filter { s in s.valeurs.contains { $0 != nil } }

        // CAMS est une cinquième source pour l'UV, et surtout une source
        // INDÉPENDANTE : c'est un modèle de chimie atmosphérique, pas un
        // modèle météo. Son désaccord avec les autres est donc informatif.
        if variable == "uv_index", let cams = await serieCAMS(lat: lat, lon: lon, heures: heures) {
            series.append((modele: "CAMS", valeurs: cams))
        }
        guard !series.isEmpty else { return nil }

        var points: [SerieHoraire.Point] = []
        for (i, iso) in h.time.enumerated() {
            guard let date = Self.formatHeureISO.date(from: iso) else { continue }
            let valeurs = series.compactMap { i < $0.valeurs.count ? $0.valeurs[i] : nil }
            guard let stat = EnsembleValue.from(valeurs) else { continue }
            points.append(.init(date: date, mediane: stat.median,
                                bas:  stat.count > 1 ? stat.low  : nil,
                                haut: stat.count > 1 ? stat.high : nil))
        }
        guard !points.isEmpty else { return nil }

        let parModele: [(String, Double)] = series.compactMap { s in
            guard let v = s.valeurs.first ?? nil else { return nil }
            return (Self.nomsModeles[s.modele] ?? s.modele, v)
        }
        return SerieHoraire(points: points, parModele: parModele)
    }

    /// Série UV de CAMS (service européen de surveillance atmosphérique),
    /// servie par l'API qualité de l'air. Best-effort : son absence ne doit
    /// pas priver l'utilisateur des quatre autres sources.
    private func serieCAMS(lat: Double, lon: Double, heures: Int) async -> [Double?]? {
        let url = "\(Config.API.openMeteoAir)/v1/air-quality"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=uv_index&forecast_hours=\(heures)&timezone=auto"
        guard let h = try? await fetch(url, as: OMReponseHoraire.self).hourly else { return nil }
        return h.series["uv_index"]
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Prévision heure par heure
    // ═══════════════════════════════════════════════════════════════

    /// Les prochaines heures, variable par variable.
    ///
    /// Une seule source ici (le « best match » d'Open-Meteo) et non les
    /// quatre modèles : on cherche à classer des créneaux entre eux, pas
    /// à mesurer une incertitude. La dispersion coûterait quatre fois le
    /// volume pour un résultat identique après tri.
    func previsionHoraire(city: String, heures: Int = 24) async -> [PrevisionHeure] {
        guard let (lat, lon) = try? await geocode(city: city) else { return [] }
        let vars = "temperature_2m,apparent_temperature,wind_speed_10m,wind_gusts_10m,uv_index,precipitation_probability,weather_code,cloud_cover,precipitation"
        let url = "\(Config.API.openMeteoBase)/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)&hourly=\(vars)"
            + "&forecast_hours=\(heures)&timezone=auto"

        guard let h = try? await fetch(url, as: OMReponseHoraire.self).hourly else { return [] }
        func serie(_ n: String) -> [Double?] { h.series[n] ?? [] }
        let temps = serie("temperature_2m"), ressentis = serie("apparent_temperature")
        let vents = serie("wind_speed_10m"), rafales = serie("wind_gusts_10m")
        let uvs = serie("uv_index"), pluies = serie("precipitation_probability")
        let codes = serie("weather_code"), nuages = serie("cloud_cover"), mm = serie("precipitation")

        return h.time.enumerated().compactMap { i, iso in
            guard let date = Self.formatHeureISO.date(from: iso),
                  let temp = temps[safe: i] ?? nil else { return nil }
            return PrevisionHeure(
                date: date, temperature: temp,
                ressenti: (ressentis[safe: i] ?? nil) ?? temp,
                vent: (vents[safe: i] ?? nil) ?? 0,
                rafales: (rafales[safe: i] ?? nil) ?? 0,
                uv: (uvs[safe: i] ?? nil) ?? 0,
                probaPluie: Int((pluies[safe: i] ?? nil) ?? 0),
                codeMeteo: Int((codes[safe: i] ?? nil) ?? 0),
                nuages: Int((nuages[safe: i] ?? nil) ?? 0),
                precipitation: (mm[safe: i] ?? nil) ?? 0)
        }
    }

    /// Précipitations au quart d'heure — le « il pleut dans 20 minutes ».
    func pluieProchaine(city: String) async -> [InstantPluie] {
        guard let (lat, lon) = try? await geocode(city: city) else { return [] }
        let url = "\(Config.API.openMeteoBase)/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&minutely_15=precipitation,precipitation_probability"
            + "&forecast_minutely_15=12&timezone=auto"

        guard let data = try? await fetch(url, as: OMReponseMinutely.self) else { return [] }
        let m = data.minutely_15
        let mm = m.series["precipitation"] ?? []
        let prob = m.series["precipitation_probability"] ?? []
        return m.time.enumerated().compactMap { i, iso in
            guard let date = Self.formatHeureISO.date(from: iso) else { return nil }
            return InstantPluie(date: date,
                                mm: (mm[safe: i] ?? nil) ?? 0,
                                probabilite: Int((prob[safe: i] ?? nil) ?? 0))
        }
    }

    /// Températures d'hier, pour donner un repère à celle d'aujourd'hui.
    func hier(city: String) async -> (min: Double, max: Double)? {
        guard let (lat, lon) = try? await geocode(city: city) else { return nil }
        let veille = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let jour = fmt.string(from: veille)
        let url = "https://archive-api.open-meteo.com/v1/archive"
            + "?latitude=\(lat)&longitude=\(lon)&start_date=\(jour)&end_date=\(jour)"
            + "&daily=temperature_2m_max,temperature_2m_min&timezone=auto"

        guard let d = try? await fetch(url, as: OMArchiveReponse.self),
              let mx = d.daily.temperature_2m_max.first ?? nil,
              let mn = d.daily.temperature_2m_min.first ?? nil else { return nil }
        return (mn, mx)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Carte : radar et coordonnées
    // ═══════════════════════════════════════════════════════════════

    /// Les images radar disponibles, du passé (2 h, une toutes les 10 min)
    /// vers la prévision courte. Best-effort.
    func imagesRadar() async -> (hote: String, images: [ImageRadar]) {
        guard let rep = try? await fetch(Config.API.rainViewerAPI, as: RainViewerReponse.self)
        else { return ("", []) }
        let passe = rep.radar.past.map {
            ImageRadar(id: $0.time, date: Date(timeIntervalSince1970: TimeInterval($0.time)),
                       chemin: $0.path, estPrevision: false)
        }
        let futur = (rep.radar.nowcast ?? []).map {
            ImageRadar(id: $0.time, date: Date(timeIntervalSince1970: TimeInterval($0.time)),
                       chemin: $0.path, estPrevision: true)
        }
        return (rep.host, passe + futur)
    }

    /// Coordonnées de la ville affichée, pour centrer la carte.
    /// Passe par le cache du géocodage : gratuit après le premier appel.
    func coordonnees(city: String) async -> (lat: Double, lon: Double)? {
        try? await geocode(city: city)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Autocomplétion de villes
    // ═══════════════════════════════════════════════════════════════

    /// Villes correspondant à un début de saisie.
    ///
    /// Utilise le géocodage d'Open-Meteo plutôt que celui d'OpenWeather :
    /// à qualité de saisie égale, « par » y donne Paris et « lyo » Lyon,
    /// là où OpenWeather renvoie Par (Royaume-Uni) et Lyo (Nigeria) — et
    /// ne trouve carrément rien pour « bloi ».
    ///
    /// Best-effort : une recherche qui échoue ne doit jamais gêner la
    /// frappe, elle rend simplement une liste vide.
    func chercherVilles(_ saisie: String) async -> [VilleSuggestion] {
        let texte = saisie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texte.count >= 2,
              let enc = texte.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }

        // On demande large (20) pour trier nous-mêmes : l'API classe par
        // pertinence brute, ce qui fait passer Touho (Nouvelle-Calédonie,
        // 1 000 habitants) devant Toulouse. Le tri par population remet
        // les grandes villes en tête.
        let url = "https://geocoding-api.open-meteo.com/v1/search"
            + "?name=\(enc)&count=20&language=fr&format=json"

        guard let rep = try? await fetch(url, as: OMGeocodingReponse.self),
              let items = rep.results else { return [] }

        return items
            .map { item in
                VilleSuggestion(
                    id: item.id,
                    nom: item.name,
                    region: item.admin1 ?? "",
                    pays: item.country ?? "",
                    codePays: item.country_code ?? "",
                    population: item.population ?? 0,
                    lat: item.latitude, lon: item.longitude)
            }
            .sorted { $0.population > $1.population }
            .prefix(7)
            .map { $0 }
    }

    /// Enregistre les coordonnées d'une ville choisie dans la liste.
    ///
    /// Sans ça, `geocode(city:)` relancerait une recherche sur le seul nom
    /// et pourrait retomber sur une homonyme — choisir « Paris (Texas) »
    /// puis recevoir la météo de Paris (France).
    func memoriser(_ ville: VilleSuggestion) {
        cache.set((ville.lat, ville.lon), for: WeatherCache.Keys.geo(ville.nom), ttl: 24 * 3600)
        cache.set(ville.region, for: Self.cleRegion(ville.nom), ttl: 24 * 3600)
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Alertes officielles
    // ═══════════════════════════════════════════════════════════════

    /// Pays couverts par MeteoAlarm, du code ISO au nom du flux.
    private static let fluxMeteoAlarm: [String: String] = [
        "FR": "france", "DE": "germany", "ES": "spain", "IT": "italy",
        "BE": "belgium", "NL": "netherlands", "PT": "portugal", "CH": "switzerland",
        "AT": "austria", "GB": "united-kingdom", "IE": "ireland", "LU": "luxembourg",
        "PL": "poland", "SE": "sweden", "NO": "norway", "DK": "denmark",
        "FI": "finland", "CZ": "czechia", "GR": "greece", "HU": "hungary"
    ]

    /// Bulletins officiels des services météo nationaux.
    /// Best-effort : jamais bloquant, jamais d'erreur remontée.
    func alertesOfficielles(lat: Double, lon: Double, pays: String,
                            ville: String, region: String) async -> [AlerteMeteo] {
        if pays.uppercased() == "US" {
            return await alertesNWS(lat: lat, lon: lon)
        }
        if let flux = Self.fluxMeteoAlarm[pays.uppercased()] {
            return await alertesMeteoAlarm(flux: flux, ville: ville, region: region)
        }
        return []
    }

    /// National Weather Service — la seule source qui annonce les tornades,
    /// parce qu'elles sont détectées au radar, pas prévues par un modèle.
    /// L'API exige un User-Agent identifiant, sans quoi elle refuse.
    private func alertesNWS(lat: Double, lon: Double) async -> [AlerteMeteo] {
        guard let url = URL(string: "https://api.weather.gov/alerts/active?point=\(lat),\(lon)") else { return [] }
        var requete = URLRequest(url: url)
        requete.setValue("WeatherHub/\(Config.appVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        requete.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await session.data(for: requete),
              let rep = try? JSONDecoder().decode(NWSReponse.self, from: data) else { return [] }

        return rep.features.compactMap { f in
            let p = f.properties
            guard let evenement = p.event else { return nil }
            return AlerteMeteo(
                titre: evenement,
                detail: p.headline ?? p.description ?? "",
                niveau: Self.niveauNWS(p.severity),
                icone: evenement.lowercased().contains("tornado") ? "tornado" : "exclamationmark.triangle.fill",
                source: "National Weather Service",
                probabilite: nil,
                fin: p.expires.flatMap { ISO8601DateFormatter().date(from: $0) })
        }
    }

    private static func niveauNWS(_ severite: String?) -> NiveauAlerte {
        switch severite?.lowercased() {
        case "extreme":  return .extreme
        case "severe":   return .danger
        case "moderate": return .vigilance
        default:         return .info
        }
    }

    /// MeteoAlarm agrège les vigilances européennes. Deux limites assumées :
    ///  · le flux est NATIONAL — il n'accepte pas de coordonnées, donc on
    ///    affiche les zones concernées et l'utilisateur juge ;
    ///  · il contient énormément de bulletins périmés (142 sur 148 lors des
    ///    essais), d'où le filtrage sur `expires` qui n'est pas optionnel.
    private func alertesMeteoAlarm(flux: String, ville: String, region: String) async -> [AlerteMeteo] {
        let url = "https://feeds.meteoalarm.org/api/v1/warnings/feeds-\(flux)"
        guard let rep = try? await fetch(url, as: MeteoAlarmReponse.self) else { return [] }

        let maintenant = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var vues = Set<String>()
        var resultat: [AlerteMeteo] = []
        var ailleurs = 0

        for bulletin in rep.warnings {
            for info in bulletin.alert.info {
                guard let finTexte = info.expires, let fin = iso.date(from: finTexte),
                      fin > maintenant else { continue }
                let niveau = Self.niveauMeteoAlarm(info.parameter)
                guard niveau >= .vigilance else { continue }   // on tait le bruit vert
                let titre = info.event ?? "Vigilance"
                guard !vues.contains(titre) else { continue }
                vues.insert(titre)

                let zones = info.area?.compactMap { $0.areaDesc } ?? []

                // Le flux étant national, un bulletin peut viser un
                // département à 900 km. On ne lève une vraie alerte que si
                // la zone correspond ; sinon on compte, sans alarmer.
                let meConcerne = zones.contains { z in
                    z.localizedCaseInsensitiveContains(ville)
                    || ville.localizedCaseInsensitiveContains(z)
                    || (!region.isEmpty && z.localizedCaseInsensitiveContains(region))
                }
                guard meConcerne else { ailleurs += 1; continue }

                resultat.append(AlerteMeteo(
                    titre: titre,
                    detail: zones.isEmpty ? "" : "Zones concernées : " + zones.joined(separator: ", "),
                    niveau: niveau,
                    icone: "exclamationmark.triangle.fill",
                    source: "MeteoAlarm",
                    probabilite: nil,
                    fin: fin))
            }
        }
        // L'information reste accessible, mais en simple ligne d'info :
        // savoir qu'il y a des vigilances ailleurs dans le pays est utile,
        // le crier en orange sur l'écran de quelqu'un que ça ne concerne
        // pas ne l'est pas.
        if ailleurs > 0 {
            resultat.append(AlerteMeteo(
                titre: "\(ailleurs) vigilance\(ailleurs > 1 ? "s" : "") ailleurs dans le pays",
                detail: "Aucune ne concerne votre zone.",
                niveau: .info, icone: "info.circle.fill",
                source: "MeteoAlarm", probabilite: nil, fin: nil))
        }
        return resultat
    }

    /// Le niveau utile est dans `awareness_level`, sous la forme
    /// « 3; orange; Moderate ». La sévérité CAP, elle, est peu fiable :
    /// des bulletins « orange canicule » y sont annoncés « Minor ».
    private static func niveauMeteoAlarm(_ parametres: [MAParametre]?) -> NiveauAlerte {
        let brut = parametres?.first { $0.valueName == "awareness_level" }?.value ?? ""
        if brut.contains("red")    { return .extreme }
        if brut.contains("orange") { return .danger }
        if brut.contains("yellow") { return .vigilance }
        return .info
    }

    /// Toutes les alertes : celles qu'on calcule (partout dans le monde)
    /// et celles des services officiels (là où ils existent).
    /// Les bulletins officiels seuls (Météo-France, NWS…), sans nos calculs.
    /// Le ViewModel recalcule les alertes maison sur l'état AFFICHÉ, pour
    /// que le mode démo montre la consigne d'une tornade simulée.
    func bulletinsOfficiels(city: String, pays: String) async -> [AlerteMeteo] {
        guard !pays.isEmpty, let (lat, lon) = try? await geocode(city: city) else { return [] }
        return await alertesOfficielles(lat: lat, lon: lon, pays: pays, ville: city, region: regionConnue(city))
    }

    /// Les officielles d'abord à niveau égal : un bulletin du NWS ou de
    /// Météo-France prime sur notre estimation.
    static func trier(_ alertes: [AlerteMeteo]) -> [AlerteMeteo] {
        alertes.sorted { $0.niveau != $1.niveau ? $0.niveau > $1.niveau : ($0.estOfficielle && !$1.estOfficielle) }
    }

    func alertes(city: String, state: WeatherState,
                 multi: MultiModelSnapshot?, ensemble: EnsembleSnapshot?) async -> [AlerteMeteo] {
        var toutes = MoteurAlertes.calculer(
            state: state,
            rafales: multi?.rafales,
            cape: multi?.cape,
            ventMembres: ensemble?.ventMembres ?? [])

        if !state.pays.isEmpty, let (lat, lon) = try? await geocode(city: city) {
            toutes += await alertesOfficielles(lat: lat, lon: lon, pays: state.pays,
                                               ville: city, region: regionConnue(city))
        }
        // Les officielles d'abord à niveau égal : un bulletin du NWS ou de
        // Météo-France prime sur notre estimation.
        return toutes.sorted {
            $0.niveau != $1.niveau ? $0.niveau > $1.niveau : ($0.estOfficielle && !$1.estOfficielle)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // MARK: - Qualité de l'air multi-sources
    // ═══════════════════════════════════════════════════════════════

    /// Trois modèles, un seul barème. CAMS Europe et CAMS global viennent
    /// de Copernicus (deux chaînes différentes : régionale à 10 km, mondiale
    /// à 40 km), OpenWeather a la sienne. Chacun publie ses concentrations ;
    /// on recalcule l'indice européen nous-mêmes et on prend la médiane —
    /// exactement ce qu'on fait pour la température avec les quatre centres.
    /// `avecCapteurs` ajoute la mesure des capteurs citoyens du voisinage,
    /// gardée à part de la médiane (particules seulement).
    func qualiteAir(lat: Double, lon: Double, heures: Int, avecCapteurs: Bool) async -> QualiteAirEnsemble? {
        async let europe  = sourceCAMS(lat: lat, lon: lon, heures: heures, domaine: "cams_europe", nom: "CAMS Europe")
        async let global  = sourceCAMS(lat: lat, lon: lon, heures: heures, domaine: "cams_global", nom: "CAMS global")
        async let ow      = sourceOpenWeather(lat: lat, lon: lon, heures: heures)
        async let capteurs: SourceAir? = avecCapteurs ? capteursCitoyens(lat: lat, lon: lon) : nil
        let sources = await [europe, global, ow, capteurs].compactMap { $0 }
        let modeles = sources.filter { !$0.estMesure }
        guard !modeles.isEmpty else { return nil }

        // La frise horaire de référence : celle du modèle qui en a le plus.
        let reference = modeles.max { $0.heures.count < $1.heures.count }!.heures
        var mediane: [Double?] = [], bas: [Double?] = [], haut: [Double?] = []
        // Pour chaque heure, ce que dit chaque modèle à cette heure-là
        let index: [[Date: Double]] = modeles.map { m in
            Dictionary(uniqueKeysWithValues: zip(m.heures, m.indice).compactMap { d, v in v.map { (d, $0) } })
        }
        for h in reference {
            let v = EnsembleValue.from(index.map { $0[h] })
            mediane.append(v?.median); bas.append(v?.low); haut.append(v?.high)
        }
        return QualiteAirEnsemble(sources: sources, heures: reference, mediane: mediane, bas: bas, haut: haut)
    }

    /// Même chose depuis un nom de ville, avec les capteurs — pour le panneau.
    func qualiteAir(city: String, heures: Int = 48) async -> QualiteAirEnsemble? {
        guard let (lat, lon) = try? await geocode(city: city) else { return nil }
        return await qualiteAir(lat: lat, lon: lon, heures: heures, avecCapteurs: true)
    }

    /// Un des deux domaines CAMS servis par Open-Meteo.
    private func sourceCAMS(lat: Double, lon: Double, heures: Int, domaine: String, nom: String) async -> SourceAir? {
        let url = "\(Config.API.openMeteoAir)/v1/air-quality"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=pm2_5,pm10,nitrogen_dioxide,ozone,sulphur_dioxide"
            + "&domains=\(domaine)&forecast_hours=\(heures)&timezone=auto"
        guard let h = try? await fetch(url, as: OMReponseHoraire.self).hourly else { return nil }
        func serie(_ n: String) -> [Double?] { h.series[n] ?? [] }
        let (pm25, pm10, no2, o3, so2) = (serie("pm2_5"), serie("pm10"), serie("nitrogen_dioxide"), serie("ozone"), serie("sulphur_dioxide"))
        var dates: [Date] = [], indices: [Double?] = [], dominants: [String?] = []
        for (i, iso) in h.time.enumerated() {
            guard let d = Self.formatHeureISO.date(from: iso) else { continue }
            let r = IndiceEuropeen.indice(pm25: pm25[safe: i] ?? nil, pm10: pm10[safe: i] ?? nil,
                                          no2: no2[safe: i] ?? nil, o3: o3[safe: i] ?? nil, so2: so2[safe: i] ?? nil)
            dates.append(d); indices.append(r?.valeur); dominants.append(r?.dominant)
        }
        guard !dates.isEmpty else { return nil }
        let concentrations: [(String, Double)] = [("PM2.5", pm25.first ?? nil), ("PM10", pm10.first ?? nil),
                                                  ("NO₂", no2.first ?? nil), ("O₃", o3.first ?? nil)]
            .compactMap { n, v in v.map { (n, $0) } }
        return SourceAir(nom: nom, estMesure: false, heures: dates, indice: indices,
                         maintenant: indices.first ?? nil, dominant: dominants.first ?? nil,
                         concentrations: concentrations, nbCapteurs: 0)
    }

    /// OpenWeather : prévision horaire sur 4 jours, en UTC.
    private func sourceOpenWeather(lat: Double, lon: Double, heures: Int) async -> SourceAir? {
        let url = "\(Config.API.openWeatherBase)/data/2.5/air_pollution/forecast?lat=\(lat)&lon=\(lon)&appid=\(Config.openWeatherAPIKey)"
        guard let r = try? await fetch(url, as: OWAirForecastResponse.self) else { return nil }
        // On garde l'heure en cours et les suivantes, pas le passé de la liste
        let debut = Date().addingTimeInterval(-3600)
        let entrees = r.list.filter { Date(timeIntervalSince1970: TimeInterval($0.dt)) >= debut }.prefix(heures)
        guard !entrees.isEmpty else { return nil }
        var dates: [Date] = [], indices: [Double?] = [], dominants: [String?] = []
        for e in entrees {
            let c = e.components
            let r = IndiceEuropeen.indice(pm25: c.pm2_5, pm10: c.pm10, no2: c.no2, o3: c.o3, so2: c.so2)
            dates.append(Date(timeIntervalSince1970: TimeInterval(e.dt))); indices.append(r?.valeur); dominants.append(r?.dominant)
        }
        let c = entrees.first!.components
        let concentrations: [(String, Double)] = [("PM2.5", c.pm2_5), ("PM10", c.pm10), ("NO₂", c.no2), ("O₃", c.o3)]
            .compactMap { n, v in v.map { (n, $0) } }
        return SourceAir(nom: "OpenWeather", estMesure: false, heures: dates, indice: indices,
                         maintenant: indices.first ?? nil, dominant: dominants.first ?? nil,
                         concentrations: concentrations, nbCapteurs: 0)
    }

    /// Les capteurs Sensor.Community dans un rayon de 5 km : une MESURE,
    /// pas un modèle — mais des particules seulement (SDS011 & co), rien
    /// sur l'ozone ni le dioxyde d'azote. Médiane des capteurs, pour qu'un
    /// capteur posé au soleil ou près d'un barbecue ne parle pas pour tous.
    private func capteursCitoyens(lat: Double, lon: Double) async -> SourceAir? {
        let url = "https://data.sensor.community/airrohr/v1/filter/area=\(lat),\(lon),5"
        guard let mesures = try? await fetch(url, as: [SCMesure].self) else { return nil }
        var pm25: [Double] = [], pm10: [Double] = []
        for m in mesures {
            for v in m.sensordatavalues {
                guard let x = Double(v.value), x >= 0, x < 1000 else { continue }
                if v.value_type == "P2" { pm25.append(x) } else if v.value_type == "P1" { pm10.append(x) }
            }
        }
        guard let p25 = EnsembleValue.from(pm25)?.median, let p10 = EnsembleValue.from(pm10)?.median else { return nil }
        let r = IndiceEuropeen.indice(pm25: p25, pm10: p10, no2: nil, o3: nil, so2: nil)
        // Un capteur envoie plusieurs relevés en quelques minutes : on compte les capteurs, pas les relevés
        let nb = Set(mesures.filter { $0.sensordatavalues.contains { $0.value_type == "P2" } }.map(\.sensor.id)).count
        return SourceAir(nom: "Capteurs citoyens", estMesure: true, heures: [], indice: [],
                         maintenant: r?.valeur, dominant: r?.dominant,
                         concentrations: [("PM2.5", p25), ("PM10", p10)], nbCapteurs: nb)
    }

    private func fetchOpenWeather(lat: Double, lon: Double) async throws -> OWCurrentResponse {
        let url = "\(Config.API.openWeatherBase)/data/2.5/weather?lat=\(lat)&lon=\(lon)&appid=\(Config.openWeatherAPIKey)&units=metric"
        return try await fetch(url, as: OWCurrentResponse.self)
    }

    private func fetchOpenMeteo(lat: Double, lon: Double) async throws -> OMCurrentForecastResponse {
        let current = "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,dew_point_2m"
        let daily   = "weathercode,temperature_2m_max,temperature_2m_min,uv_index_max,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,sunrise,sunset"
        let url = "\(Config.API.openMeteoBase)/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=\(current)&daily=\(daily)&timezone=auto&forecast_days=7"
        return try await fetch(url, as: OMCurrentForecastResponse.self)
    }

}


// MARK: - Aperçu d'une ville (barre latérale)

/// Ce qu'affiche une rangée de la barre latérale : la météo du moment
/// d'une ville, en trois nombres et une icône.
struct ApercuVille: Codable, Equatable {
    let ville: String
    let temperature: Double
    let tMin: Double
    let tMax: Double
    let codeWMO: Int
    let estJour: Bool
    /// Pour la ville affichée : la même icône et le même mot que l'en-tête
    /// (qui viennent d'OpenWeather), plutôt que le code WMO d'Open-Meteo —
    /// les deux sources ne sont pas toujours d'accord, et une rangée qui
    /// contredit l'en-tête juste à côté serait troublante.
    var iconeForcee: String? = nil
    var libelleForce: String? = nil

    var icone: String { iconeForcee ?? iconePourCodeWMO(codeWMO, nuit: !estJour) }
    var libelle: String { libelleForce ?? libellePourCodeWMO(codeWMO) }
}

struct OMApercuReponse: Decodable {
    struct Courant: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
    struct Journee: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
    let current: Courant
    let daily: Journee
}
