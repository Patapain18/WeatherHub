import SwiftUI

// MARK: - Palette adaptative (mode clair / mode sombre)

// On étend `ShapeStyle` et non `Color`, exactement comme Apple le fait pour
// `.white` ou `.cyan`. Raison : certains modificateurs attendent une `Color`
// (`.foregroundColor`), d'autres un `ShapeStyle` (`.foregroundStyle`, `.fill`,
// `.background`, qui acceptent aussi dégradés et matériaux). Cette seule
// déclaration rend `.texte` valable dans les deux cas — et `Color.texte` aussi.
extension ShapeStyle where Self == Color {

    /// Texte et icônes d'interface.
    /// Blanc en mode sombre, presque noir en mode clair.
    /// La bascule ne se fait PAS en Swift : elle vient d'Assets.xcassets →
    /// « Texte », qui contient deux variantes. SwiftUI choisit la bonne selon
    /// l'environnement de la vue, donc aucune vue n'a besoin de savoir
    /// quel thème est actif.
    static var texte: Color { Color("Texte") }

    /// Fonds translucides : onglet actif, séparateurs, pistes de jauges.
    /// Toujours utilisée avec .opacity() — blanc en mode sombre (elle éclaircit
    /// ce qu'il y a dessous), noir en mode clair (elle l'assombrit).
    static var surface: Color { Color("Surface") }

    /// L'exact opposé de `texte` : pour les éléments en inversion vidéo
    /// (fond plein de la couleur du texte, texte de la couleur du fond),
    /// comme la puce de la ville active.
    static var texteInverse: Color { Color("TexteInverse") }
}

// MARK: - Icône selon le code WMO (Open-Meteo)

/// Codes WMO 4677 tels que les publie Open-Meteo.
/// 0 = ciel dégagé, 1–3 = nuages, 45/48 = brouillard, 51–67 = bruine et
/// pluie, 71–77 = neige, 80–82 = averses, 95–99 = orage.
func iconePourCodeWMO(_ code: Int, nuit: Bool = false) -> String {
    switch code {
    case 0:        return nuit ? "moon.stars" : "sun.max"
    case 1, 2:     return nuit ? "cloud.moon" : "cloud.sun"
    case 3:        return "cloud"
    case 45, 48:   return "cloud.fog"
    case 51...57:  return "cloud.drizzle"
    case 61...67:  return "cloud.rain"
    case 71...77:  return "snowflake"
    case 80...82:  return "cloud.heavyrain"
    case 85, 86:   return "cloud.snow"
    case 95...99:  return "cloud.bolt.rain"
    default:       return "cloud"
    }
}

/// Le mot qui va avec le code WMO, pour la barre latérale.
func libellePourCodeWMO(_ code: Int) -> String {
    switch code {
    case 0:        return "Ciel dégagé"
    case 1:        return "Plutôt dégagé"
    case 2:        return "Partiellement nuageux"
    case 3:        return "Couvert"
    case 45, 48:   return "Brouillard"
    case 51...57:  return "Bruine"
    case 61, 63:   return "Pluie"
    case 65:       return "Pluie forte"
    case 66, 67:   return "Pluie verglaçante"
    case 71, 73:   return "Neige"
    case 75, 77:   return "Neige forte"
    case 80, 81:   return "Averses"
    case 82:       return "Averses violentes"
    case 85, 86:   return "Averses de neige"
    case 95:       return "Orage"
    case 96, 99:   return "Orage de grêle"
    default:       return "Nuageux"
    }
}

/// Le mot français pour la condition OpenWeather (« Clouds » → « Nuageux »).
/// L'en-tête l'affichait en anglais, tel quel.
func libelleCondition(_ condition: String) -> String {
    switch condition.lowercased() {
    case "clear":        return "Ciel dégagé"
    case "clouds":       return "Nuageux"
    case "rain":         return "Pluie"
    case "drizzle":      return "Bruine"
    case "snow":         return "Neige"
    case "thunderstorm": return "Orage"
    case "mist", "fog":  return "Brouillard"
    case "haze":         return "Brume"
    case "smoke":        return "Fumée"
    case "dust", "sand": return "Poussière"
    case "ash":          return "Cendres"
    case "squall":       return "Rafales"
    case "tornado":      return "Tornade"
    case "":             return ""
    default:             return condition
    }
}

// MARK: - Shared icon color helpers (global functions utilisées par plusieurs vues)

func iconPrimaryColor(condition: String) -> Color {
    let c = condition.lowercased()
    if c.contains("clear")       { return .yellow }
    if c.contains("cloud")       { return .texte }
    if c.contains("rain") || c.contains("drizzle") { return .blue }
    if c.contains("snow")        { return .cyan }
    if c.contains("thunder")     { return .purple }
    if c.contains("fog") || c.contains("mist")     { return .gray }
    return .texte
}

func iconSecondaryColor(condition: String) -> Color {
    let c = condition.lowercased()
    if c.contains("clear")       { return .orange }
    if c.contains("cloud")       { return .gray }
    if c.contains("rain") || c.contains("drizzle") { return .cyan }
    if c.contains("snow")        { return .texte }
    if c.contains("thunder")     { return .yellow }
    return .gray
}


// MARK: - Fond des cartes

extension View {

    /// Fond des cartes météo.
    ///
    /// Le matériau est atténué pour laisser deviner le décor animé
    /// derrière, mais un voile est glissé dessous : sans lui, un nuage
    /// clair ou le soleil passant derrière une carte ferait chuter le
    /// contraste du texte.
    ///
    /// Le voile utilise `texteInverse`, donc il s'inverse avec le thème —
    /// sombre sous du texte blanc, clair sous du texte noir. Un voile
    /// noir fixe aurait dégradé le mode clair au lieu de l'aider.
    func fondCarte() -> some View {
        self
            .background(.ultraThinMaterial.opacity(0.58))
            .background(Color.texteInverse.opacity(0.18))
    }
}


// MARK: - Sens du défilement

/// Position verticale du haut du contenu d'une ScrollView, à l'écran.
/// Les PreferenceKey remontent la hiérarchie de vues : c'est ainsi qu'une
/// ScrollView enfant peut informer ContentView, sans lien direct.
///
/// La valeur est optionnelle, et ce n'est pas un détail : `reduce` combine
/// les préférences de TOUS les frères dans la hiérarchie, y compris ceux
/// qui n'ont pas de sonde. Avec un `CGFloat` et une valeur par défaut de 0,
/// la barre flottante — dernier enfant du ZStack — écrasait la vraie
/// position par 0 à chaque passage. Avec `nil`, on ne retient que les vues
/// qui ont réellement quelque chose à dire.
struct OffsetDefilementKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let n = nextValue() { value = n }
    }
}

/// À poser en PREMIER enfant d'une ScrollView. Hauteur nulle, invisible :
/// elle ne fait que publier sa position. Quand on fait défiler vers le
/// bas, le contenu monte et cette position diminue — c'est le signal.
struct SondeDefilement: View {
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: OffsetDefilementKey.self,
                                   value: geo.frame(in: .global).minY)
        }
        .frame(height: 0)
    }
}

// MARK: - Typographie

/// « -2° » devient « −2° » : le trait d'union est trop court pour un
/// signe moins. Ne touche qu'un tiret suivi d'un chiffre — les mots
/// composés gardent le leur.
func typoMoins(_ s: String) -> String {
    s.replacingOccurrences(of: "-(?=[0-9])", with: "−", options: .regularExpression)
}

