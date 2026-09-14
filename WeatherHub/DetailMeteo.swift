import SwiftUI
import Charts

// ═══════════════════════════════════════════════════════════════════
// MARK: - Grandeurs explorables au clic
// ═══════════════════════════════════════════════════════════════════

enum DetailMeteo: String, Identifiable, CaseIterable {
    case temperature, ressenti, vent, rafales, humidite
    case uv, airQuality, pluieProb, precipitation, nuages, visibilite

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .temperature:   return "Température"
        case .ressenti:      return "Ressenti"
        case .vent:          return "Vent"
        case .rafales:       return "Rafales"
        case .humidite:      return "Humidité"
        case .uv:            return "Indice UV"
        case .airQuality:    return "Qualité de l'air"
        case .pluieProb:     return "Risque de pluie"
        case .precipitation: return "Précipitations"
        case .nuages:        return "Couverture nuageuse"
        case .visibilite:    return "Visibilité"
        }
    }

    var icone: String {
        switch self {
        case .temperature:   return "thermometer.medium"
        case .ressenti:      return "thermometer.sun.fill"
        case .vent:          return "wind"
        case .rafales:       return "wind.circle.fill"
        case .humidite:      return "humidity.fill"
        case .uv:            return "sun.max.fill"
        case .airQuality:    return "aqi.medium"
        case .pluieProb:     return "drop.fill"
        case .precipitation: return "cloud.rain.fill"
        case .nuages:        return "cloud.fill"
        case .visibilite:    return "eye.fill"
        }
    }

    var couleur: Color {
        switch self {
        case .temperature, .ressenti: return .orange
        case .vent, .rafales:         return .cyan
        case .humidite:               return .teal
        case .uv:                     return .yellow
        case .airQuality:             return .green
        case .pluieProb, .precipitation: return .blue
        case .nuages:                 return .gray
        case .visibilite:             return .indigo
        }
    }

    var unite: String {
        switch self {
        case .temperature, .ressenti: return "°C"
        case .vent, .rafales:         return "km/h"
        case .humidite, .pluieProb, .nuages: return "%"
        case .uv:                     return ""
        case .airQuality:             return ""
        case .precipitation:          return "mm"
        case .visibilite:             return "km"
        }
    }

    /// Nom de la variable chez Open-Meteo.
    /// `nil` pour la qualité de l'air : elle a sa propre API.
    var variable: String? {
        switch self {
        case .temperature:   return "temperature_2m"
        case .ressenti:      return "apparent_temperature"
        case .vent:          return "wind_speed_10m"
        case .rafales:       return "wind_gusts_10m"
        case .humidite:      return "relative_humidity_2m"
        case .uv:            return "uv_index"
        case .pluieProb:     return "precipitation_probability"
        case .precipitation: return "precipitation"
        case .nuages:        return "cloud_cover"
        case .visibilite:    return "visibility"
        case .airQuality:    return nil
        }
    }

    var decimales: Int {
        switch self {
        case .temperature, .ressenti, .uv, .precipitation: return 1
        default: return 0
        }
    }

    /// Barème qualitatif, quand le chiffre seul ne parle pas.
    var bareme: [(borne: Double, label: String, couleur: Color)]? {
        switch self {
        case .uv:
            return [(2, "Faible", .green), (5, "Modéré", .yellow), (7, "Élevé", .orange),
                    (10, "Très élevé", .red), (99, "Extrême", .purple)]
        case .airQuality:
            return [(1, "Bon", .green), (2, "Acceptable", .mint), (3, "Modéré", .yellow),
                    (4, "Mauvais", .orange), (5, "Très mauvais", .red)]
        case .vent, .rafales:
            // Beaufort, ramené à cinq mots.
            return [(5, "Calme", .green), (19, "Léger", .cyan), (39, "Modéré", .yellow),
                    (59, "Fort", .orange), (999, "Tempête", .red)]
        default: return nil
        }
    }

    /// Une ligne pour comprendre la donnée, sans jargon.
    var explication: String {
        switch self {
        case .temperature:   return "La température affichée est la médiane des centres de prévision, pas leur moyenne : un modèle qui s'emballe ne la tire pas. Mesurée à 2 m du sol, à l'ombre."
        case .ressenti:      return "Le ressenti combine température, vent et humidité : le vent refroidit, l'humidité empêche la sueur de s'évaporer."
        case .vent:          return "Vent moyen à 10 m au-dessus du sol. Le barème suit l'échelle de Beaufort ; les rafales font en général 1,5 à 2 fois le vent moyen."
        case .rafales:       return "Une rafale est une pointe de quelques secondes. C'est elle qui couche les vélos et casse les branches, pas le vent moyen."
        case .humidite:      return "Humidité relative : 100 % = air saturé. Au-delà de 60 % avec de la chaleur, la sueur s'évapore mal et l'air paraît lourd."
        case .uv:            return "L'indice UV mesure l'intensité du rayonnement ultraviolet, de 0 à 11+. À 3, une peau claire rougit en moins d'une heure ; les nuages n'arrêtent qu'une partie des UV."
        case .airQuality:    return "Indice européen de 1 (bon) à 5 (très mauvais) : le pire des polluants mesurés (particules, dioxyde d'azote, ozone). Trois modèles jugés à la même règle, plus les capteurs citoyens du quartier, qui ne voient que les particules."
        case .pluieProb:     return "Probabilité qu'il tombe au moins 0,1 mm dans l'heure. 40 % ne veut pas dire « pluie faible » : il pleut franchement 4 fois sur 10."
        case .precipitation: return "Cumul attendu par heure, en millimètres : 1 mm = 1 litre par m². Au-delà de 5 mm/h, c'est une averse marquée."
        case .nuages:        return "Part du ciel couverte par les nuages. Sous 25 % le soleil domine, au-dessus de 75 % le ciel est gris."
        case .visibilite:    return "Distance à laquelle on distingue un objet. Sous 1 km on parle de brouillard ; au-delà de 10 km l'air est limpide."
        }
    }

    func niveau(pour valeur: Double) -> (label: String, couleur: Color)? {
        guard let bareme else { return nil }
        for palier in bareme where valeur <= palier.borne {
            return (palier.label, palier.couleur)
        }
        return bareme.last.map { ($0.label, $0.couleur) }
    }
}


