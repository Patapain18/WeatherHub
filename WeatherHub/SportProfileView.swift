import SwiftUI

// MARK: - Onglet Profil Sportif

struct SportProfileView: View {
    @ObservedObject var vm: WeatherViewModel
    @StateObject private var store = SportProfileStore.shared
    @State private var expandedSport: String? = nil
    @State private var editingSport: FavoriteSport? = nil

    var body: some View {
        ScrollView {
            SondeDefilement()
            VStack(spacing: 0) {

                // MARK: Header
                VStack(spacing: 6) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 44))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.texte, .cyan)
                    Text("Mon profil sportif")
                        .font(.largeTitle.bold()).foregroundColor(.texte)
                    Text("Seuils personnalisés selon vos sports")
                        .font(.subheadline).foregroundColor(.texte.opacity(0.55))
                }
                .padding(.top, 55)
                .padding(.bottom, 28)

                // MARK: Conditions du jour (sports activés)
                if !store.enabled.isEmpty {
                    todaySection
                        .padding(.horizontal, 40)
                        .padding(.bottom, 24)
                }

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
                    .padding(.horizontal, 40)

                    ForEach($store.sports) { $sport in
                        SportRowCard(sport: $sport,
                                     isExpanded: expandedSport == sport.id,
                                     onToggleExpand: {
                                         withAnimation(.spring(duration: 0.45, bounce: 0.22)) {
                                             expandedSport = expandedSport == sport.id ? nil : sport.id
                                         }
                                     },
                                     onToggleEnabled: { store.toggle(sport) })
                        .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $editingSport) { sport in
            SportThresholdEditor(sport: sport) { updated in
                store.update(updated)
            }
        }
    }

    // MARK: - Section "Aujourd'hui"

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conditions aujourd'hui")
                .font(.headline).foregroundColor(.texte)

            ForEach(store.enabled) { sport in
                let eval = SportEvaluator.evaluate(sport: sport, state: vm.state)
                TodayEvalRow(evaluation: eval)
            }
        }
        .padding(20)
        .fondCarte()
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Ligne évaluation du jour

struct TodayEvalRow: View {
    let evaluation: SportEvaluation
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.spring(duration: 0.4, bounce: 0.25)) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: evaluation.sport.icon)
                        .font(.title3).foregroundColor(.texte).frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(evaluation.sport.name)
                            .font(.subheadline.bold()).foregroundColor(.texte)
                        if !evaluation.reasons.isEmpty {
                            Text(evaluation.reasons.first ?? "")
                                .font(.caption).foregroundColor(.texte.opacity(0.55))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: evaluation.level.icon)
                            .font(.system(size: 14))
                        Text(evaluation.level.label)
                            .font(.caption.bold())
                    }
                    .foregroundColor(evaluation.level.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(evaluation.level.color.opacity(0.18))
                    .cornerRadius(10)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundColor(.texte.opacity(0.35))
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(evaluation.reasons, id: \.self) { reason in
                        Text(reason).font(.caption).foregroundColor(.texte.opacity(0.65))
                    }
                    if !evaluation.tips.isEmpty {
                        Divider().background(Color.surface.opacity(0.1))
                        ForEach(evaluation.tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 6) {
                                Text("→").font(.caption).foregroundColor(.cyan)
                                Text(tip).font(.caption).foregroundColor(.texte.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(.leading, 40).padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                ))
            }

            if evaluation.sport.id != SportProfileStore.shared.enabled.last?.id {
                Divider().background(Color.surface.opacity(0.1))
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
