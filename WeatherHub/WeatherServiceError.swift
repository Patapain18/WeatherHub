import Foundation

// MARK: - Erreurs typées du service météo

enum WeatherServiceError: LocalizedError {

    case cityNotFound(String)
    case networkUnavailable
    case rateLimited
    case invalidAPIKey
    case serverError(Int)
    case decodingError(String)
    case timeout
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .cityNotFound(let name):  return "Ville « \(name) » introuvable."
        case .networkUnavailable:      return "Pas de connexion réseau."
        case .rateLimited:             return "Limite d'appels API atteinte. Réessayez dans une minute."
        case .invalidAPIKey:           return "Clé API invalide. Vérifiez Config.swift."
        case .serverError(let code):   return "Erreur serveur (\(code)). Réessayez."
        case .decodingError(let info): return "Données invalides reçues : \(info)"
        case .timeout:                 return "Délai dépassé. Vérifiez votre connexion."
        case .unknown(let e):          return e.localizedDescription
        }
    }

    /// Indique si l'erreur est récupérable (retry possible)
    var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .serverError, .timeout: return true
        default: return false
        }
    }

    static func from(_ statusCode: Int) -> WeatherServiceError {
        switch statusCode {
        case 401, 403: return .invalidAPIKey
        case 404:      return .cityNotFound("?")
        case 429:      return .rateLimited
        case 500...599:return .serverError(statusCode)
        default:       return .serverError(statusCode)
        }
    }
}
