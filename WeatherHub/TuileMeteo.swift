import SwiftUI
import Charts

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  TuileMeteo — la grille de blocs de l'onglet Météo                   ║
// ║  Un bloc par donnée, façon Apple Météo : icône + titre en petites    ║
// ║  capitales, grande valeur, qualificatif, un visuel propre à la       ║
// ║  donnée, et une phrase qui dit ce que ça change pour l'utilisateur.  ║
// ╚══════════════════════════════════════════════════════════════════════╝

/// Hauteur commune : c'est elle qui fait la grille. Les tuiles larges
/// prennent deux colonnes mais gardent cette hauteur.
let hauteurTuile: CGFloat = 148

// MARK: - Le gabarit

struct Tuile<Contenu: View>: View {
    let titre: String
    let icone: String
    let couleur: Color
    var accessoire: String? = nil          // texte discret à droite du titre
    var accessoireCouleur: Color? = nil
    var action: (() -> Void)? = nil        // si présent, la tuile est cliquable
    @ViewBuilder let contenu: () -> Contenu

    var body: some View {
        let corps = VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icone)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(couleur)
                Text(titre.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundColor(.texte.opacity(0.48))
                    .lineLimit(1)
                if let accessoire {
                    Spacer(minLength: 4)
                    Text(accessoire)
                        .font(.system(size: 11, weight: accessoireCouleur == nil ? .medium : .bold))
                        .foregroundColor(accessoireCouleur ?? .texte.opacity(0.48))
                        .lineLimit(1).fixedSize()   // c'est le titre qui cède, pas l'accessoire
                }
            }
            contenu()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: hauteurTuile)
        .fondCarte()
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.surface.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 18))

        if let action {
            Button(action: action) { corps }
                .buttonStyle(.plain)
                .help("Voir le détail sur 48 h")
        } else {
            corps
        }
    }
}

/// Grande valeur + unité, la ligne centrale de la plupart des tuiles.
struct ValeurTuile: View {
    let valeur: String
    var unite: String = ""
    var couleur: Color = .texte
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(typoMoins(valeur))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .foregroundColor(couleur)
            if !unite.isEmpty {
                Text(unite).font(.system(size: 15, weight: .medium)).foregroundColor(couleur.opacity(0.7))
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
    }
}

struct QualiTuile: View {
    let texte: String
    var body: some View {
        Text(texte).font(.system(size: 13, weight: .medium)).foregroundColor(.texte.opacity(0.66)).lineLimit(1)
    }
}