// ═══════════════════════════════════════════════════════════════════
// MARK: - Panneau de détail
// ═══════════════════════════════════════════════════════════════════

/// Ce qui s'ouvre au clic sur une tuile. Même langage que la grille :
/// titre en capitales, grande valeur, barème visible, une phrase qui dit
/// quoi faire, le graphe 48 h en aire colorée, trois repères du jour,
/// une ligne pour comprendre la donnée.
struct DetailMeteoSheet: View {

    let detail: DetailMeteo
    @ObservedObject var vm: WeatherViewModel
    @Environment(\.dismiss) private var fermer

    @State private var serie: SerieHoraire?
    @State private var air: QualiteAirEnsemble?
    @State private var chargement = true

    private static let formatEnTete: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE d MMM, HH:mm"; return f
    }()

    /// 640 × 640 quand l'écran le permet ; sinon la feuille se réduit et
    /// son contenu défile — plus haute que la fenêtre, elle serait coupée.
    private var hauteur: CGFloat {
        min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 120)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                entete
                maintenant
                tuileGraphe
                reperesDuJour
                Text(detail.explication)
                    .font(.system(size: 12)).foregroundColor(.texte.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
                pied
            }
            .padding(22)
        }
        .frame(width: 640, height: hauteur)
        .fondCarte()
        .task { await charger() }
    }

    // MARK: En-tête

    private var entete: some View {
        HStack(spacing: 8) {
            Image(systemName: detail.icone)
                .font(.system(size: 13, weight: .semibold)).foregroundColor(detail.couleur)
            Text(detail.titre.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(1)
                .foregroundColor(.texte.opacity(0.66))
            Spacer()
            Text("\(vm.city.capitalized) · \(Self.formatEnTete.string(from: Date()))")
                .font(.system(size: 12)).foregroundColor(.texte.opacity(0.48))
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
    }

    // MARK: Maintenant : valeur, niveau, barème, phrase d'action

    private var maintenant: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fmt(valeurActuelle))
                        .font(.system(size: 56, weight: .bold, design: .rounded)).tracking(-2)
                        .foregroundColor(.texte)
                    if !detail.unite.isEmpty {
                        Text(detail.unite).font(.system(size: 20, weight: .medium)).foregroundColor(.texte.opacity(0.66))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    pastille
                    Text(contexte).font(.system(size: 12)).foregroundColor(.texte.opacity(0.48)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            if let bareme = detail.bareme {
                BaremeSegments(bareme: bareme, valeur: valeurActuelle,
                               decalage: detail == .airQuality ? 0.5 : 0,
                               actif: detail.niveau(pour: valeurActuelle)?.label)
            }
            let (tete, suite) = phraseAction
            (Text(tete).fontWeight(.semibold).foregroundColor(.texte) + Text(suite).foregroundColor(.texte.opacity(0.66)))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Pastille de niveau (barème) — ou l'écart avec hier pour la température.
    @ViewBuilder private var pastille: some View {
        if let n = detail.niveau(pour: valeurActuelle) {
            pastilleTexte(n.label, couleur: n.couleur)
        } else if detail == .temperature || detail == .ressenti, let c = vm.comparaisonHier {
            pastilleTexte(c.replacingOccurrences(of: " par rapport à hier", with: " vs hier"), couleur: .cyan)
        }
    }

    private func pastilleTexte(_ texte: String, couleur: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(couleur).frame(width: 7, height: 7)
            Text(texte).font(.system(size: 13, weight: .semibold)).foregroundColor(couleur)
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(couleur.opacity(0.2)).clipShape(Capsule())
    }

    // MARK: Le graphe 48 h

    private var tuileGraphe: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(detail.couleur)
                Text("PRÉVISION 48 H")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.9)
                    .foregroundColor(.texte.opacity(0.48))
                Spacer()
                accordDesModeles
            }
            Group {
                if chargement {
                    VStack(spacing: 10) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .texte))
                        Text("Chargement des 48 prochaines heures…")
                            .font(.caption).foregroundColor(.texte.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                } else if let serie, !serie.points.isEmpty {
                    graphe(serie)
                } else {
                    Text("Aucune série disponible pour cette donnée.")
                        .font(.subheadline).foregroundColor(.texte.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 170)
            HStack(spacing: 14) {
                legende(couleurLegende, texteLegende)
                legende(Color.black.opacity(0.25), "Nuit")
            }
        }
        .padding(12)
        .fondCarte().cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.surface.opacity(0.13), lineWidth: 1))
    }

    /// Juste le pourcentage : le détail par centre n'intéressait personne.
    @ViewBuilder private var accordDesModeles: some View {
        if detail == .airQuality, (air?.nbModeles ?? 0) < 2 {
            Text(air == nil ? "" : "Source unique").font(.system(size: 11, weight: .semibold)).foregroundColor(.texte.opacity(0.66))
        } else {
            HStack(spacing: 7) {
                Text(detail == .airQuality ? "Accord des \(air?.nbModeles ?? 0) modèles" : "Accord des modèles")
                    .font(.system(size: 11)).foregroundColor(.texte.opacity(0.48))
                Text("\(accord) %")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(couleurAccord)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface.opacity(0.14))
                    Capsule().fill(couleurAccord).frame(width: 54 * CGFloat(accord) / 100)
                }
                .frame(width: 54, height: 4)
            }
        }
    }

    /// Pour l'air, l'accord des modèles d'air ; sinon celui de la météo.
    private var accord: Int { detail == .airQuality ? (air?.accord ?? 0) : vm.state.reliability }

    private var couleurAccord: Color {
        accord >= 80 ? .green : accord >= 50 ? .yellow : .red
    }

    private func legende(_ couleur: Color, _ texte: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(couleur).frame(width: 10, height: 10)
            Text(texte).font(.system(size: 10.5)).foregroundColor(.texte.opacity(0.48))
        }
    }

    private var couleurLegende: Color {
        detail.bareme != nil ? .green : detail == .temperature || detail == .ressenti ? .orange : couleurGraphe
    }
    /// Le gris des nuages est invisible sur le fond gris de la feuille :
    /// pour le tracé on prend la couleur du texte (blanc en sombre, noir
    /// en clair), qui contraste dans les deux thèmes.
    private var couleurGraphe: Color {
        detail == .nuages ? Color.texte.opacity(0.75) : detail.couleur
    }

    private var texteLegende: String {
        detail.bareme != nil ? "Couleur = niveau, du plus faible au plus élevé"
        : detail == .temperature || detail == .ressenti ? "Couleur = valeur, du frais au chaud"
        : "Médiane des centres"
    }

    /// Swift Charts fournit les axes, les nuits, le pic et le marqueur
    /// « maintenant » ; l'aire colorée est dessinée dans le fond du
    /// graphe avec les positions du `ChartProxy` — voir `AireColoree`.
    private func graphe(_ serie: SerieHoraire) -> some View {
        let pts = serie.points
        let (ymin, ymax) = domaine(pts)
        let pic = picDuJour(pts)
        return Chart {
            ForEach(nuits(pts), id: \.debut) { n in
                RectangleMark(xStart: .value("Début", n.debut), xEnd: .value("Fin", n.fin),
                              yStart: .value("Bas", ymin), yEnd: .value("Haut", ymax))
                    .foregroundStyle(Color.black.opacity(0.18))
            }
            RuleMark(x: .value("Maintenant", Date()))
                .foregroundStyle(Color.cyan.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                // Au-dessus du tracé, dans la bande des jours : en bas ou en
                // haut du cadre, le mot finissait toujours sur la courbe.
                .annotation(position: .top, alignment: .leading, spacing: 2,
                            overflowResolution: .init(x: .fit(to: .plot), y: .disabled)) {
                    Text("maintenant").font(.system(size: 9)).foregroundColor(.cyan)
                }
            if let pic {
                PointMark(x: .value("Heure", pic.date), y: .value("Valeur", pic.mediane))
                    .foregroundStyle(couleurGraphe).symbolSize(40)
                    .annotation(position: .top, spacing: 3) {
                        Text(fmt(pic.mediane)).font(.system(size: 10, weight: .semibold)).foregroundColor(.texte)
                    }
            }
            // Invisible : elle ne sert qu'à fixer l'échelle des heures.
            ForEach(pts) { p in
                LineMark(x: .value("Heure", p.date), y: .value(detail.titre, p.mediane)).opacity(0)
            }
        }
        .chartYScale(domain: ymin...ymax)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Color.surface.opacity(0.10))
                AxisValueLabel(format: .dateTime.hour())
                    .font(.system(size: 9.5)).foregroundStyle(Color.texte.opacity(0.48))
            }
            // Les changements de jour, en haut pour ne pas chevaucher les heures.
            AxisMarks(position: .top, values: .stride(by: .day)) { _ in
                AxisGridLine().foregroundStyle(Color.surface.opacity(0.18))
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), anchor: .bottomLeading)
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color.texte.opacity(0.66))
            }
        }
        .chartYAxis {
            if let bareme = detail.bareme {
                // Les seuils du barème remplacent les chiffres : « Modéré », « Élevé »…
                AxisMarks(values: seuils(bareme, ymax: ymax).map(\.valeur)) { v in
                    let seuil = seuils(bareme, ymax: ymax).first { $0.valeur == v.as(Double.self) }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .foregroundStyle((seuil?.couleur ?? .gray).opacity(0.7))
                    AxisValueLabel {
                        Text(seuil?.label ?? "").font(.system(size: 9)).foregroundColor(seuil?.couleur ?? .gray)
                    }
                }
            } else if [.humidite, .nuages, .pluieProb].contains(detail) {
                AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                    AxisGridLine().foregroundStyle(Color.surface.opacity(0.10))
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.texte.opacity(0.48))
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.surface.opacity(0.10))
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.texte.opacity(0.48))
                }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                AireColoree(points: pts, ymin: ymin, proxy: proxy, geo: geo, bandes: bandesDegrade(ymin: ymin, ymax: ymax))
            }
        }
    }

    private struct Seuil { let valeur: Double; let label: String; let couleur: Color }

    /// Une graduation par changement de niveau, dans les bornes du graphe.
    private func seuils(_ bareme: [(borne: Double, label: String, couleur: Color)], ymax: Double) -> [Seuil] {
        var r: [Seuil] = []
        for (i, palier) in bareme.enumerated() where i > 0 {
            let borne = bareme[i - 1].borne
            if borne > 0.2, borne < ymax - 0.2 { r.append(Seuil(valeur: borne, label: palier.label, couleur: palier.couleur)) }
        }
        return r
    }

    /// Les bandes de couleur du dégradé, par valeur : une par niveau du
    /// barème (couleur unie), sinon du cyan au orange pour la température,
    /// sinon la couleur de la donnée qui s'estompe vers le bas.
    private func bandesDegrade(ymin: Double, ymax: Double) -> [AireColoree.Bande] {
        if let bareme = detail.bareme {
            var r: [AireColoree.Bande] = []
            var bas = ymin
            for palier in bareme {
                let haut = min(ymax, palier.borne)
                if haut > bas { r.append(.init(bas: bas, haut: haut, couleurBas: palier.couleur, couleurHaut: palier.couleur)); bas = haut }
                if bas >= ymax { break }
            }
            if bas < ymax, let dernier = bareme.last {
                r.append(.init(bas: bas, haut: ymax, couleurBas: dernier.couleur, couleurHaut: dernier.couleur))
            }
            return r
        }
        if detail == .temperature || detail == .ressenti {
            return [.init(bas: min(ymin, 10), haut: max(ymax, 30), couleurBas: .cyan, couleurHaut: .orange)]
        }
        return [.init(bas: ymin, haut: ymax, couleurBas: couleurGraphe.opacity(0.25), couleurHaut: couleurGraphe)]
    }

    // MARK: Repères du jour

    private var reperesDuJour: some View {
        HStack(spacing: 10) {
            ForEach(reperes, id: \.titre) { r in
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.titre.uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(0.9)
                        .foregroundColor(.texte.opacity(0.48)).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(r.valeur).font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(-0.4).foregroundColor(.texte)
                        if !r.unite.isEmpty { Text(r.unite).font(.system(size: 12, weight: .medium)).foregroundColor(.texte.opacity(0.66)) }
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                    Text(r.note).font(.system(size: 11)).foregroundColor(.texte.opacity(0.48)).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fondCarte().cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.surface.opacity(0.13), lineWidth: 1))
            }
        }
    }

    private struct Repere { let titre: String; let valeur: String; let unite: String; let note: String }

    private var reperes: [Repere] {
        guard let pts = serie?.points, !pts.isEmpty else {
            return [Repere(titre: "Pic aujourd'hui", valeur: "–", unite: "", note: "en attente"),
                    Repere(titre: "Le plus bas", valeur: "–", unite: "", note: "en attente"),
                    Repere(titre: "Demain", valeur: "–", unite: "", note: "en attente")]
        }
        let cal = Calendar.current
        let auj = pts.filter { cal.isDateInToday($0.date) }
        let demain = pts.filter { cal.isDateInTomorrow($0.date) }
        let picAuj = auj.max { $0.mediane < $1.mediane } ?? pts[0]
        let picDemain = demain.max { $0.mediane < $1.mediane }
        let creux = pts.prefix(24).min { $0.mediane < $1.mediane } ?? pts[0]
        let heure = { (d: Date) in "\(cal.component(.hour, from: d)) h" }
        let niveau = { (v: Double) in detail.niveau(pour: v).map { " · \($0.label)" } ?? "" }

        let premier = Repere(titre: "Pic aujourd'hui", valeur: fmt(picAuj.mediane), unite: detail.unite,
                             note: "à \(heure(picAuj.date))\(niveau(picAuj.mediane))")
        let second: Repere
        switch detail {
        case .uv:
            // La plage à protéger : les heures d'aujourd'hui où l'indice dépasse 3.
            let expo = auj.filter { $0.mediane >= 3 }
            if let d = expo.first, let f = expo.last {
                second = Repere(titre: "À protéger", valeur: "\(heure(d.date)) → \(heure(f.date))", unite: "",
                                note: "\(expo.count) h au-dessus de 3")
            } else {
                second = Repere(titre: "À protéger", valeur: "Rien", unite: "", note: "l'indice reste sous 3")
            }
        case .temperature, .ressenti:
            second = Repere(titre: "Min cette nuit", valeur: fmt(creux.mediane), unite: detail.unite, note: "à \(heure(creux.date))")
        case .airQuality where air?.mesures.first != nil:
            // Une mesure réelle du quartier : particules seulement, mais mesurées, pas prévues.
            let m = air!.mesures[0]
            let pm25 = m.concentrations.first { $0.polluant == "PM2.5" }?.valeur ?? 0
            second = Repere(titre: "Mesuré à côté", valeur: String(format: pm25 < 10 ? "%.1f" : "%.0f", pm25), unite: "µg/m³",
                            note: "PM2.5 · \(m.nbCapteurs) capteur\(m.nbCapteurs > 1 ? "s" : "") citoyen\(m.nbCapteurs > 1 ? "s" : "")")
        default:
            second = Repere(titre: "Le plus bas", valeur: fmt(creux.mediane), unite: detail.unite,
                            note: "à \(heure(creux.date))\(niveau(creux.mediane))")
        }
        let troisieme = picDemain.map {
            Repere(titre: "Demain", valeur: fmt($0.mediane), unite: detail.unite, note: "max à \(heure($0.date))\(niveau($0.mediane))")
        } ?? Repere(titre: "Demain", valeur: "–", unite: "", note: "hors de la série")
        return [premier, second, troisieme]
    }

    // MARK: Pied

    private var pied: some View {
        HStack {
            Text(detail == .airQuality
                 ? "\(sourcesAir) · \(vm.lastUpdatedString.lowercased())"
                 : "Open-Meteo · \(centres) · \(vm.lastUpdatedString.lowercased())")
                .font(.system(size: 11)).foregroundColor(.texte.opacity(0.48)).lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                Text("Fermer").font(.system(size: 11)).foregroundColor(.texte.opacity(0.48))
                Text("Échap").font(.system(size: 10)).foregroundColor(.texte.opacity(0.66))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.surface.opacity(0.06)).cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.surface.opacity(0.13), lineWidth: 1))
            }
        }
    }

    private var sourcesAir: String {
        guard let air, !air.modeles.isEmpty else { return "Qualité de l'air indisponible" }
        var s = air.modeles.map(\.nom).joined(separator: ", ")
        if let m = air.mesures.first { s += " · \(m.nbCapteurs) capteur\(m.nbCapteurs > 1 ? "s" : "") Sensor.Community" }
        return s
    }

    private var centres: String {
        let noms = serie?.parModele.map(\.modele) ?? []
        return noms.count > 1 ? noms.joined(separator: ", ") : "ECMWF, GFS, ICON, Météo-France"
    }

    // MARK: Textes

    private func fmt(_ v: Double) -> String {
        // Pour l'air, on affiche le numéro du niveau (1 à 5), pas la valeur
        // continue de la série — « 1.3 » à côté de « Acceptable » serait absurde.
        if detail == .airQuality, let bareme = detail.bareme {
            return String((bareme.firstIndex { v <= $0.borne } ?? bareme.count - 1) + 1)
        }
        return typoMoins(String(format: "%.\(detail.decimales)f", v))
    }

    /// Sous la pastille : le pic du jour et celui de demain, en une ligne.
    private var contexte: String {
        guard let pts = serie?.points, !pts.isEmpty else { return "Prévision en cours de chargement…" }
        let cal = Calendar.current
        let pic = pts.filter { cal.isDateInToday($0.date) }.max { $0.mediane < $1.mediane } ?? pts[0]
        let demain = pts.filter { cal.isDateInTomorrow($0.date) }.max { $0.mediane < $1.mediane }
        var s = "Pic à \(fmt(pic.mediane))\(detail.unite.isEmpty ? "" : " " + detail.unite) vers \(cal.component(.hour, from: pic.date)) h aujourd'hui"
        if let demain { s += " · \(fmt(demain.mediane)) demain" }
        return s + "."
    }

    /// Ce que ça change pour la sortie — un début en gras, une suite.
    private var phraseAction: (String, String) {
        let v = valeurActuelle
        let pts = serie?.points ?? []
        let cal = Calendar.current
        let auj = pts.filter { cal.isDateInToday($0.date) }
        let pic = auj.max { $0.mediane < $1.mediane }
        let picV = pic?.mediane ?? v
        let picH = pic.map { cal.component(.hour, from: $0.date) } ?? cal.component(.hour, from: Date())
        let creux = pts.prefix(24).min { $0.mediane < $1.mediane }
        let demainMax = pts.filter { cal.isDateInTomorrow($0.date) }.map(\.mediane).max() ?? picV

        switch detail {
        case .uv:
            if picV >= 8 { return ("Protection indispensable", " — chapeau, lunettes et ombre entre 12 h et 16 h.") }
            if picV >= 6 { return ("Crème solaire et chapeau", " — la protection compte de 11 h à 16 h.") }
            if picV >= 3 { return ("Crème solaire pour une longue sortie", " — la protection compte de 12 h à 16 h, inutile avant 10 h ou après 18 h.") }
            return ("Aucune protection nécessaire", " — l'indice reste faible toute la journée.")
        case .airQuality:
            if v <= 2 { return ("Bonne journée pour aérer et sortir", demainMax <= 2 ? " — l'air reste sain sur les 48 h." : " — l'indice monte à \(fmt(demainMax)) demain.") }
            if v == 3 { return ("Personnes sensibles : limitez l'effort prolongé", " en extérieur, surtout l'après-midi.") }
            return ("Évitez l'effort en extérieur", " et aérez tôt le matin, quand l'air est le plus propre.")
        case .temperature, .ressenti:
            guard let creux else { return ("Température", " en cours de chargement.") }
            let ecart = picV - creux.mediane
            if ecart >= 8 { return ("Grand écart sur la journée", " — \(fmt(picV)) °C à \(picH) h, \(fmt(creux.mediane)) °C à \(cal.component(.hour, from: creux.date)) h : prévoir une couche pour le matin.") }
            return ("Peu d'écart sur la journée", " — entre \(fmt(creux.mediane)) et \(fmt(picV)) °C.")
        case .vent, .rafales:
            let suite = demainMax >= 20 && picV < 20 ? " Se renforce demain (\(fmt(demainMax)) km/h)." : ""
            if picV >= 40 { return ("Vent fort aujourd'hui", " — évitez les zones boisées et le vélo exposé.") }
            if picV >= 20 { return ("Vent modéré", " — bien pour sécher le linge, moins pour le vélo.") }
            return ("Calme", " — rien à signaler côté vent." + suite)
        case .humidite:
            if v >= 70 { return ("Air lourd", " — la sueur s'évapore mal, pensez à boire.") }
            if v <= 30 { return ("Air sec", " — lèvres et peau tirent, pensez à boire.") }
            return ("Confortable", " — ni sec ni moite.")
        case .pluieProb:
            if picV >= 60 { return ("Parapluie conseillé", " — \(fmt(picV)) % de risque vers \(picH) h.") }
            if picV >= 30 { return ("Risque d'averse", " — \(fmt(picV)) % vers \(picH) h, un coupe-vent suffit.") }
            return ("Pas de pluie en vue", " sur les 48 prochaines heures.")
        case .precipitation:
            if picV >= 5 { return ("Averse marquée", " — \(fmt(picV)) mm/h vers \(picH) h.") }
            if picV > 0.2 { return ("Pluie faible attendue", " — \(fmt(picV)) mm/h au plus, vers \(picH) h.") }
            return ("Sec", " — rien de mesurable sur 48 h.")
        case .nuages:
            if v >= 75 { return ("Ciel gris", " — peu de soleil à attendre aujourd'hui.") }
            if v >= 40 { return ("Éclaircies", " — le soleil perce par moments.") }
            return ("Ciel dégagé", " — le soleil domine.")
        case .visibilite:
            if v < 1 { return ("Brouillard", " — prudence sur la route, feux allumés.") }
            if v < 4 { return ("Visibilité réduite", " — brume ou pluie.") }
            return ("Bonne visibilité", " — aucune brume attendue.")
        }
    }

    // MARK: Calculs pour le graphe

    /// Bornes verticales : de 0 avec un barème (au moins deux niveaux
    /// visibles), sinon autour des valeurs ; les pourcentages restent
    /// dans 0–100.
    private func domaine(_ pts: [SerieHoraire.Point]) -> (Double, Double) {
        let maxV = pts.map(\.mediane).max() ?? 1, minV = pts.map(\.mediane).min() ?? 0
        if let bareme = detail.bareme {
            let deuxieme = bareme.count > 1 ? bareme[1].borne : maxV
            return (0, max((maxV * 1.15 + 0.5).rounded(.up), deuxieme + 1))
        }
        // Un pourcentage plafonne à 100 : sans marge, la courbe à 100 % se
        // confond avec le bord du cadre et son trait est coupé en deux.
        if [.humidite, .nuages, .pluieProb].contains(detail) { return (0, 106) }
        if detail == .precipitation || detail == .visibilite { return (0, max(1, (maxV * 1.2).rounded(.up))) }
        return ((minV - 1).rounded(.down), (maxV + 1).rounded(.up))
    }

    private func picDuJour(_ pts: [SerieHoraire.Point]) -> SerieHoraire.Point? {
        guard detail != .airQuality else { return nil }
        let auj = pts.filter { Calendar.current.isDateInToday($0.date) }
        return (auj.isEmpty ? Array(pts.prefix(12)) : auj).max { $0.mediane < $1.mediane }
    }

    /// Les nuits couvertes par la série, à partir du lever et du coucher
    /// d'aujourd'hui décalés de ±1 jour — assez juste sur 48 h.
    private func nuits(_ pts: [SerieHoraire.Point]) -> [(debut: Date, fin: Date)] {
        guard let lever = vm.state.sunrise, let coucher = vm.state.sunset,
              let premier = pts.first?.date, let dernier = pts.last?.date else { return [] }
        var r: [(Date, Date)] = []
        for k in -1...2 {
            let d = coucher.addingTimeInterval(Double(k) * 86_400)
            let f = lever.addingTimeInterval(Double(k + 1) * 86_400)
            let debut = max(d, premier), fin = min(f, dernier)
            if fin > debut { r.append((debut, fin)) }
        }
        return r
    }

    // MARK: Données

    private var valeurActuelle: Double {
        let s = vm.state
        switch detail {
        case .temperature:   return s.temperature
        case .ressenti:      return s.feelsLike
        case .vent:          return s.windSpeed
        case .rafales:       return s.windGusts
        case .humidite:      return Double(s.humidity)
        case .uv:            return s.uvIndex
        case .airQuality:    return Double(s.aqi)
        case .pluieProb:     return Double(s.precipitationProb)
        case .precipitation: return s.precipitationMm
        case .nuages:        return Double(s.cloudCover)
        case .visibilite:    return s.visibility
        }
    }

    private func charger() async {
        chargement = true
        if let variable = detail.variable {
            serie = await WeatherService.shared.serieHoraire(city: vm.city, variable: variable)
        } else {
            air = await WeatherService.shared.qualiteAir(city: vm.city)
            if let air {
                // L'indice européen va de 0 à 100+ par paliers de 20 ; l'app
                // affiche un indice de 1 à 5. On le ramène sur cette échelle
                // (en continu : 26 → 1,3, donc niveau 2, « Acceptable »).
                let sur5 = { (v: Double?) -> Double? in v.map { min(5.5, $0 / 20) } }
                var pts: [SerieHoraire.Point] = []
                for (i, d) in air.heures.enumerated() {
                    guard let m = sur5(air.mediane[i]) else { continue }
                    pts.append(.init(date: d, mediane: m, bas: sur5(air.bas[i]), haut: sur5(air.haut[i])))
                }
                serie = SerieHoraire(points: pts, parModele: air.modeles.compactMap { m in m.maintenant.map { (m.nom, $0 / 20) } })
            }
        }
        chargement = false
    }
}

