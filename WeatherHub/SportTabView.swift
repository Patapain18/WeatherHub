import SwiftUI

struct SportTabView: View {
    @ObservedObject var vm: WeatherViewModel
    /// La feuille du profil sportif (l'ancien onglet Profil).
    @State private var profilOuvert = false

    var body: some View {
        ScrollView {
            SondeDefilement()
            VStack(spacing: 28) {
                // MARK: Header — et la bulle « réglages » à droite
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 6) {
                        Text("Sport")
                            .font(.largeTitle.bold())
                            .foregroundColor(.texte)

                        HStack(spacing: 16) {
                            contextPill(icon: "thermometer.medium", label: "\(Int(vm.state.temperature))°C")
                            contextPill(icon: "wind",               label: "\(Int(vm.state.windSpeed)) km/h")
                            contextPill(icon: "cloud",              label: vm.state.condition.isEmpty ? "—" : vm.conditionLibelle)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button { profilOuvert = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.texte.opacity(0.7))
                            .padding(10).fondCarte().clipShape(Circle())
                            .accessibilityLabel("Mon profil sportif")
                    }
                    .buttonStyle(.plain)
                    .help("Mes sports et leurs seuils")
                    .padding(.trailing, 40)
                }

                // MARK: Quand sortir
                if let meilleur = vm.creneaux.first { carteCreneau(meilleur) }

                // MARK: Sport list
                if vm.sports.isEmpty {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .texte))
                        .scaleEffect(1.4)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 14) {
                        ForEach(vm.sports) { evaluation in
                            sportRow(evaluation)
                        }
                    }
                    .padding(.horizontal, 40)
                }

                // MARK: Carte des équipements proches
                SportsMapCard(vm: vm)
                    .padding(.horizontal, 40)

            }
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $profilOuvert) { SportProfileView(vm: vm) }
    }

    // MARK: - Quand sortir ?

    private static let heureCourte: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH'h'"; return f
    }()

    private func carteCreneau(_ c: MeilleurCreneau) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundColor(.green).font(.title3)
                Text("Quand sortir ?").font(.headline).foregroundColor(.texte)
                Spacer()
                Text(c.sport.name).font(.subheadline.bold())
                    .foregroundColor(.texte.opacity(0.6))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Self.heureCourte.string(from: c.debut)) – \(Self.heureCourte.string(from: c.fin))")
                    .font(.system(size: 30, weight: .bold)).foregroundColor(.texte)
                Text("\(c.score)/100").font(.subheadline.bold())
                    .foregroundColor(.texte.opacity(0.55))
            }

            if let eviter = c.aEviter {
                Text("À éviter : \(Self.heureCourte.string(from: eviter.debut)) – \(Self.heureCourte.string(from: eviter.fin)) (\(eviter.frein.lowercased()))")
                    .font(.caption).foregroundColor(.orange.opacity(0.9))
            }

            // Frise des prochaines heures : une barre par heure, teintée
            // selon le score. On lit d'un coup d'œil la forme de la journée.
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(c.heures.prefix(24)) { h in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(couleurScore(h.score))
                            .frame(height: max(4, CGFloat(h.score) * 0.42))
                        if Calendar.current.component(.hour, from: h.date) % 6 == 0 {
                            Text(Self.heureCourte.string(from: h.date))
                                .font(.system(size: 8)).foregroundColor(.texte.opacity(0.4))
                        } else {
                            Text(" ").font(.system(size: 8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fondCarte().cornerRadius(22)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meilleur créneau pour \(c.sport.name) : de \(Self.heureCourte.string(from: c.debut)) à \(Self.heureCourte.string(from: c.fin)), score \(c.score) sur 100")
    }

    private func couleurScore(_ s: Int) -> Color {
        switch s {
        case 80...:   return .green
        case 60..<80: return Color(red: 0.55, green: 0.78, blue: 0.35)
        case 35..<60: return .orange
        default:      return .red
        }
    }

    // MARK: - Context pills

    private func contextPill(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.texte.opacity(0.7))
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.texte)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.surface.opacity(0.15))
        .cornerRadius(20)
    }

    // MARK: - Sport row

    private func sportRow(_ eval: SportEvaluation) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: eval.sport.icon)
                    .font(.title2)
                    .foregroundColor(.texte)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(eval.sport.name)
                        .foregroundColor(.texte)
                        .font(.headline)
                    Text(eval.resume)
                        .foregroundColor(.texte.opacity(0.6))
                        .font(.caption)
                }
            }

            Spacer()

            // Le score, avec sa marge d'incertitude quand on la connaît.
            VStack(alignment: .trailing, spacing: 1) {
                Text(eval.scoreTexte)
                    .font(.title3.bold())
                    .foregroundColor(.texte)
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.caption2)
                    .foregroundColor(.texte.opacity(0.4))
            }

            HStack(spacing: 4) {
                Image(systemName: eval.level.icon)
                Text(eval.level.label)
                    .font(.subheadline.bold())
            }
            .foregroundColor(.texte)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(eval.level.color.opacity(0.3))
            .cornerRadius(14)
            .frame(width: 130, alignment: .trailing)
        }
        .padding(18)
        .fondCarte()
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .animation(.spring(duration: 0.4), value: eval.score)
    }

}
