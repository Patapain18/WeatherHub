import SwiftUI

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  HoraireTabView — les 48 prochaines heures en un seul graphique      ║
// ║  Maquette B « le graphique-loupe », choisie par Mathis : la courbe   ║
// ║  de température, les icônes du temps toutes les trois heures, les   ║
// ║  nuits en bandes sombres, la pluie en barres, le lever et le coucher ║
// ║  — et une loupe au survol qui donne tout ce que disaient les 48     ║
// ║  lignes de l'ancienne liste, à l'heure qu'on regarde.               ║
// ╚══════════════════════════════════════════════════════════════════════╝

struct HoraireTabView: View {
    @ObservedObject var vm: WeatherViewModel

    /// Température vue par les quatre modèles, pour la bande d'incertitude
    /// autour de la courbe. Chargée à l'ouverture de l'onglet, pas au démarrage.
    @State private var serieTemperature: SerieHoraire?

    var body: some View {
        ScrollView {
            SondeDefilement()
            VStack(spacing: 20) {
                entete
                if vm.previsionsHoraires.isEmpty {
                    chargement
                } else {
                    carte
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

    // MARK: - La carte : titre, graphique, légende

    private var carte: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("48 heures").font(.headline).foregroundColor(.texte)
                Spacer()
                Text("survole pour lire une heure")
                    .font(.caption2).foregroundColor(.texte.opacity(0.45))
            }
            .padding(.horizontal, 20).padding(.top, 16)

            GraphiqueHoraire(heures: vm.previsionsHoraires, serie: serieTemperature,
                             lever: vm.state.sunrise, coucher: vm.state.sunset)
                .frame(height: 440)
                .padding(.horizontal, 8)

            HStack(spacing: 16) {
                legende(GraphiqueHoraire.couleurCourbe, "Température")
                if let s = serieTemperature, s.aUneBande {
                    legende(GraphiqueHoraire.couleurCourbe.opacity(0.3), "Écart entre \(s.nbModeles) modèles")
                }
                legende(GraphiqueHoraire.couleurPluie, "Pluie (probabilité)")
                legende(Color.texte.opacity(0.18), "Nuit")
                legende(.cyan, "Maintenant")
            }
            .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 14)
        }
        .fondCarte().cornerRadius(22)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
    }

    private func legende(_ couleur: Color, _ texte: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(couleur).frame(width: 18, height: 3)
            Text(texte).font(.caption2).foregroundColor(.texte.opacity(0.45))
        }
    }
}

// MARK: - Le graphique

/// Tout est dessiné à la main dans un Canvas, à partir de deux échelles
/// (l'heure → x, la température → y) : c'est ce qui permet de poser sur
/// le même dessin des choses que Swift Charts ne sait pas mélanger — une
/// courbe, des barres sur une autre échelle, des bandes, des icônes.
struct GraphiqueHoraire: View {
    let heures: [PrevisionHeure]
    let serie: SerieHoraire?
    let lever: Date?
    let coucher: Date?

    /// L'heure sous la souris, ou rien.
    @State private var survol: Int? = nil

