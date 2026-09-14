import SwiftUI
import MetalKit

// ╔══════════════════════════════════════════════════════════════════╗
// ║  CielMetal — la couche GPU sous le contenu                       ║
// ║  Un MTKView qui se redessine seul 60 fois par seconde, sans que  ║
// ║  SwiftUI ne rasterise quoi que ce soit : c'est la leçon de la    ║
// ║  preuve de concept « chaleur ». Le shader est dans Ciel.metal.   ║
// ╚══════════════════════════════════════════════════════════════════╝

/// Même disposition que `Uniformes` dans Ciel.metal. Les SIMD4 sont
/// alignés sur 16 octets des deux côtés, d'où l'ordre des champs.
struct UniformesCiel {
    var resolution: SIMD2<Float> = .zero
    var temps: Float = 0
    var condition: Int32 = 0
    var intensite: Float = 1
    var vent: Float = 0.25
    var elevation: Float = 0.7
    var soleil: SIMD2<Float> = [0.5, 0.06]
    var crepuscule: Float = 0
    var eclat: Float = 0.25
    var disque: Float = 2
    var encre: SIMD4<Float> = [1, 1, 1, 1]
    var haut: SIMD4<Float> = [0.38, 0.44, 0.58, 1]
    var bas: SIMD4<Float> = [0.18, 0.22, 0.34, 1]
}

/// Les conditions que le GPU sait rendre. Les autres restent au Canvas.
enum ConditionMetal: Int32 {
    case aucune = 0, pluie = 1, bruine = 2, brouillard = 3, neige = 4
    case degage = 5, nuit = 6, nuages = 7, orage = 8, averse = 9
    // Les régimes extrêmes (mêmes numéros dans Ciel.metal)
    case tornade = 10, tempete = 11, grele = 12, canicule = 13, grandFroid = 14
    case poussiere = 15, cyclone = 16, blizzard = 17, verglas = 18, deluge = 19

    /// Pluie et bruine partagent le rendu « pluie fine » (D) ; averse et
    /// orage le rendu « averse » (E). L'averse, c'est une pluie avec du
    /// débit : ≥ 4 mm/h, ou un code WMO d'averse.
    static func depuis(cle: String, estNuit: Bool, averse: Bool) -> ConditionMetal {
        switch cle {
        case "rain":    return averse ? .averse : .pluie
        case "drizzle": return .bruine
        case "fog":     return .brouillard
        case "snow":    return .neige
        case "clear":   return estNuit ? .nuit : .degage
        case "cloud":   return .nuages
        case "thunder": return .orage      // l'averse E plus les éclairs
        // Les régimes extrêmes, par leur clé de décor (RegimeExtreme.cle).
        // Jour ou nuit, c'est le shader qui tranche, avec l'élévation du soleil.
        case "tornado":  return .tornade
        case "storm":    return .tempete
        case "hail":     return .grele
        case "heat":     return .canicule
        case "cold":     return .grandFroid
        case "dust":     return .poussiere
        case "cyclone":  return .cyclone
        case "blizzard": return .blizzard
        case "sleet":    return .verglas
        case "deluge":   return .deluge
        default:        return .aucune
        }
    }
    /// Toutes les clés de décor de l'app : le GPU rend tout, le Canvas
    /// `WeatherBackground` a été supprimé.
    static let clesGerees: Set<String> = ["rain", "drizzle", "fog", "snow", "clear", "cloud", "thunder",
                                          "tornado", "storm", "hail", "heat", "cold", "dust",
                                          "cyclone", "blizzard", "sleet", "deluge"]
}

struct CielMetal: NSViewRepresentable {
    var haut: (r: Double, g: Double, b: Double)
    var bas: (r: Double, g: Double, b: Double)
    var condition: ConditionMetal
    var intensite: Float           // bruine 0,45 → averse 1
    var encreSombre: Bool          // thème clair de jour : particules sombres
    var vent: Float
    var soleil: SIMD2<Float>       // position du soleil dans l'écran (uv)
    var elevation: Float           // −1 → 1 ; ≤ 0, c'est la nuit (canicule et grand froid en ont besoin)
    var crepuscule: Float
    var eclat: Float               // éclat du soleil photographique, selon l'heure
    var anime: Bool                // faux : fenêtre inactive ou animations réduites