/// La phrase du bas. `Spacer` la pousse au pied de la tuile.
struct NoteTuile: View {
    let texte: String
    var body: some View {
        Text(texte).font(.system(size: 11)).foregroundColor(.texte.opacity(0.48))
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

/// Jauge horizontale : soit une piste remplie, soit un dégradé avec curseur.
struct JaugeTuile: View {
    enum Style { case remplie(Double, Color), curseur(Double, [Color]) }
    let style: Style
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surface.opacity(0.14))
                switch style {
                case .remplie(let t, let c):
                    Capsule().fill(c).frame(width: max(6, g.size.width * t))
                case .curseur(let t, let couleurs):
                    Capsule().fill(LinearGradient(colors: couleurs, startPoint: .leading, endPoint: .trailing)).opacity(0.9)
                    Circle().fill(.white)
                        .overlay(Circle().stroke(Color.texteInverse, lineWidth: 2))
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(x: g.size.width * t - 5.5)
                }
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Le soleil, en vrai

/// Cœur presque blanc, disque chaud, couronne qui respire, douze rayons.
/// Rien qu'un point orange ne disait.
struct SoleilVue: View {
    var rayon: CGFloat = 7.5
    /// 0 = ciel dégagé, 0,5 = nuages, 1 = pluie, neige, orage, brouillard.
    /// Un soleil rayonnant sous la pluie disait le contraire du ciel.
    var couverture: Double = 0
    @State private var respire = false
    @Environment(\.accessibilityReduceMotion) private var reduit

    // Les couleurs à part : inline dans le body, le compilateur Swift
    // met des minutes à typer l'expression et finit par abandonner.
    private static let coeur   = Color(red: 1, green: 0.96, blue: 0.84)
    private static let disque  = Color(red: 1, green: 0.82, blue: 0.40)
    private static let bord    = Color(red: 1, green: 0.60, blue: 0.18)
    private static let halo1   = Color(red: 1, green: 0.78, blue: 0.34).opacity(0.55)
    private static let halo2   = Color(red: 1, green: 0.70, blue: 0.25).opacity(0.22)
    private static let halo3   = Color(red: 1, green: 0.60, blue: 0.18).opacity(0.07)

    var body: some View {
        ZStack {
            halo.opacity(1 - 0.8 * couverture)
            rayons.opacity(1 - couverture)
            disqueSolaire
                .saturation(1 - 0.7 * couverture)
                .opacity(1 - 0.35 * couverture)
        }
        .onAppear {
            guard !reduit, couverture < 1 else { return }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { respire = true }
        }
    }

    /// La couronne diffuse, qui respire lentement.
    private var halo: some View {
        let d = rayon * 7
        return Circle()
            .fill(RadialGradient(colors: [Self.halo1, Self.halo2, Self.halo3, .clear],
                                 center: .center, startRadius: 0, endRadius: rayon * 3.5))
            .frame(width: d, height: d)
            .scaleEffect(respire ? 1.09 : 1)
            .opacity(respire ? 1 : 0.85)
    }

    /// Douze rayons, un long un court, plus vifs quand le halo est gonflé.
    private var rayons: some View {
        let d = rayon * 7
        let r = rayon
        let alpha: Double = respire ? 0.95 : 0.55
        return Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<12 {
                let a = Double(i) * .pi / 6
                let long: CGFloat = i % 2 == 0 ? r * 1.5 : r
                let depart = r + 1.5
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * depart, y: c.y + sin(a) * depart))
                p.addLine(to: CGPoint(x: c.x + cos(a) * (depart + long), y: c.y + sin(a) * (depart + long)))
                ctx.stroke(p, with: .color(Self.disque.opacity(alpha)),
                           style: StrokeStyle(lineWidth: i % 2 == 0 ? 1.7 : 1.2, lineCap: .round))
            }
        }
        .frame(width: d, height: d)
    }

    /// Le disque : cœur presque blanc décalé en haut à gauche, bord chaud.
    private var disqueSolaire: some View {
        Circle()
            .fill(RadialGradient(colors: [Self.coeur, Self.disque, Self.bord],
                                 center: UnitPoint(x: 0.38, y: 0.35), startRadius: 0, endRadius: rayon))
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.6))
            .frame(width: rayon * 2, height: rayon * 2)
    }
}

struct LuneVue: View {
    var rayon: CGFloat = 7
    private static let halo   = Color(red: 0.86, green: 0.89, blue: 1)
    private static let ombre  = Color(red: 0.83, green: 0.85, blue: 0.92)
    private static let mer    = Color(red: 0.47, green: 0.50, blue: 0.59)

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Self.halo.opacity(0.30), Self.halo.opacity(0.08), .clear],
                                     center: .center, startRadius: 0, endRadius: rayon * 2.8))
                .frame(width: rayon * 5.6, height: rayon * 5.6)
            Circle()
                .fill(RadialGradient(colors: [.white, Self.ombre],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: rayon))
                .frame(width: rayon * 2, height: rayon * 2)
            // Les mers : sans elles le disque fait plat.
            Circle().fill(Self.mer.opacity(0.35)).frame(width: rayon * 0.55).offset(x: -rayon * 0.35, y: -rayon * 0.3)
            Circle().fill(Self.mer.opacity(0.30)).frame(width: rayon * 0.65).offset(x: rayon * 0.3, y: rayon * 0.18)
        }
    }
}

// MARK: - Tuile : course du soleil (large)

struct TuileSoleil: View {
    @ObservedObject var vm: WeatherViewModel

