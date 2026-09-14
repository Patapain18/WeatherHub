import SwiftUI
import MapKit

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  CarteTabView — radar de précipitations animé et couches météo       ║
// ╚══════════════════════════════════════════════════════════════════════╝

// MARK: - Couches disponibles

enum CoucheCarte: String, CaseIterable, Identifiable {
    case radar, nuages, temperature, vent, pression, precipitations

    var id: String { rawValue }

    var titre: String {
        switch self {
        case .radar:          return "Radar"
        case .nuages:         return "Nuages"
        case .temperature:    return "Température"
        case .vent:           return "Vent"
        case .pression:       return "Pression"
        case .precipitations: return "Pluie (modèle)"
        }
    }

    var icone: String {
        switch self {
        case .radar:          return "dot.radiowaves.left.and.right"
        case .nuages:         return "cloud.fill"
        case .temperature:    return "thermometer.medium"
        case .vent:           return "wind"
        case .pression:       return "gauge.with.dots.needle.33percent"
        case .precipitations: return "cloud.rain.fill"
        }
    }

    /// Le radar est une MESURE (écho radar réel) ; les autres couches
    /// sont des sorties de modèle. La distinction est affichée.
    var estMesure: Bool { self == .radar }

    /// Identifiant de couche chez OpenWeather. Nil pour le radar, qui
    /// vient de RainViewer.
    var coucheOpenWeather: String? {
        switch self {
        case .radar:          return nil
        case .nuages:         return "clouds_new"
        case .temperature:    return "temp_new"
        case .vent:           return "wind_new"
        case .pression:       return "pressure_new"
        case .precipitations: return "precipitation_new"
        }
    }

    /// Comment rendre la couche lisible sur notre fond sombre.
    ///
    /// Mesuré tuile par tuile : les nuages et le vent sortent d'OpenWeather
    /// avec une opacité franche (≥ 250/255), la température et la pression
    /// sont pâles (76–102), et les précipitations quasi invisibles
    /// (opacité médiane **3/255**, en bleu lavande). Leur palette est
    /// pensée pour une carte claire ; on la corrige à la volée.
    var traitement: TraitementTuile? {
        switch self {
        case .radar, .nuages, .vent: return nil
        case .temperature:           return TraitementTuile(gammaAlpha: 0.55, teinte: nil)
        case .pression:              return TraitementTuile(gammaAlpha: 0.60, teinte: nil)
        case .precipitations:        return TraitementTuile(gammaAlpha: 0.30, teinte: (0.25, 0.55, 1.0))
        }
    }

    /// Ce que veulent dire les couleurs, pour la légende.
    var legende: [(couleur: Color, texte: String)] {
        switch self {
        case .radar, .precipitations:
            return [(.green, "Faible"), (.yellow, "Modérée"), (.orange, "Forte"), (.red, "Violente / orage")]
        case .nuages:
            return [(.white.opacity(0.3), "Voile"), (.white.opacity(0.7), "Couvert"), (.white, "Très dense")]
        case .temperature:
            return [(.blue, "< 0 °C"), (.cyan, "0–10"), (.green, "10–20"), (.orange, "20–30"), (.red, "> 30 °C")]
        case .vent:
            return [(.blue.opacity(0.5), "Calme"), (.purple, "Modéré"), (.pink, "Fort")]
        case .pression:
            return [(.blue, "Basse"), (.green, "Normale"), (.red, "Haute")]
        }
    }
}

// MARK: - Renforcement d'une tuile trop pâle

struct TraitementTuile {
    /// Exposant appliqué à l'opacité normalisée : < 1 remonte les faibles
    /// valeurs sans écraser les fortes. À 0,30, une opacité de 3/255
    /// passe à ~67/255 ; 255 reste 255.
    let gammaAlpha: Double
    /// Couleur imposée (0–1). `nil` conserve la couleur d'origine — pour
    /// la température ou la pression, où la teinte porte l'information.
    let teinte: (r: Double, g: Double, b: Double)?