    /// Vrai si un GPU Metal répond — sinon ContentView garde le dégradé SwiftUI.
    static let disponible = MTLCreateSystemDefaultDevice() != nil

    func makeCoordinator() -> Coordinateur { Coordinateur() }

    func makeNSView(context: Context) -> MTKView {
        let vue = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        vue.colorPixelFormat = .bgra8Unorm
        vue.framebufferOnly = true
        vue.preferredFramesPerSecond = 60
        vue.isPaused = false
        vue.enableSetNeedsDisplay = false
        vue.layer?.isOpaque = true
        vue.delegate = context.coordinator
        context.coordinator.preparer(vue)
        return vue
    }

    func updateNSView(_ vue: MTKView, context: Context) {
        let c = context.coordinator
        c.cible.haut = [Float(haut.r), Float(haut.g), Float(haut.b), 1]
        c.cible.bas  = [Float(bas.r), Float(bas.g), Float(bas.b), 1]
        c.cible.encre = encreSombre ? [0.22, 0.26, 0.34, 1] : [1, 1, 1, 1]
        c.cible.condition = condition.rawValue
        c.cible.intensite = intensite
        c.cible.vent = vent
        c.cible.soleil = soleil
        c.cible.elevation = elevation
        c.cible.crepuscule = crepuscule
        c.cible.eclat = eclat
        // En pause, la dernière image reste affichée : un ciel figé, pas noir.
        if vue.isPaused != !anime {
            vue.isPaused = !anime
            if !anime { vue.enableSetNeedsDisplay = true; vue.needsDisplay = true }
            else { vue.enableSetNeedsDisplay = false }
        }
    }

    /// Le délégué du MTKView : il tient le pipeline et dessine chaque image.
    final class Coordinateur: NSObject, MTKViewDelegate {
        private var pipeline: MTLRenderPipelineState?
        private var file: MTLCommandQueue?
        private let debut = Date()
        /// Ce que SwiftUI demande, et ce qui est affiché : les couleurs
        /// glissent de l'un vers l'autre à chaque image (transition douce
        /// quand la condition change, comme l'ancien `.animation`).
        var cible = UniformesCiel()
        private var courant = UniformesCiel()

        func preparer(_ vue: MTKView) {
            guard let device = vue.device, let biblio = device.makeDefaultLibrary(),
                  let vs = biblio.makeFunction(name: "ciel_vertex"),
                  let fs = biblio.makeFunction(name: "ciel_fragment") else { return }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vs
            desc.fragmentFunction = fs
            desc.colorAttachments[0].pixelFormat = vue.colorPixelFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: desc)
            file = device.makeCommandQueue()
            courant = cible
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in vue: MTKView) {
            guard let pipeline, let file, let drawable = vue.currentDrawable,
                  let passe = vue.currentRenderPassDescriptor,
                  let commandes = file.makeCommandBuffer(),
                  let enc = commandes.makeRenderCommandEncoder(descriptor: passe) else { return }

            // Glissement des couleurs vers la cible (≈ 1 s), condition immédiate
            let k: Float = 0.04
            courant.haut += (cible.haut - courant.haut) * k
            courant.bas  += (cible.bas  - courant.bas)  * k
            courant.encre += (cible.encre - courant.encre) * k
            courant.condition = cible.condition
            courant.vent = cible.vent
            courant.intensite += (cible.intensite - courant.intensite) * k
            courant.soleil += (cible.soleil - courant.soleil) * k
            courant.elevation += (cible.elevation - courant.elevation) * k
            courant.crepuscule += (cible.crepuscule - courant.crepuscule) * k
            courant.eclat += (cible.eclat - courant.eclat) * k
            courant.resolution = [Float(vue.drawableSize.width), Float(vue.drawableSize.height)]
            // Sous 1 000 s : un Float n'a que ~7 chiffres significatifs
            courant.temps = Float(Date().timeIntervalSince(debut).truncatingRemainder(dividingBy: 1000))

            enc.setRenderPipelineState(pipeline)
            var u = courant
            enc.setFragmentBytes(&u, length: MemoryLayout<UniformesCiel>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            commandes.present(drawable)
            commandes.commit()
        }
    }
}