    var body: some View {
        let phase = vm.phaseSolaire
        let p = max(0, min(1, phase.progression))
        Tuile(titre: "Course du soleil", icone: "sun.max.fill", couleur: .orange,
              accessoire: phase.estNuit ? "Nuit" : "\(Int(p * 100)) % de la journée") {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let base = h - 4, sommet: CGFloat = 12
                let cx = w / 2, rx = w / 2 - 4, ry = base - sommet
                let point: (Double) -> CGPoint = { t in
                    CGPoint(x: cx - cos(t * .pi) * rx, y: base - sin(t * .pi) * ry)
                }
                ZStack {
                    Path { path in path.move(to: CGPoint(x: 4, y: base)); path.addLine(to: CGPoint(x: w - 4, y: base)) }
                        .stroke(Color.surface.opacity(0.14), lineWidth: 1)
                    Path { path in
                        for i in 0...40 { let pt = point(Double(i) / 40); i == 0 ? path.move(to: pt) : path.addLine(to: pt) }
                    }
                    .stroke(Color.surface.opacity(0.18), style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
                    if !phase.estNuit {
                        Path { path in
                            for i in 0...40 { let pt = point(p * Double(i) / 40); i == 0 ? path.move(to: pt) : path.addLine(to: pt) }
                        }
                        .stroke(Color.orange.opacity(1 - 0.5 * couverture), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        SoleilVue(couverture: couverture).position(point(p))
                    } else {
                        LuneVue().position(x: cx, y: sommet + 2)
                    }
                }
            }
            .frame(height: 62)
            HStack {
                heure("Lever", vm.sunriseString)
                Spacer()
                heure("Midi solaire", midiSolaire, centre: true)
                Spacer()
                heure("Coucher", vm.sunsetString, fin: true)
            }
        }
    }

    /// Ce que la condition laisse voir du soleil.
    private var couverture: Double {
        switch vm.backgroundConditionKey {
        case "clear", "heat", "cold": return 0
        case "cloud":                 return 0.5
        default:                      return 1      // pluie, bruine, orage, neige, brouillard, tornade, tempête, grêle, poussière
        }
    }

    private var midiSolaire: String {
        guard let l = vm.state.sunrise, let c = vm.state.sunset else { return "--:--" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: l.addingTimeInterval(c.timeIntervalSince(l) / 2))
    }

    private func heure(_ label: String, _ valeur: String, centre: Bool = false, fin: Bool = false) -> some View {
        VStack(alignment: fin ? .trailing : centre ? .center : .leading, spacing: 0) {
            Text(label).font(.system(size: 10)).foregroundColor(.texte.opacity(0.48))
            Text(valeur).font(.system(size: 13, weight: .semibold)).foregroundColor(.texte)
        }
    }
}

// MARK: - Tuile : UV

struct TuileUV: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void

    var body: some View {
        let uv = vm.state.uvIndex
        Tuile(titre: "Indice UV", icone: "sun.max", couleur: .yellow, action: ouvrir) {
            ValeurTuile(valeur: String(format: "%.0f", uv))
            QualiTuile(texte: vm.uvLevel.label)
            Spacer(minLength: 0)
            JaugeTuile(style: .curseur(min(1, uv / 11), [.green, .yellow, .orange, .red, .purple]))
            NoteTuile(texte: uv >= 6 ? "Protection conseillée de 12 h à 16 h"
                             : uv >= 3 ? "Crème solaire pour une longue sortie"
                             : "Aucune protection nécessaire")
        }
    }
}

// MARK: - Tuile : vent (boussole)

struct TuileVent: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void

    var body: some View {
        Tuile(titre: "Vent", icone: "wind", couleur: .cyan, action: ouvrir) {
            HStack(spacing: 10) {
                Boussole(direction: Double(vm.state.windDirection)).frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 2) {
                    ValeurTuile(valeur: "\(Int(vm.state.windSpeed))", unite: "km/h")
                    QualiTuile(texte: vm.windDirectionLabel)
                }
            }
            Spacer(minLength: 0)
            // Sur toute la largeur : coincée à côté de la boussole, la note
            // se coupait en « Rafales 20 / km/h ».
            NoteTuile(texte: "Rafales \(Int(vm.state.windGusts)) km/h")
        }
    }
}

