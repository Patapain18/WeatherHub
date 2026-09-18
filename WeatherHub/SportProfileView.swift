import SwiftUI

// MARK: - Le profil sportif, en feuille de réglages

/// Ouvert depuis la bulle « réglages » de l'onglet Sport (ce n'était plus
/// un onglet à part entière : on n'y va que pour régler ses sports). La
/// section « Conditions aujourd'hui » est partie — l'onglet Sport dit
/// déjà tout ça, en mieux.
struct SportProfileView: View {
    @ObservedObject var vm: WeatherViewModel
    @StateObject private var store = SportProfileStore.shared
    @State private var expandedSport: String? = nil
    @State private var editingSport: FavoriteSport? = nil
    @Environment(\.dismiss) private var fermer

    /// 640 de large ; en hauteur, ce que l'écran permet.
    private var hauteur: CGFloat {
        min(660, (NSScreen.main?.visibleFrame.height ?? 800) - 120)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // MARK: Header
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 36))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.texte, .cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mon profil sportif")
                            .font(.title2.bold()).foregroundColor(.texte)
                        Text("Vos sports, et les seuils qui comptent pour chacun")
                            .font(.subheadline).foregroundColor(.texte.opacity(0.55))
                    }
                    Spacer()
                    Button { fermer() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.texte.opacity(0.66))
                            .frame(width: 24, height: 24)
                            .background(Color.surface.opacity(0.12)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("Fermer")
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 22)

                // MARK: Liste tous les sports
                VStack(spacing: 12) {
                    HStack {
                        Text("Mes sports")
                            .font(.headline).foregroundColor(.texte)
                        Spacer()
                        Button("Réinitialiser") { store.reset() }
                            .font(.caption).foregroundColor(.texte.opacity(0.4))
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)

                    ForEach($store.sports) { $sport in
                        SportRowCard(sport: $sport,
                                     isExpanded: expandedSport == sport.id,
                                     onToggleExpand: {
                                         withAnimation(.spring(duration: 0.45, bounce: 0.22)) {
                                             expandedSport = expandedSport == sport.id ? nil : sport.id
                                         }
                                     },
                                     onToggleEnabled: { store.toggle(sport) })
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .frame(width: 640, height: hauteur)
        .fondCarte()
        .sheet(item: $editingSport) { sport in
            SportThresholdEditor(sport: sport) { updated in
                store.update(updated)
            }
        }
    }
}

// MARK: - Carte sport (liste complète)

struct SportRowCard: View {
    @Binding var sport: FavoriteSport
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleEnabled: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header cliquable
            HStack(spacing: 14) {
                // Toggle activé/désactivé
                Button { onToggleEnabled() } label: {
                    Image(systemName: sport.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(sport.isEnabled ? .cyan : .texte.opacity(0.3))
                }
                .buttonStyle(.plain)

                Image(systemName: sport.icon)
                    .font(.title3).foregroundColor(.texte).frame(width: 28)

                Text(sport.name)
                    .font(.headline).foregroundColor(sport.isEnabled ? .texte : .texte.opacity(0.45))

                Spacer()

                if sport.isEnabled {
                    Text("Actif").font(.caption.bold()).foregroundColor(.cyan)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.15)).cornerRadius(8)
                }

                Button { onToggleExpand() } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "slider.horizontal.3")
                        .font(.caption.bold()).foregroundColor(.texte.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // Panneau de seuils dépliable
            if isExpanded {
                Divider().background(Color.surface.opacity(0.1)).padding(.horizontal, 16)

                VStack(spacing: 16) {
                    ThresholdSlider(label: "Vent max", unit: "km/h",
                                    value: $sport.maxWindKmh, range: 10...60, step: 5)
                    ThresholdSlider(label: "Rafales max", unit: "km/h",
                                    value: $sport.maxWindGustsKmh, range: 15...80, step: 5)
                    ThresholdSlider(label: "Température min", unit: "°C",
                                    value: $sport.minTempC, range: -10...20, step: 1)
                    ThresholdSlider(label: "Température max", unit: "°C",
                                    value: $sport.maxTempC, range: 20...45, step: 1)
                    ThresholdSlider(label: "UV max", unit: "",
                                    value: $sport.maxUVIndex, range: 3...11, step: 1)
                    ThresholdSliderInt(label: "Précipitations max", unit: "%",
                                       value: Binding(
                                           get: { Double(sport.maxPrecipProb) },
                                           set: { sport.maxPrecipProb = Int($0) }
                                       ), range: 10...80, step: 5)
                }
                .padding(16)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                ))
            }
        }
        .fondCarte()
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(sport.isEnabled ? Color.cyan.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: isExpanded)
    }
}

// MARK: - Slider seuil Double

struct ThresholdSlider: View {
    let label: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).font(.caption).foregroundColor(.texte.opacity(0.6))
                Spacer()
                Text("\(formattedValue)\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.caption.bold()).foregroundColor(.texte)
            }
            Slider(value: $value, in: range, step: step)
                .tint(.cyan)
        }
    }

    private var formattedValue: String {
        step >= 1 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - Slider seuil via Double binding pour Int

struct ThresholdSliderInt: View {
    let label: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).font(.caption).foregroundColor(.texte.opacity(0.6))
                Spacer()
                Text("\(Int(value))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.caption.bold()).foregroundColor(.texte)
            }
            Slider(value: $value, in: range, step: step).tint(.cyan)
        }
    }
}

// MARK: - Éditeur modal (futur usage)

struct SportThresholdEditor: View {
    @State var sport: FavoriteSport
    let onSave: (FavoriteSport) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Modifier \(sport.name)").font(.title2.bold()).foregroundColor(.texte).padding()
            Button("Fermer") { dismiss() }.foregroundColor(.cyan)
        }
        .background(Color(red:0.1,green:0.2,blue:0.4))
    }
}
