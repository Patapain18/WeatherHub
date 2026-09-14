import SwiftUI

// ╔══════════════════════════════════════════════════════════════════╗
// ║  BarreVilles — la barre latérale des villes, façon Apple Météo   ║
// ║  Chaque favori avec sa météo du moment. Elle n'apparaît que sur  ║
// ║  les fenêtres larges (≥ 1 100 pt) : en dessous, les pastilles    ║
// ║  au-dessus de la grille reprennent le relais.                    ║
// ╚══════════════════════════════════════════════════════════════════╝

struct BarreVilles: View {
    @ObservedObject var vm: WeatherViewModel
    @StateObject private var favoris = FavoriteCitiesManager.shared

    static let largeur: CGFloat = 270
    /// En dessous, la barre se replie : 720 de contenu + 2 × 36 de marge
    /// + la barre + un peu d'air.
    static let largeurMinimaleFenetre: CGFloat = 1100

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Villes")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(.texte.opacity(0.5))
                .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    // La ville affichée passe en tête si elle n'est pas un favori
                    if !favoris.contains(vm.city) {
                        rangee(nom: vm.city, emoji: "📍", favori: nil)
                    }
                    ForEach(favoris.cities) { ville in
                        rangee(nom: ville.name, emoji: ville.emoji, favori: ville)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)

            Text(favoris.cities.count < 8
                 ? "L'étoile en haut de la météo ajoute une ville ici."
                 : "Huit favoris au maximum.")
                .font(.system(size: 10.5))
                .foregroundColor(.texte.opacity(0.4))
                .padding(.horizontal, 24).padding(.bottom, 22)
        }
        .frame(width: Self.largeur)
        .frame(maxHeight: .infinity)
        // Le matériau laisse voir le ciel (le MTKView est derrière), le
        // voile garantit le contraste du texte, quel que soit le ciel.
        .background(.ultraThinMaterial)
        .background(Color.texteInverse.opacity(0.14))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.surface.opacity(0.14)).frame(width: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Villes")
    }

    /// Une rangée : nom et drapeau à gauche, icône et température à
    /// droite, et en dessous la condition et les extrêmes du jour.
    private func rangee(nom: String, emoji: String, favori: FavoriteCity?) -> some View {
        let active = vm.city.lowercased() == nom.lowercased()
        let apercu = vm.apercus[nom.lowercased()]
        return Button {
            guard !active else { return }
            vm.city = nom
            vm.fetchWeather()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(emoji).font(.system(size: 13))
                        Text(nom).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    }
                    Text(apercu?.libelle ?? (favori == nil ? "Ville en cours" : "Chargement…"))
                        .font(.system(size: 11)).opacity(0.62).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let apercu {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: apercu.icone)
                                .font(.system(size: 14, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text(typoMoins("\(Int(apercu.temperature.rounded()))°"))
                                .font(.system(size: 22, weight: .medium, design: .rounded))
                        }
                        Text(typoMoins("↑\(Int(apercu.tMax.rounded()))°  ↓\(Int(apercu.tMin.rounded()))°"))
                            .font(.system(size: 10.5, weight: .medium)).opacity(0.55)
                    }
                } else {
                    ProgressView().controlSize(.small).opacity(0.6)
                }
            }
            .foregroundColor(active ? .texteInverse : .texte)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(active ? AnyShapeStyle(Color.texte) : AnyShapeStyle(Color.texteInverse.opacity(0.14)))
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(apercu.map { "\(nom), \($0.libelle), \(Int($0.temperature.rounded())) degrés" } ?? nom)
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .contextMenu {
            if let favori {
                Button(role: .destructive) { favoris.remove(favori) } label: {
                    Label("Retirer des favoris", systemImage: "star.slash")
                }
            } else {
                Button { favoris.add(nom, emoji: "📍") } label: {
                    Label("Ajouter aux favoris", systemImage: "star")
                }
            }
        }
    }
}

// MARK: - Environnement : la barre est-elle affichée ?

/// Quand la barre est là, la rangée de pastilles au-dessus de la grille
/// ferait doublon : WeatherTabView la cache en lisant cette valeur.
private struct BarreVillesVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var barreVillesVisible: Bool {
        get { self[BarreVillesVisibleKey.self] }
        set { self[BarreVillesVisibleKey.self] = newValue }
    }
}