    static let couleurCourbe = Color(red: 1.0, green: 0.70, blue: 0.65)
    static let couleurPluie  = Color(red: 0.44, green: 0.70, blue: 1.0)
    private static let couleurPluieTexte = Color(red: 0.74, green: 0.86, blue: 1.0)
    private static let couleurNuit = Color(red: 0.02, green: 0.04, blue: 0.10).opacity(0.28)

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH'h'"; return f
    }()
    private static let formatHeureMinute: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let formatJour: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "fr_FR"); return f
    }()

    var body: some View {
        GeometryReader { geo in
            let d = Disposition(largeur: geo.size.width, hauteur: geo.size.height, heures: heures, serie: serie)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in dessiner(ctx, d) }
                icones(d)
                leversEtCouchers(d)
                if let i = survol, heures.indices.contains(i) { loupe(i, d, largeur: geo.size.width) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): survol = d.index(x: p.x)
                case .ended:         survol = nil
                }
            }
        }
        // VoiceOver lit les 48 heures une par une, comme l'ancienne liste
        .accessibilityRepresentation {
            VStack {
                ForEach(Array(heures.enumerated()), id: \.element.id) { i, h in
                    Text(resumeVocal(h, estMaintenant: i == 0))
                }
            }
        }
    }

    // MARK: Les échelles

    /// Où va chaque chose, en points. Calculé une fois par dessin.
    struct Disposition {
        let largeur: CGFloat, hauteur: CGFloat
        let n: Int
        let gauche: CGFloat = 16, droite: CGFloat = 24
        let yIcones: CGFloat = 44
        let yJour: CGFloat = 66                       // le haut des lignes « DEMAIN »
        let haut: CGFloat = 96                         // la courbe vit entre haut et bas
        let bas: CGFloat
        let hauteurPluie: CGFloat = 46
        let yAxe: CGFloat
        let tMin: Double, tMax: Double

        init(largeur: CGFloat, hauteur: CGFloat, heures: [PrevisionHeure], serie: SerieHoraire?) {
            self.largeur = largeur; self.hauteur = hauteur
            n = max(heures.count, 2)
            yAxe = hauteur - 26
            bas = hauteur - 144
            var lo = heures.map(\.temperature).min() ?? 0, hi = heures.map(\.temperature).max() ?? 20
            if let s = serie {
                for p in s.points { if let b = p.bas { lo = min(lo, b) }; if let h = p.haut { hi = max(hi, h) } }
            }
            tMin = lo - 2; tMax = max(hi + 3, lo + 8)
        }

        var pas: CGFloat { (largeur - gauche - droite) / CGFloat(n - 1) }
        func x(_ i: Int) -> CGFloat { gauche + CGFloat(i) * pas }
        func x(_ f: Double) -> CGFloat { gauche + CGFloat(f) * pas }
        func y(_ t: Double) -> CGFloat { bas - CGFloat((t - tMin) / (tMax - tMin)) * (bas - haut) }
        var basPluie: CGFloat { bas + 6 + hauteurPluie }
        func yPluie(_ proba: Int) -> CGFloat { basPluie - CGFloat(proba) / 100 * hauteurPluie }
        func index(x: CGFloat) -> Int { max(0, min(n - 1, Int(((x - gauche) / pas).rounded()))) }
    }

    /// L'heure `date` en position fractionnaire sur l'axe (0 = maintenant).
    private func position(_ date: Date) -> Double? {
        guard let debut = heures.first?.date else { return nil }
        return date.timeIntervalSince(debut) / 3600
    }

    /// Le lever et le coucher de chaque jour couvert : ceux d'aujourd'hui,
    /// décalés de 24 h — à quelques minutes près, c'est juste.
    private var evenementsSoleil: [(f: Double, lever: Bool, date: Date)] {
        guard let lever, let coucher, let fin = heures.last?.date else { return [] }
        var r: [(Double, Bool, Date)] = []
        for k in -1...2 {
            for (base, estLever) in [(lever, true), (coucher, false)] {
                let d = base.addingTimeInterval(Double(k) * 86400)
                if let f = position(d), f >= 0.3, d <= fin { r.append((f, estLever, d)) }
            }
        }
        return r.sorted { $0.0 < $1.0 }
    }

    private func estNuit(_ date: Date) -> Bool {
        guard let lever, let coucher else { return false }
        let cal = Calendar.current
        let h = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let l = cal.component(.hour, from: lever) * 60 + cal.component(.minute, from: lever)
        let c = cal.component(.hour, from: coucher) * 60 + cal.component(.minute, from: coucher)
        return h < l || h > c
    }

    /// Les heures « pleines » où l'on pose une icône et une étiquette :
    /// maintenant, puis toutes les trois heures — sauf les deux heures qui
    /// suivent « maintenant », qui se marcheraient dessus.
    private func estJalon(_ i: Int) -> Bool {
        guard i > 0 else { return true }
        return i > 2 && Calendar.current.component(.hour, from: heures[i].date) % 3 == 0
    }

    // MARK: Le dessin

    private func dessiner(_ ctx: GraphicsContext, _ d: Disposition) {
        let cal = Calendar.current
        // Les nuits : du coucher d'un jour au lever du suivant, rognées aux 48 h
        if let lever, let coucher {
            for k in -1...2 {
                guard let a = position(coucher.addingTimeInterval(Double(k) * 86400)),
                      let b = position(lever.addingTimeInterval(Double(k + 1) * 86400)) else { continue }
                let debut = max(0, a), fin = min(Double(d.n - 1), b)
                if fin > debut {
                    ctx.fill(Path(CGRect(x: d.x(debut), y: 8, width: d.x(fin) - d.x(debut), height: d.yAxe - 22)), with: .color(Self.couleurNuit))
                }
            }
        }

        // Les jours : une ligne à minuit et le nom du jour
        for (i, h) in heures.enumerated() where cal.component(.hour, from: h.date) == 0 && i > 0 {
            var ligne = Path(); ligne.move(to: CGPoint(x: d.x(i), y: d.yJour)); ligne.addLine(to: CGPoint(x: d.x(i), y: d.yAxe - 14))
            ctx.stroke(ligne, with: .color(.texte.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            let nom = cal.isDateInTomorrow(h.date) ? "DEMAIN" : Self.formatJour.string(from: h.date).uppercased()
            ctx.draw(Text(nom).font(.system(size: 10.5, weight: .bold)).foregroundColor(.texte.opacity(0.62)),
                     at: CGPoint(x: d.x(i) + 6, y: d.yJour + 6), anchor: .leading)
        }

        // La bande des modèles, l'aire, la courbe
        let points = heures.enumerated().map { i, h in CGPoint(x: d.x(i), y: d.y(h.temperature)) }
        if let s = serie {
            let hauts = bornes(s, d, \.haut), bas = bornes(s, d, \.bas)
            if hauts.count > 1 && bas.count == hauts.count {
                var bande = AireColoree.lissageMonotone(hauts)
                bande.addLine(to: bas.last!)
                for p in bas.reversed().dropFirst() { bande.addLine(to: p) }
                bande.closeSubpath()
                ctx.fill(bande, with: .color(Self.couleurCourbe.opacity(0.14)))
            }
        }
        var aire = AireColoree.lissageMonotone(points)
        aire.addLine(to: CGPoint(x: d.x(d.n - 1), y: d.bas))
        aire.addLine(to: CGPoint(x: d.x(0), y: d.bas))
        aire.closeSubpath()
        ctx.fill(aire, with: .linearGradient(
            Gradient(colors: [Self.couleurCourbe.opacity(0.32), Self.couleurCourbe.opacity(0)]),
            startPoint: CGPoint(x: 0, y: d.haut), endPoint: CGPoint(x: 0, y: d.bas)))
        ctx.stroke(AireColoree.lissageMonotone(points), with: .color(Self.couleurCourbe),
                   style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        for (i, h) in heures.enumerated() where estJalon(i) {
            ctx.draw(Text(typoMoins(String(format: "%.0f°", h.temperature))).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.texte),
                     at: CGPoint(x: d.x(i), y: d.y(h.temperature) - 12), anchor: .center)
        }

        // La pluie : des barres en bas, une étiquette par sommet seulement
        var sol = Path(); sol.move(to: CGPoint(x: d.gauche, y: d.basPluie)); sol.addLine(to: CGPoint(x: d.largeur - d.droite, y: d.basPluie))
        ctx.stroke(sol, with: .color(.texte.opacity(0.10)), lineWidth: 1)
        let lb = d.pas * 0.7
        for (i, h) in heures.enumerated() where h.probaPluie > 0 {
            let r = CGRect(x: d.x(i) - lb / 2, y: d.yPluie(h.probaPluie), width: lb, height: d.basPluie - d.yPluie(h.probaPluie))
            ctx.fill(Path(roundedRect: r, cornerRadius: 2.5), with: .color(Self.couleurPluie.opacity(0.35 + Double(h.probaPluie) / 140)))
            let avant = i == 0 ? 0 : heures[i - 1].probaPluie, apres = i == d.n - 1 ? 0 : heures[i + 1].probaPluie
            if h.probaPluie >= 30 && avant <= h.probaPluie && apres < h.probaPluie {
                let mm = h.precipitation > 0 ? " · \(String(format: "%.1f", h.precipitation).replacingOccurrences(of: ".", with: ",")) mm" : ""
                ctx.draw(Text("\(h.probaPluie) %\(mm)").font(.system(size: 10.5, weight: .semibold)).foregroundColor(Self.couleurPluieTexte),
                         at: CGPoint(x: d.x(i), y: d.yPluie(h.probaPluie) - 8), anchor: .center)
            }
        }

        // Maintenant
        var maintenant = Path(); maintenant.move(to: CGPoint(x: d.x(0), y: 8)); maintenant.addLine(to: CGPoint(x: d.x(0), y: d.yAxe - 14))
        ctx.stroke(maintenant, with: .color(.cyan), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))

        // L'axe des heures
        for (i, h) in heures.enumerated() where estJalon(i) {
            ctx.draw(Text(i == 0 ? "Maint." : Self.formatHeure.string(from: h.date)).font(.system(size: 11)).foregroundColor(.texte.opacity(0.42)),
                     at: CGPoint(x: d.x(i), y: d.yAxe), anchor: .center)
        }

        // Le curseur du survol
        if let i = survol, heures.indices.contains(i) {
            var ligne = Path(); ligne.move(to: CGPoint(x: d.x(i), y: 8)); ligne.addLine(to: CGPoint(x: d.x(i), y: d.yAxe - 14))
            ctx.stroke(ligne, with: .color(.texte.opacity(0.55)), lineWidth: 1)
            let p = CGPoint(x: d.x(i), y: d.y(heures[i].temperature))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(Self.couleurCourbe))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(Color(red: 0.08, green: 0.10, blue: 0.17)), lineWidth: 2)
        }
    }

    /// Les bornes d'un modèle (haut ou bas) alignées sur nos 48 heures.
    private func bornes(_ s: SerieHoraire, _ d: Disposition, _ cle: KeyPath<SerieHoraire.Point, Double?>) -> [CGPoint] {
        var r: [CGPoint] = []
        for (i, h) in heures.enumerated() {
            guard let p = s.points.first(where: { abs($0.date.timeIntervalSince(h.date)) < 1800 }), let v = p[keyPath: cle] else { continue }
            r.append(CGPoint(x: d.x(i), y: d.y(v)))
        }
        return r
    }

    // MARK: Ce qui se pose par-dessus le dessin

    /// Les icônes du temps, toutes les trois heures, au-dessus de la courbe.
    private func icones(_ d: Disposition) -> some View {
        ForEach(Array(heures.enumerated()), id: \.element.id) { i, h in
            if estJalon(i) {
                let nuit = estNuit(h.date)
                Image(systemName: iconePourCodeWMO(h.codeMeteo, nuit: nuit))
                    .font(.system(size: 19))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(couleurIcone(h.codeMeteo, nuit: nuit), .gray)
                    .position(x: d.x(i), y: d.yIcones)
            }
        }
    }

    /// Le lever et le coucher : un petit soleil sous les barres de pluie.
    private func leversEtCouchers(_ d: Disposition) -> some View {
        ForEach(Array(evenementsSoleil.enumerated()), id: \.offset) { _, e in
            VStack(spacing: 3) {
                Image(systemName: e.lever ? "sunrise.fill" : "sunset.fill")
                    .font(.system(size: 13)).symbolRenderingMode(.palette).foregroundStyle(.yellow, .texte.opacity(0.7))
                Text("\(e.lever ? "Lever" : "Coucher") \(Self.formatHeureMinute.string(from: e.date))")
                    .font(.system(size: 10.5)).foregroundColor(.yellow.opacity(0.9))
            }
            .position(x: d.x(e.f), y: d.yAxe - 34)
        }
    }

    /// La loupe : ce que disait une ligne de l'ancienne liste, et plus.
    private func loupe(_ i: Int, _ d: Disposition, largeur: CGFloat) -> some View {
        let h = heures[i]
        let nuit = estNuit(h.date)
        let largeurLoupe: CGFloat = 214
        let aDroite = d.x(i) + 18 + largeurLoupe < largeur
        let x = aDroite ? d.x(i) + 18 + largeurLoupe / 2 : d.x(i) - 18 - largeurLoupe / 2
        let y = min(max(d.y(h.temperature) - 10, 70), d.bas)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconePourCodeWMO(h.codeMeteo, nuit: nuit))
                    .font(.system(size: 24)).symbolRenderingMode(.palette)
                    .foregroundStyle(couleurIcone(h.codeMeteo, nuit: nuit), .gray)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(typoMoins(String(format: "%.0f°", h.temperature)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundColor(.texte)
                    Text("\(quand(i)) · \(libellePourCodeWMO(h.codeMeteo))")
                        .font(.system(size: 11)).foregroundColor(.texte.opacity(0.62)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                ligneLoupe("Ressenti", typoMoins(String(format: "%.0f°", h.ressenti)))
                ligneLoupe("Vent", "\(Int(h.vent)) km/h")
                ligneLoupe("Rafales", "\(Int(h.rafales)) km/h")
                ligneLoupe("Pluie", "\(h.probaPluie) %" + (h.precipitation > 0 ? " · \(String(format: "%.1f", h.precipitation).replacingOccurrences(of: ".", with: ",")) mm" : ""))
                if h.uv >= 1 { ligneLoupe("UV", "\(Int(h.uv))") }
            }
        }
        .padding(12)
        .frame(width: largeurLoupe, alignment: .leading)
        .background(Color(red: 0.08, green: 0.10, blue: 0.17).opacity(0.96))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 10)
        .position(x: x, y: y)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func ligneLoupe(_ nom: String, _ valeur: String) -> some View {
        GridRow {
            Text(nom).font(.system(size: 12)).foregroundColor(.texte.opacity(0.45))
            Text(valeur).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.texte)
                .gridColumnAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// « Maintenant », « 17h », « Demain 15h », « Samedi 09h ».
    private func quand(_ i: Int) -> String {
        guard i > 0 else { return "Maintenant" }
        let date = heures[i].date, cal = Calendar.current
        let heure = Self.formatHeure.string(from: date)
        if cal.isDateInToday(date) { return heure }
        if cal.isDateInTomorrow(date) { return "Demain \(heure)" }
        return "\(Self.formatJour.string(from: date).capitalized) \(heure)"
    }

    private func couleurIcone(_ code: Int, nuit: Bool) -> Color {
        switch code {
        case 0, 1, 2:  return nuit ? Color(red: 0.85, green: 0.88, blue: 1.0) : .yellow
        case 45, 48:   return .gray
        case 51...67, 80...82: return .blue
        case 71...77, 85, 86:  return .cyan
        case 95...99:  return .purple
        default:       return .texte
        }
    }

    private func resumeVocal(_ h: PrevisionHeure, estMaintenant: Bool) -> String {
        var s = estMaintenant ? "Maintenant" : Self.formatHeure.string(from: h.date)
        s += ", \(libellePourCodeWMO(h.codeMeteo)), \(Int(h.temperature)) degrés, ressenti \(Int(h.ressenti))"
        if h.probaPluie >= 10 { s += ", \(h.probaPluie) pour cent de pluie" }
        s += ", vent \(Int(h.vent)) kilomètres heure"
        if h.uv >= 3 { s += ", UV \(Int(h.uv))" }
        return s
    }
}