    func appliquer(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let base = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

        let px = base.assumingMemoryBound(to: UInt8.self)
        let stride = ctx.bytesPerRow
        for y in 0..<h {
            for x in 0..<w {
                let i = y * stride + x * 4
                let a = Double(px[i + 3])
                guard a > 0 else { continue }
                let na = 255.0 * pow(a / 255.0, gammaAlpha)
                if let teinte {
                    // Couleur imposée, prémultipliée par la nouvelle opacité.
                    px[i]     = UInt8(teinte.r * na)
                    px[i + 1] = UInt8(teinte.g * na)
                    px[i + 2] = UInt8(teinte.b * na)
                } else {
                    // Le tampon est prémultiplié : on retrouve la couleur
                    // d'origine en divisant par l'ancienne opacité, puis on
                    // la remultiplie par la nouvelle.
                    let k = na / a
                    px[i]     = UInt8(min(255, Double(px[i]) * k))
                    px[i + 1] = UInt8(min(255, Double(px[i + 1]) * k))
                    px[i + 2] = UInt8(min(255, Double(px[i + 2]) * k))
                }
                px[i + 3] = UInt8(na)
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}

// MARK: - Tuiles agrandies au-delà du zoom disponible

/// `MKTileOverlay` avec « sur-zoom » : quand MapKit demande une tuile à
/// un niveau que la source ne sert pas, on charge la tuile parente au
/// dernier niveau disponible, on en découpe la portion correspondante
/// et on l'agrandit.
///
/// Sans ça, `maximumZ` fait simplement cesser les requêtes au-delà de la
/// limite — et la couche disparaît dès qu'on zoome. Le radar RainViewer
/// s'arrête au niveau 7, soit ~1 km par pixel : l'agrandir ne perd
/// aucune information, il n'y en a pas plus fine.
final class TuilesSurZoom: MKTileOverlay {

    private let zoomSource: Int
    private let traitement: TraitementTuile?

    /// Session réseau À NOUS, distincte de celle de MapKit.
    ///
    /// C'est le cœur du correctif. MapKit annule ses propres requêtes
    /// dès qu'une tuile sort de l'écran — normal pendant un zoom rapide.
    /// Mais quand la requête annulée est celle d'une tuile PARENTE, tous
    /// les enfants qui l'attendaient sont rendus `nil`… et MapKit met ce
    /// `nil` en cache : la tuile ne sera plus jamais redemandée, d'où un
    /// trou permanent. Diagnostiqué par traces : douze `nil` en 4 ms,
    /// bien trop rapide pour douze vrais aller-retours réseau.
    private let session = URLSession(configuration: .default)
    private var cache: [String: Data] = [:]
    private var attentes: [String: [(Data?) -> Void]] = [:]
    private let verrou = NSLock()

    init(urlTemplate: String, zoomSource: Int, traitement: TraitementTuile? = nil) {
        self.zoomSource = zoomSource
        self.traitement = traitement
        super.init(urlTemplate: urlTemplate)
    }

    override func loadTile(at path: MKTileOverlayPath, result brut: @escaping (Data?, Error?) -> Void) {
        // Le traitement s'applique au résultat quel que soit le chemin
        // (tuile directe ou fabriquée par sur-zoom).
        let result: (Data?, Error?) -> Void = { [traitement] data, error in
            guard let traitement, let data else { brut(data, error); return }
            brut(traitement.appliquer(data) ?? data, error)
        }
        guard path.z > zoomSource else {
            super.loadTile(at: path, result: result)
            return
        }

        // Chaque niveau de zoom divise une tuile en 4 : au niveau z, la
        // tuile (x, y) est un morceau de la tuile (x/2ᵈ, y/2ᵈ) du niveau
        // z − d.
        let facteur = 1 << (path.z - zoomSource)
        let parent = MKTileOverlayPath(x: path.x / facteur, y: path.y / facteur,
                                       z: zoomSource, contentScaleFactor: path.contentScaleFactor)

        chargerParente(parent) { data in
            guard let data,
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let source = CGImageSourceCreateImageAtIndex(src, 0, nil)
            else { result(nil, nil); return }

            // La portion : (x mod 2ᵈ, y mod 2ᵈ) désigne le sous-carré.
            let cote = CGFloat(source.width) / CGFloat(facteur)
            let portion = CGRect(x: CGFloat(path.x % facteur) * cote,
                                 y: CGFloat(path.y % facteur) * cote,
                                 width: cote, height: cote)
            guard let morceau = source.cropping(to: portion) else { result(nil, nil); return }

            // Agrandissement à 256 px. Interpolation basse : le radar est
            // une grille de mesures, la lisser donnerait de faux dégradés
            // entre deux cellules.
            let taille = 256
            guard let ctx = CGContext(data: nil, width: taille, height: taille,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { result(nil, nil); return }
            ctx.interpolationQuality = .low
            // Pas de retournement : `CGContext.draw` place la première
            // rangée de l'image en haut du rectangle, et `makeImage()`
            // la restitue dans le même ordre. Vérifié sur une vraie tuile
            // — avec un retournement, elle sortait à l'envers.
            ctx.draw(morceau, in: CGRect(x: 0, y: 0, width: taille, height: taille))

            guard let agrandi = ctx.makeImage() else { result(nil, nil); return }
            result(NSBitmapImageRep(cgImage: agrandi).representation(using: .png, properties: [:]), nil)
        }
    }

    /// Une seule requête par parente, quel que soit le nombre d'enfants
    /// qui l'attendent ; mise en cache ; deux nouvelles tentatives en cas
    /// d'échec réseau avant de renoncer.
    private func chargerParente(_ p: MKTileOverlayPath, completion: @escaping (Data?) -> Void) {
        let cle = "\(p.z)/\(p.x)/\(p.y)"
        verrou.lock()
        if let d = cache[cle] { verrou.unlock(); completion(d); return }
        if attentes[cle] != nil { attentes[cle]!.append(completion); verrou.unlock(); return }
        attentes[cle] = [completion]
        verrou.unlock()
        telecharger(url(forTilePath: p), cle: cle, essaisRestants: 2)
    }

    private func telecharger(_ url: URL, cle: String, essaisRestants: Int) {
        session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            if let data, !data.isEmpty {
                verrou.lock()
                cache[cle] = data
                let enAttente = attentes.removeValue(forKey: cle) ?? []
                verrou.unlock()
                enAttente.forEach { $0(data) }
            } else if essaisRestants > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                    self.telecharger(url, cle: cle, essaisRestants: essaisRestants - 1)
                }
            } else {
                verrou.lock()
                let enAttente = attentes.removeValue(forKey: cle) ?? []
                verrou.unlock()
                enAttente.forEach { $0(nil) }
            }
        }.resume()
    }
}

// MARK: - La carte MapKit (AppKit)

/// Le `Map` de SwiftUI ne sait pas superposer des tuiles : on descend
/// d'un étage vers `MKMapView`, qui le fait avec `MKTileOverlay`.
struct CarteMeteoView: NSViewRepresentable {
    let centre: CLLocationCoordinate2D
    let modeleURL: String?      // template avec {z}/{x}/{y}, nil = rien à afficher
    let opacite: Double
    let traitement: TraitementTuile?
    /// Niveau de zoom maximal que la source sait servir. Au-delà, MapKit
    /// agrandit lui-même les tuiles du dernier niveau disponible au lieu
    /// de demander des tuiles qui n'existent pas.
    let zoomMax: Int