// MARK: - Le barème en segments

/// Un segment par niveau, large comme la plage qu'il couvre, et un
/// curseur sur la valeur du moment. Le dernier niveau est ouvert
/// (« 11+ ») : on lui donne la largeur du précédent.
struct BaremeSegments: View {
    let bareme: [(borne: Double, label: String, couleur: Color)]
    let valeur: Double
    var decalage: Double = 0      // 0,5 pour un indice entier (air) : la valeur 2 tombe au milieu de son segment
    var actif: String? = nil

    private var largeurs: [Double] {
        var r: [Double] = []; var bas = 0.0
        for (i, p) in bareme.enumerated() {
            let ouvert = i == bareme.count - 1 && p.borne > 90
            let l = ouvert ? (r.last ?? 1) : max(0.5, p.borne - bas)
            r.append(l); bas = p.borne
        }
        return r
    }

    var body: some View {
        let total = largeurs.reduce(0, +)
        let position = min(1, max(0, (valeur - decalage) / total))
        VStack(spacing: 5) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        ForEach(Array(bareme.enumerated()), id: \.offset) { i, p in
                            Capsule().fill(p.couleur)
                                .opacity(p.label == actif ? 0.95 : 0.38)
                                .frame(width: max(4, (g.size.width - 3 * CGFloat(bareme.count - 1)) * largeurs[i] / total))
                        }
                    }
                    Circle().fill(.white)
                        .overlay(Circle().stroke(Color.texteInverse, lineWidth: 2))
                        .frame(width: 13, height: 13)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .offset(x: g.size.width * position - 6.5)
                }
            }
            .frame(height: 7)
            // Les mots sous les segments, chacun large comme son segment.
            GeometryReader { g in
                HStack(spacing: 3) {
                    ForEach(Array(bareme.enumerated()), id: \.offset) { i, p in
                        Text(p.label)
                            .font(.system(size: 10.5, weight: p.label == actif ? .semibold : .regular))
                            .foregroundColor(p.label == actif ? .texte : .texte.opacity(0.48))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: max(4, (g.size.width - 3 * CGFloat(bareme.count - 1)) * largeurs[i] / total), alignment: .leading)
                    }
                }
            }
            .frame(height: 13)
        }
    }
}