struct Boussole: View {
    let direction: Double   // d'où vient le vent, en degrés
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 2
            // Une graduation tous les 10°, sauf aux quatre points cardinaux
            // où la lettre prend la place du trait.
            for i in 0..<36 where i % 9 != 0 {
                let a = Double(i) * 10 * .pi / 180
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * (r - 2.5), y: c.y + sin(a) * (r - 2.5)))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                ctx.stroke(p, with: .color(.texte.opacity(0.45)), lineWidth: 0.8)
            }
            for (l, dx, dy) in [("N", 0.0, -1.0), ("E", 1.0, 0.0), ("S", 0.0, 1.0), ("O", -1.0, 0.0)] {
                ctx.draw(Text(l).font(.system(size: 8, weight: .semibold)).foregroundColor(.texte.opacity(0.66)),
                         at: CGPoint(x: c.x + dx * (r - 5), y: c.y + dy * (r - 5)))
            }
            let a = (direction - 90) * .pi / 180
            var aig = Path()
            aig.move(to: CGPoint(x: c.x - cos(a) * 14, y: c.y - sin(a) * 14))
            aig.addLine(to: CGPoint(x: c.x + cos(a) * 19, y: c.y + sin(a) * 19))
            ctx.stroke(aig, with: .color(.cyan), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(.cyan))
        }
        .accessibilityLabel("Vent de \(Int(direction)) degrés")
    }
}

// MARK: - Tuile : accord des modèles (large)

struct TuileAccord: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void

    var body: some View {
        let r = vm.state.reliability
        let couleur: Color = r >= 80 ? .green : r >= 50 ? .yellow : .red
        Tuile(titre: "Accord des modèles", icone: "chart.line.uptrend.xyaxis", couleur: .green,
              accessoire: "\(r) %", accessoireCouleur: couleur, action: ouvrir) {
            JaugeTuile(style: .remplie(Double(r) / 100, couleur))
            if vm.modelesTemperature.count > 1 {
                let med = vm.state.temperature
                HStack(spacing: 6) {
                    ForEach(vm.modelesTemperature, id: \.modele) { m in
                        VStack(spacing: 1) {
                            Text(m.modele.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5)
                                .foregroundColor(.texte.opacity(0.48)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(typoMoins(String(format: "%.1f°", m.valeur))).font(.system(size: 13, weight: .semibold)).foregroundColor(.texte)
                            Text(typoMoins(String(format: "%+.1f", m.valeur - med))).font(.system(size: 9)).foregroundColor(.texte.opacity(0.48))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(Color.surface.opacity(0.055)).cornerRadius(9)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.surface.opacity(0.13), lineWidth: 1))
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 0)
                NoteTuile(texte: String(format: "%.1f °C d'écart entre le centre le plus froid et le plus chaud.",
                                        vm.state.temperatureHigh - vm.state.temperatureLow))
            } else {
                Spacer(minLength: 0)
                NoteTuile(texte: vm.state.modelCount > 1
                          ? "Les \(vm.state.modelCount) modèles se situent entre \(String(format: "%.1f", vm.state.temperatureLow)) et \(String(format: "%.1f", vm.state.temperatureHigh)) °C."
                          : "Une seule source pour l'instant.")
            }
        }
    }
}

// MARK: - Tuiles simples

struct TuileRessenti: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void
    var body: some View {
        let ecart = vm.state.feelsLike - vm.state.temperature
        Tuile(titre: "Ressenti", icone: "thermometer.medium", couleur: .orange, action: ouvrir) {
            ValeurTuile(valeur: "\(Int(vm.state.feelsLike.rounded()))", unite: "°C")
            QualiTuile(texte: abs(ecart) < 1 ? "Comme la température" : ecart < 0 ? "Plus frais" : "Plus chaud")
            Spacer(minLength: 0)
            NoteTuile(texte: abs(ecart) < 1 ? "Ni le vent ni l'humidité ne changent la sensation."
                             : ecart < 0 ? "Le vent et l'humidité font paraître l'air plus frais."
                             : "L'humidité rend la chaleur plus lourde.")
        }
    }
}