    func makeNSView(context: Context) -> MKMapView {
        let carte = MKMapView()
        carte.delegate = context.coordinator
        carte.showsCompass = false
        carte.showsZoomControls = true
        // Carte sombre et discrète : c'est le radar qu'on veut lire, pas
        // les noms de rues.
        carte.appearance = NSAppearance(named: .darkAqua)
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        carte.preferredConfiguration = config
        // En dessous de ~15 km de distance, une cellule radar ferait plus
        // de 30 px de côté : ça n'apporte plus rien. On borne le zoom.
        carte.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 15_000)
        carte.setRegion(MKCoordinateRegion(center: centre,
                                           span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 3.5)),
                        animated: false)
        return carte
    }

    func updateNSView(_ carte: MKMapView, context: Context) {
        let coord = context.coordinator

        // Recentrer seulement si la ville a changé, pas à chaque tick
        // d'animation — sinon l'utilisateur ne peut plus se déplacer.
        if coord.dernierCentre == nil
            || abs(coord.dernierCentre!.latitude - centre.latitude) > 0.01
            || abs(coord.dernierCentre!.longitude - centre.longitude) > 0.01 {
            carte.setCenter(centre, animated: coord.dernierCentre != nil)
            coord.dernierCentre = centre
        }

        coord.opacite = opacite

        // Même URL = même couche = rien à faire. Sinon on remplace :
        // retirer l'ancienne tuile et poser la nouvelle est ce qui produit
        // l'animation image par image du radar.
        // Un changement de traitement à URL égale ne se produit pas (le
        // traitement dépend de la couche, comme l'URL) — inutile de le
        // comparer séparément.
        guard coord.dernierModele != modeleURL else {
            carte.renderer(for: coord.overlayCourant ?? MKTileOverlay(urlTemplate: nil))
                .flatMap { $0 as? MKTileOverlayRenderer }?.alpha = opacite
            return
        }
        coord.dernierModele = modeleURL
        if let ancien = coord.overlayCourant { carte.removeOverlay(ancien) }
        coord.overlayCourant = nil

        if let modeleURL {
            let tuiles = TuilesSurZoom(urlTemplate: modeleURL, zoomSource: zoomMax, traitement: traitement)
            tuiles.canReplaceMapContent = false
            tuiles.tileSize = CGSize(width: 256, height: 256)
            carte.addOverlay(tuiles, level: .aboveLabels)
            coord.overlayCourant = tuiles
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var overlayCourant: MKTileOverlay?
        var dernierModele: String?
        var dernierCentre: CLLocationCoordinate2D?
        var opacite: Double = 0.75

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tuiles = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKTileOverlayRenderer(tileOverlay: tuiles)
            r.alpha = opacite
            return r
        }
    }
}