// MARK: - L'aire colorée (variante C de la maquette)

/// La courbe médiane lissée, remplie d'un dégradé vertical dont les
/// couleurs suivent le barème. Dessinée à la main dans le fond du graphe :
/// un `AreaMark` ne sait pas caler un dégradé sur des valeurs précises.
struct AireColoree: View {
    let points: [SerieHoraire.Point]
    let ymin: Double
    let proxy: ChartProxy
    let geo: GeometryProxy
    let bandes: [Bande]

    /// Une plage de valeurs et ses couleurs aux deux bouts (identiques
    /// pour un niveau de barème : la bande est unie).
    struct Bande { let bas: Double; let haut: Double; let couleurBas: Color; let couleurHaut: Color }

    var body: some View {
        guard let ancre = proxy.plotFrame else { return AnyView(EmptyView()) }
        let cadre = geo[ancre]
        // Position d'un point dans les coordonnées du GeometryReader
        let xy: (SerieHoraire.Point) -> CGPoint? = { p in
            guard let x = proxy.position(forX: p.date), let y = proxy.position(forY: p.mediane) else { return nil }
            return CGPoint(x: x + cadre.minX, y: y + cadre.minY)
        }
        let pts = points.compactMap(xy)
        guard pts.count > 1, let yBase = proxy.position(forY: ymin) else { return AnyView(EmptyView()) }
        let base = yBase + cadre.minY

        let courbe = Self.lissageMonotone(pts)
        var aire = courbe
        aire.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: base))
        aire.addLine(to: CGPoint(x: pts[0].x, y: base))
        aire.closeSubpath()

        // Les arrêts du dégradé, en fraction de la hauteur du GeometryReader
        // (le dégradé couvre tout le cadre, le masque découpe l'aire).
        // Construits de HAUT en BAS, bande par bande : deux arrêts à la même
        // position font une frontière nette, et un tri les aurait mélangés.
        let h = max(1, geo.size.height)
        let loc: (Double) -> CGFloat = { v in
            let y = proxy.position(forY: v) ?? 0
            return min(1, max(0, (y + cadre.minY) / h))
        }
        var stops: [Gradient.Stop] = []
        for b in bandes.sorted(by: { $0.haut > $1.haut }) {
            stops.append(.init(color: b.couleurHaut, location: loc(b.haut)))
            stops.append(.init(color: b.couleurBas, location: loc(b.bas)))
        }

        return AnyView(
            ZStack {
                LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom)
                    .opacity(0.62)
                    .mask(aire.fill(Color.black))
                courbe.stroke(Color.texte.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            // Le lissage peut déborder sous le plancher : on coupe au cadre du tracé.
            .mask(Rectangle().frame(width: cadre.width, height: cadre.height).position(x: cadre.midX, y: cadre.midY))
        )
    }

    /// Lissage monotone (Fritsch–Carlson) converti en courbes de Bézier :
    /// la courbe passe par chaque point et ne dépasse jamais les valeurs.
    /// Catmull-Rom, plus simple, « rebondit » au-dessus d'un plateau à 100 %
    /// et la bosse était coupée par le bord du cadre.
    static func lissageMonotone(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let premier = p.first else { return path }
        path.move(to: premier)
        guard p.count > 1 else { return path }
        let n = p.count
        // Pentes des cordes entre points voisins
        var delta = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = p[i + 1].x - p[i].x
            delta[i] = dx == 0 ? 0 : (p[i + 1].y - p[i].y) / dx
        }
        // Tangentes : moyenne des cordes, mises à zéro quand la pente change de signe
        var m = [CGFloat](repeating: 0, count: n)
        m[0] = delta[0]; m[n - 1] = delta[n - 2]
        for i in 1..<(n - 1) { m[i] = delta[i - 1] * delta[i] <= 0 ? 0 : (delta[i - 1] + delta[i]) / 2 }
        for i in 0..<(n - 1) where delta[i] != 0 {
            let a = m[i] / delta[i], b = m[i + 1] / delta[i]
            let h = a * a + b * b
            if h > 9 { let t = 3 / h.squareRoot(); m[i] = t * a * delta[i]; m[i + 1] = t * b * delta[i] }
        }
        for i in 0..<(n - 1) {
            let dx = (p[i + 1].x - p[i].x) / 3
            path.addCurve(to: p[i + 1],
                          control1: CGPoint(x: p[i].x + dx, y: p[i].y + m[i] * dx),
                          control2: CGPoint(x: p[i + 1].x - dx, y: p[i + 1].y - m[i + 1] * dx))
        }
        return path
    }
}