struct TuileHumidite: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void
    var body: some View {
        Tuile(titre: "Humidité", icone: "humidity.fill", couleur: .blue, action: ouvrir) {
            ValeurTuile(valeur: "\(vm.state.humidity)", unite: "%")
            Spacer(minLength: 0)
            JaugeTuile(style: .remplie(Double(vm.state.humidity) / 100, .blue))
            NoteTuile(texte: String(format: "Point de rosée %.0f °C — %@", vm.state.dewPoint,
                                    vm.state.dewPoint < 13 ? "air confortable" : vm.state.dewPoint < 18 ? "air un peu lourd" : "air moite"))
        }
    }
}

struct TuilePrecipitations: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void
    var body: some View {
        Tuile(titre: "Précipitations", icone: "cloud.rain.fill", couleur: .blue, action: ouvrir) {
            // mm tombés sur la dernière heure, donc des mm/h.
            ValeurTuile(valeur: String(format: "%.1f", vm.state.precipitationMm), unite: "mm/h")
            Spacer(minLength: 0)
            // Les 3 prochaines heures par quart d'heure : une barre chacun.
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(vm.pluieImminente.prefix(12)) { q in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue.opacity(q.pleut ? 0.7 : 0.3))
                        .frame(height: max(2, CGFloat(min(100, q.probabilite)) / 100 * 22))
                        .frame(maxWidth: .infinity)
                }
                if vm.pluieImminente.isEmpty {
                    ForEach(0..<12, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.surface.opacity(0.14)).frame(height: 2).frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 22)
            NoteTuile(texte: vm.prochainePluie.map { "Pluie dans \($0.minutes) min" } ?? "Rien d'ici 3 h")
        }
    }
}

struct TuileNuages: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void
    var body: some View {
        let c = vm.state.cloudCover
        Tuile(titre: "Nuages", icone: "cloud.fill", couleur: .gray, action: ouvrir) {
            ValeurTuile(valeur: "\(c)", unite: "%")
            QualiTuile(texte: c < 25 ? "Ciel dégagé" : c < 60 ? "Partiellement couvert" : c < 90 ? "Très nuageux" : "Couvert")
            Spacer(minLength: 0)
            JaugeTuile(style: .remplie(Double(c) / 100, .gray))
            NoteTuile(texte: c < 25 ? "Le soleil est largement visible." : c < 60 ? "Éclaircies probables." : "Peu de soleil à attendre.")
        }
    }
}

struct TuileVisibilite: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void
    var body: some View {
        let v = vm.state.visibility
        Tuile(titre: "Visibilité", icone: "eye.fill", couleur: .indigo, action: ouvrir) {
            ValeurTuile(valeur: "\(Int(v))", unite: "km")
            QualiTuile(texte: v >= 10 ? "Parfaitement dégagé" : v >= 4 ? "Bonne" : v >= 1 ? "Réduite" : "Brouillard")
            Spacer(minLength: 0)
            NoteTuile(texte: v >= 10 ? "Aucune brume ni brouillard attendus." : v >= 4 ? "Légère brume à l'horizon." : "Prudence sur la route.")
        }
    }
}

struct TuilePression: View {
    @ObservedObject var vm: WeatherViewModel
    var body: some View {
        let p = vm.state.pressure
        let t = max(0, min(1, (p - 980) / 60))
        Tuile(titre: "Pression", icone: "gauge.with.dots.needle.33percent", couleur: .texte.opacity(0.66)) {
            ValeurTuile(valeur: "\(Int(p))", unite: "hPa")
            Spacer(minLength: 0)
            // Demi-jauge 980–1040 hPa : la plage où vit la météo courante.
            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height - 2, r = min(size.width / 2 - 4, size.height - 6)
                let arc: (Double, Double) -> Path = { a, b in
                    var path = Path()
                    for i in 0...30 { let k = a + (b - a) * Double(i) / 30
                        let pt = CGPoint(x: cx - cos(k * .pi) * r, y: cy - sin(k * .pi) * r)
                        i == 0 ? path.move(to: pt) : path.addLine(to: pt) }
                    return path
                }
                ctx.stroke(arc(0, 1), with: .color(.surface.opacity(0.14)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                ctx.stroke(arc(0, t), with: .color(.cyan), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                let pt = CGPoint(x: cx - cos(t * .pi) * r, y: cy - sin(t * .pi) * r)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9)), with: .color(.white))
                ctx.draw(Text("Basse").font(.system(size: 8)).foregroundColor(.texte.opacity(0.48)), at: CGPoint(x: cx - r, y: cy + 8))
                ctx.draw(Text("Haute").font(.system(size: 8)).foregroundColor(.texte.opacity(0.48)), at: CGPoint(x: cx + r, y: cy + 8))
            }
            .frame(height: 40)
            NoteTuile(texte: p < 1000 ? "Basse — temps instable possible" : p < 1020 ? "Normale — temps stable" : "Haute — beau temps probable")
        }
    }
}