// MARK: - L'onglet

struct CarteTabView: View {
    @ObservedObject var vm: WeatherViewModel

    @State private var couche: CoucheCarte = .radar
    @State private var centre: CLLocationCoordinate2D? = nil
    @State private var hoteRadar = ""
    @State private var images: [ImageRadar] = []
    @State private var indexImage = 0
    @State private var lecture = false
    @State private var opacite = 0.75

    /// L'animation : une image toutes les 0,6 s. Assez lent pour lire le
    /// déplacement, assez vite pour ne pas s'ennuyer sur 2 h de radar.
    private let horloge = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    private static let heure: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(spacing: 14) {
            entete
            ZStack(alignment: .bottom) {
                carte
                if couche == .radar { controleTemps }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(22)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.surface.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            barreCouches
        }
        .padding(.horizontal, 36).padding(.top, 28).padding(.bottom, 20)
        .task(id: vm.city) {
            if let c = await WeatherService.shared.coordonnees(city: vm.city) {
                centre = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
            }
            let r = await WeatherService.shared.imagesRadar()
            hoteRadar = r.hote
            images = r.images
            // On démarre sur la dernière MESURE, pas sur la prévision.
            indexImage = max(0, (images.lastIndex { !$0.estPrevision } ?? images.count - 1))
        }
        .onReceive(horloge) { _ in
            guard lecture, !images.isEmpty else { return }
            indexImage = (indexImage + 1) % images.count
        }
    }

    // MARK: En-tête

    private var entete: some View {
        VStack(spacing: 6) {
            Text("Carte").font(.largeTitle.bold()).foregroundColor(.texte)
            Text(couche.estMesure
                 ? "\(vm.city.capitalized) · radar mesuré, deux dernières heures"
                 : "\(vm.city.capitalized) · \(couche.titre.lowercased()), sortie de modèle OpenWeather")
                .font(.caption).foregroundColor(.texte.opacity(0.55))
        }
    }

