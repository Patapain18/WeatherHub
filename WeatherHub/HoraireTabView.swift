import SwiftUI
import Charts

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  HoraireTabView — les 48 prochaines heures, une par une              ║
// ╚══════════════════════════════════════════════════════════════════════╝

struct HoraireTabView: View {
    @ObservedObject var vm: WeatherViewModel

    /// Température vue par les quatre modèles, pour la bande d'incertitude
    /// du graphique. Chargée à l'ouverture de l'onglet, pas au démarrage.
    @State private var serieTemperature: SerieHoraire?

    private static let heure: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH'h'"; return f
    }()
    private static let jour: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"
        f.locale = Locale(identifier: "fr_FR"); return f
    }()

    var body: some View {
        ScrollView {
            SondeDefilement()
            VStack(spacing: 20) {
                entete
                if vm.previsionsHoraires.isEmpty {
                    chargement
                } else {
                    graphique
                    liste
                }
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 36).padding(.top, 28).padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .task(id: vm.city) {
            serieTemperature = await WeatherService.shared
                .serieHoraire(city: vm.city, variable: "temperature_2m", heures: 48)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        VStack(spacing: 6) {
            Text("Prochaines heures")
                .font(.largeTitle.bold()).foregroundColor(.texte)
            Text("\(vm.city.capitalized) · prévision heure par heure sur 48 h")
                .font(.caption).foregroundColor(.texte.opacity(0.55))
        }
    }

    private var chargement: some View {
        VStack(spacing: 10) {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .texte))
            Text("Chargement de la prévision horaire…")
                .font(.caption).foregroundColor(.texte.opacity(0.5))
        }
        .padding(.top, 60)
    }

    // MARK: - Graphique

    /// Courbe de température sur 48 h. La bande, quand on l'a, montre
    /// l'écart entre les quatre modèles — même principe que dans les
    /// panneaux de détail, mais ici en tête d'onglet.
    private var graphique: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Température").font(.headline).foregroundColor(.texte)
                Spacer()
                if let s = serieTemperature, s.aUneBande {
                    Text("zone colorée : écart entre \(s.nbModeles) modèles")
                        .font(.caption2).foregroundColor(.texte.opacity(0.45))
                }
            }

            Chart {
                if let s = serieTemperature {
                    ForEach(s.points) { p in
                        if let bas = p.bas, let haut = p.haut {
                            AreaMark(x: .value("Heure", p.date),
                                     yStart: .value("min", bas), yEnd: .value("max", haut))
                                .foregroundStyle(Color.orange.opacity(0.16))
                        }
                    }
                }
                ForEach(vm.previsionsHoraires) { h in
                    LineMark(x: .value("Heure", h.date), y: .value("°C", h.temperature))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                }
                // Repère « maintenant »
                RuleMark(x: .value("Maintenant", Date()))
                    .foregroundStyle(Color.texte.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine().foregroundStyle(Color.surface.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour())
                        .font(.caption2).foregroundStyle(Color.texte.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color.surface.opacity(0.08))
                    AxisValueLabel().font(.caption2).foregroundStyle(Color.texte.opacity(0.5))
                }
            }
            .frame(height: 170)
        }
        .padding(18)
        .fondCarte().cornerRadius(22)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
    }

    // MARK: - Liste heure par heure

    private var liste: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.previsionsHoraires.enumerated()), id: \.element.id) { i, h in
                // Un séparateur quand on change de jour : sans lui, « 00 h »
                // au milieu d'une liste ne dit pas qu'on est passé à demain.
                if i == 0 || !Calendar.current.isDate(h.date, inSameDayAs: vm.previsionsHoraires[i - 1].date) {
                    separateurJour(h.date, premier: i == 0)
                }
                ligne(h, estMaintenant: i == 0)
                if i < vm.previsionsHoraires.count - 1 {
                    Divider().background(Color.surface.opacity(0.08)).padding(.leading, 70)
                }
            }
        }
        .padding(.vertical, 6)
        .fondCarte().cornerRadius(22)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
    }

    private func separateurJour(_ date: Date, premier: Bool) -> some View {
        HStack {
            Text(premier ? "Aujourd'hui" : Self.jour.string(from: date).capitalized)
                .font(.caption.bold()).foregroundColor(.texte.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, premier ? 10 : 18).padding(.bottom, 6)
    }

    private func ligne(_ h: PrevisionHeure, estMaintenant: Bool) -> some View {
        let nuit = estNuit(h.date)
        return HStack(spacing: 14) {
            Text(estMaintenant ? "Maint." : Self.heure.string(from: h.date))
                .font(.subheadline.bold())
                .foregroundColor(estMaintenant ? .cyan : .texte.opacity(0.75))
                .frame(width: 52, alignment: .leading)

            Image(systemName: iconePourCodeWMO(h.codeMeteo, nuit: nuit))
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(couleurIcone(h.codeMeteo, nuit: nuit), .gray)
                .frame(width: 30)

            Text(String(format: "%.0f°", h.temperature))
                .font(.title3.bold()).foregroundColor(.texte)
                .frame(width: 44, alignment: .trailing)

            Text(String(format: "ressenti %.0f°", h.ressenti))
                .font(.caption).foregroundColor(.texte.opacity(0.45))
                .frame(width: 92, alignment: .leading)

            Spacer()

            // La pluie n'est affichée que si elle a une chance d'arriver :
            // une colonne de « 0 % » n'apporte rien et noie l'information.
            if h.probaPluie >= 10 {
                Label("\(h.probaPluie) %", systemImage: "drop.fill")
                    .font(.caption).foregroundColor(.blue)
                    .frame(width: 58, alignment: .leading)
            } else {
                Spacer().frame(width: 58)
            }

            Label("\(Int(h.vent)) km/h", systemImage: "wind")
                .font(.caption).foregroundColor(.cyan.opacity(0.85))
                .frame(width: 78, alignment: .leading)

            if h.uv >= 3 {
                Text("UV \(Int(h.uv))")
                    .font(.caption2.bold()).foregroundColor(.texte)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(couleurUV(h.uv).opacity(0.3)).cornerRadius(6)
                    .frame(width: 46)
            } else {
                Spacer().frame(width: 46)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(estMaintenant ? Color.cyan.opacity(0.08) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resumeVocal(h, estMaintenant: estMaintenant))
    }

    // MARK: - Helpers

    private func estNuit(_ date: Date) -> Bool {
        guard let lever = vm.state.sunrise, let coucher = vm.state.sunset else { return false }
        // On compare l'heure du jour seulement : lever/coucher sont ceux
        // d'aujourd'hui, mais valent pour demain à quelques minutes près.
        let cal = Calendar.current
        let h = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let l = cal.component(.hour, from: lever) * 60 + cal.component(.minute, from: lever)
        let c = cal.component(.hour, from: coucher) * 60 + cal.component(.minute, from: coucher)
        return h < l || h > c
    }

    private func couleurIcone(_ code: Int, nuit: Bool) -> Color {
        switch code {
        case 0:        return nuit ? Color(red: 0.85, green: 0.88, blue: 1.0) : .yellow
        case 1, 2:     return nuit ? Color(red: 0.85, green: 0.88, blue: 1.0) : .yellow
        case 45, 48:   return .gray
        case 51...67, 80...82: return .blue
        case 71...77, 85, 86:  return .cyan
        case 95...99:  return .purple
        default:       return .texte
        }
    }

    private func couleurUV(_ uv: Double) -> Color {
        switch uv {
        case ..<3: return .green
        case ..<6: return .yellow
        case ..<8: return .orange
        default:   return .red
        }
    }

    private func resumeVocal(_ h: PrevisionHeure, estMaintenant: Bool) -> String {
        var s = estMaintenant ? "Maintenant" : Self.heure.string(from: h.date)
        s += ", \(Int(h.temperature)) degrés, ressenti \(Int(h.ressenti))"
        if h.probaPluie >= 10 { s += ", \(h.probaPluie) pour cent de pluie" }
        s += ", vent \(Int(h.vent)) kilomètres heure"
        if h.uv >= 3 { s += ", UV \(Int(h.uv))" }
        return s
    }
}
