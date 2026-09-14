import Foundation
import SwiftUI

// MARK: - Compte utilisateur

struct UserAccount: Codable {
    var firstName: String = ""
    var email: String = ""
    var favoriteSportIDs: [String] = []
    var onboardingCompleted: Bool = false
    var registeredAt: Date = Date()
    var notificationsEnabled: Bool = false

    var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") && email.contains(".")
    }

    var initials: String {
        let parts = firstName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Store

final class UserAccountStore: ObservableObject {

    static let shared = UserAccountStore()
    private let key = "userAccount_v1"

    @Published var account: UserAccount {
        didSet { save() }
    }

    var isOnboarded: Bool { account.onboardingCompleted }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(UserAccount.self, from: data) {
            account = decoded
        } else {
            account = UserAccount()
        }
    }

    func completeOnboarding(firstName: String, email: String, sportIDs: [String]) {
        account.firstName = firstName.trimmingCharacters(in: .whitespaces)
        account.email = email.trimmingCharacters(in: .whitespaces)
        account.favoriteSportIDs = sportIDs
        account.onboardingCompleted = true
        account.registeredAt = Date()
        save()

        // Sync avec le profil sportif
        var updated = SportProfileStore.shared.sports
        for i in updated.indices {
            updated[i].isEnabled = sportIDs.contains(updated[i].id)
        }
        SportProfileStore.shared.sports = updated
    }

    func resetOnboarding() {
        account = UserAccount()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Sports disponibles à l'onboarding

struct OnboardingSport: Identifiable {
    let id: String
    let name: String
    let icon: String
    let emoji: String
    let color: Color
    let description: String
}

extension OnboardingSport {
    static let all: [OnboardingSport] = [
        .init(id: "running",    name: "Running",        icon: "figure.run",          emoji: "🏃", color: .orange,  description: "Courir en plein air"),
        .init(id: "cycling",    name: "Vélo",           icon: "bicycle",             emoji: "🚴", color: .green,   description: "Route ou montagne"),
        .init(id: "tennis",     name: "Tennis",         icon: "tennis.racket",       emoji: "🎾", color: .yellow,  description: "Court extérieur"),
        .init(id: "basketball", name: "Basket",         icon: "basketball",          emoji: "🏀", color: Color(red:0.9,green:0.45,blue:0.1), description: "Terrain en plein air"),
        .init(id: "swimming",   name: "Natation",       icon: "figure.pool.swim",    emoji: "🏊", color: .cyan,    description: "Bassin extérieur"),
        .init(id: "hiking",     name: "Randonnée",      icon: "figure.hiking",       emoji: "🥾", color: .brown,   description: "Sentiers & forêts"),
        .init(id: "yoga",       name: "Yoga",           icon: "figure.mind.and.body",emoji: "🧘", color: .purple,  description: "Séance en plein air"),
        .init(id: "soccer",     name: "Football",       icon: "soccerball",          emoji: "⚽", color: .texte,   description: "Terrain gazonné"),
    ]
}