    // MARK: Carte

    @ViewBuilder private var carte: some View {
        if let centre {
            CarteMeteoView(centre: centre, modeleURL: modeleURL, opacite: opacite,
                           traitement: couche.traitement,
                           zoomMax: couche == .radar ? 7 : 12)
        } else {
            ZStack {
                Color.surface.opacity(0.06)
                VStack(spacing: 10) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .texte))
                    Text("Localisation de \(vm.city.capitalized)…")
                        .font(.caption).foregroundColor(.texte.opacity(0.5))
                }
            }
        }
    }

    /// L'URL des tuiles pour la couche et l'instant courants.
    private var modeleURL: String? {
        if couche == .radar {
            guard !hoteRadar.isEmpty, images.indices.contains(indexImage) else { return nil }
            // /256/ = taille des tuiles, /4/ = palette « The Weather Channel »
            // (vert → jaune → rouge, la plus lisible pour repérer un orage),
            // /1_1 = lissage et neige activés.
            return "\(hoteRadar)\(images[indexImage].chemin)/256/{z}/{x}/{y}/4/1_1.png"
        }
        guard let l = couche.coucheOpenWeather else { return nil }
        return "\(Config.API.openWeatherTuiles)/\(l)/{z}/{x}/{y}.png?appid=\(Config.openWeatherAPIKey)"
    }

    // MARK: Curseur temporel (radar)

    private var controleTemps: some View {
        VStack(spacing: 8) {
            if images.isEmpty {
                Text("Radar indisponible pour le moment")
                    .font(.caption).foregroundColor(.texte.opacity(0.6))
            } else {
                let img = images[min(indexImage, images.count - 1)]
                HStack(spacing: 12) {
                    Button { lecture.toggle() } label: {
                        Image(systemName: lecture ? "pause.fill" : "play.fill")
                            .font(.title3).foregroundColor(.texte)
                            .frame(width: 30, height: 30)
                            .background(Color.surface.opacity(0.15)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lecture ? "Mettre en pause" : "Animer le radar")

                    // Le curseur parcourt les images : passé à gauche,
                    // prévision courte à droite quand elle existe.
                    Slider(value: Binding(
                        get: { Double(indexImage) },
                        set: { indexImage = Int($0.rounded()); lecture = false }
                    ), in: 0...Double(max(0, images.count - 1)), step: 1)
                    .accessibilityLabel("Instant du radar")

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Self.heure.string(from: img.date))
                            .font(.subheadline.bold().monospacedDigit()).foregroundColor(.texte)
                        Text(img.estPrevision ? "prévision" : "mesuré")
                            .font(.caption2).foregroundColor(img.estPrevision ? .orange : .green)
                    }
                    .frame(width: 58, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.texteInverse.opacity(0.25))
        .cornerRadius(16)
        .padding(14)
    }

    // MARK: Couches, opacité, légende

    private var barreCouches: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(CoucheCarte.allCases) { c in
                    Button {
                        withAnimation(.spring(duration: 0.3)) { couche = c; lecture = false }
                    } label: {
                        Label(c.titre, systemImage: c.icone)
                            .font(.caption.bold())
                            .foregroundColor(couche == c ? .texteInverse : .texte)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(couche == c ? Color.texte : Color.surface.opacity(0.12))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled").font(.caption).foregroundColor(.texte.opacity(0.5))
                    Slider(value: $opacite, in: 0.2...1).frame(width: 90)
                        .accessibilityLabel("Opacité de la couche")
                }
            }

            HStack(spacing: 14) {
                ForEach(Array(couche.legende.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(item.couleur).frame(width: 14, height: 10)
                        Text(item.texte).font(.caption2).foregroundColor(.texte.opacity(0.6))
                    }
                }
                Spacer()
                Text(couche.estMesure ? "Source : RainViewer (radar)" : "Source : OpenWeather (modèle)")
                    .font(.caption2).foregroundColor(.texte.opacity(0.4))
            }
        }
        .padding(14)
        .fondCarte().cornerRadius(18)
    }
}