struct TuileAir: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void
    var body: some View {
        let a = vm.state.aqi
        let couleur: Color = a <= 1 ? .green : a == 2 ? .mint : a == 3 ? .yellow : a == 4 ? .orange : .red
        Tuile(titre: "Qualité de l'air", icone: "aqi.medium", couleur: .mint, action: ouvrir) {
            ValeurTuile(valeur: a == 0 ? "–" : "\(a)")
            // « Acceptable · O₃ » : le niveau, et le polluant qui le fixe
            QualiTuile(texte: vm.state.aqiLabel.isEmpty || a == 0 ? "Indisponible"
                       : vm.state.aqiDominant.isEmpty ? vm.state.aqiLabel : "\(vm.state.aqiLabel) · \(vm.state.aqiDominant)")
            Spacer(minLength: 0)
            JaugeTuile(style: .curseur(a == 0 ? 0 : (Double(a) - 0.5) / 5, [.green, .yellow, .orange, .red, .purple]))
            NoteTuile(texte: a <= 2 ? "Bonne journée pour aérer et sortir." : a == 3 ? "Personnes sensibles : limitez l'effort." : "Évitez l'effort prolongé en extérieur.")
                .foregroundColor(a >= 4 ? couleur : .texte.opacity(0.48))
        }
    }
}

struct TuileHier: View {
    @ObservedObject var vm: WeatherViewModel
    var body: some View {
        Tuile(titre: "Par rapport à hier", icone: "clock.arrow.circlepath", couleur: .orange) {
            if let hier = vm.hier {
                let ecart = vm.state.temperature - hier.max
                let maxAuj = max(vm.state.temperature, hier.max, 1)
                ValeurTuile(valeur: String(format: "%+.1f", ecart), unite: "°C", couleur: abs(ecart) < 0.5 ? .texte : ecart > 0 ? .orange : .cyan)
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    barre("Auj.", vm.state.temperature / maxAuj, .orange, typoMoins(String(format: "%.1f°", vm.state.temperature)))
                    barre("Hier", hier.max / maxAuj, .texte.opacity(0.4), typoMoins(String(format: "%.1f°", hier.max)))
                }
                NoteTuile(texte: abs(ecart) < 0.5 ? "Comme hier à la même heure." : ecart > 0 ? "Plus doux qu'hier." : "Plus frais qu'hier.")
            } else {
                ValeurTuile(valeur: "–")
                Spacer(minLength: 0)
                NoteTuile(texte: "Températures d'hier en cours de chargement.")
            }
        }
    }
    private func barre(_ l: String, _ t: Double, _ c: Color, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(l).font(.system(size: 10)).foregroundColor(.texte.opacity(0.48)).frame(width: 26, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface.opacity(0.14))
                    Capsule().fill(c).frame(width: max(4, g.size.width * t))
                }
            }.frame(height: 5)
            Text(v).font(.system(size: 10, weight: .medium)).foregroundColor(.texte.opacity(0.66)).frame(width: 34, alignment: .trailing)
        }
    }
}

struct TuileRosee: View {
    @ObservedObject var vm: WeatherViewModel
    var body: some View {
        let d = vm.state.dewPoint
        Tuile(titre: "Point de rosée", icone: "drop.degreesign", couleur: .cyan) {
            ValeurTuile(valeur: "\(Int(d.rounded()))", unite: "°C")
            QualiTuile(texte: d < 10 ? "Air sec" : d < 13 ? "Confortable" : d < 18 ? "Un peu lourd" : "Moite")
            Spacer(minLength: 0)
            NoteTuile(texte: d < 13 ? "En dessous de 13 °C, l'air ne colle pas." : "Au-dessus de 13 °C, la sueur s'évapore mal.")
        }
    }
}

struct TuileRafales: View {
    @ObservedObject var vm: WeatherViewModel
    var ouvrir: () -> Void
    var body: some View {
        let r = vm.state.windGusts
        Tuile(titre: "Rafales", icone: "wind.circle.fill", couleur: .orange, action: ouvrir) {
            ValeurTuile(valeur: "\(Int(r))", unite: "km/h")
            QualiTuile(texte: r < 30 ? "Faibles" : r < 50 ? "Modérées" : r < 75 ? "Fortes" : "Tempête")
            Spacer(minLength: 0)
            JaugeTuile(style: .remplie(min(1, r / 100), r < 50 ? .orange : .red))
            NoteTuile(texte: r < 30 ? "Rien à craindre." : r < 50 ? "Attention aux objets légers." : "Évitez les zones boisées.")
        }
    }
}

// MARK: - Tuile : meilleur sport (large)

struct TuileSport: View {
    @ObservedObject var vm: WeatherViewModel
    private static let h: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH'h'"; return f }()
    var body: some View {
        Tuile(titre: "Meilleur sport", icone: "figure.run", couleur: .green,
              accessoire: vm.sports.first.map { "\($0.score)/100" }) {
            if let s = vm.sports.first {
                HStack(spacing: 12) {
                    Image(systemName: s.sport.icon).font(.system(size: 26)).foregroundColor(.texte).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        ValeurTuile(valeur: vm.bestSportAdvice)
                        QualiTuile(texte: s.level.label + " · " + s.resume)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
                if let c = vm.creneaux.first {
                    NoteTuile(texte: "Meilleur créneau : \(Self.h.string(from: c.debut)) – \(Self.h.string(from: c.fin))")
                } else {
                    NoteTuile(texte: "Créneau optimal en cours de calcul.")
                }
            } else {
                ValeurTuile(valeur: "–")
                Spacer(minLength: 0)
                NoteTuile(texte: "Évaluation en attente des données.")
            }
        }
    }
}

// MARK: - Tuile : 24 prochaines heures (large)

struct TuileTendance: View {
    @ObservedObject var vm: WeatherViewModel
    var body: some View {
        let h = Array(vm.previsionsHoraires.prefix(24))
        let tmin = h.map(\.temperature).min() ?? 0, tmax = h.map(\.temperature).max() ?? 0
        Tuile(titre: "24 prochaines heures", icone: "chart.xyaxis.line", couleur: .orange,
              accessoire: h.isEmpty ? nil : String(format: "max %.0f° · min %.0f°", tmax, tmin)) {
            if h.isEmpty {
                Spacer(minLength: 0)
                NoteTuile(texte: "Prévision horaire en cours de chargement.")
            } else {
                // Le plancher du graphe ; les barres de pluie partent de là,
                // pas de 0 °C, sinon elles remplissent tout le bas.
                let plancher = tmin - 1
                let hauteurPluie = (tmax + 2 - plancher) * 0.35
                Chart {
                    ForEach(h.filter { $0.probaPluie > 0 }) { p in
                        BarMark(x: .value("Heure", p.date),
                                yStart: .value("Plancher", plancher),
                                yEnd: .value("Pluie", plancher + Double(p.probaPluie) / 100 * hauteurPluie))
                            .foregroundStyle(Color.blue.opacity(0.28))
                    }
                    ForEach(h) { p in
                        AreaMark(x: .value("Heure", p.date), yStart: .value("min", tmin), yEnd: .value("°C", p.temperature))
                            .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.28), .orange.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Heure", p.date), y: .value("°C", p.temperature))
                            .foregroundStyle(.orange).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    RuleMark(x: .value("Maintenant", Date())).foregroundStyle(Color.cyan.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: (tmin - 1)...(tmax + 2))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour()).font(.system(size: 9)).foregroundStyle(Color.texte.opacity(0.48))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.surface.opacity(0.10))
                        AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.texte.opacity(0.48))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}
