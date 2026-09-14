import SwiftUI

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  WeatherBackground — Apple Weather-inspired cinematic renderer     ║
// ║  Multi-layer parallax, volumetric light, atmospheric scattering,   ║
// ║  organic noise, depth-of-field simulation, 60fps Canvas            ║
// ╚══════════════════════════════════════════════════════════════════════╝

struct WeatherBackground: View {
    let condition: String
    /// Où en est le soleil : place l'astre et décide du décor nocturne.
    let phase: PhaseSolaire

    @Environment(\.colorScheme) private var schemaCouleur

    /// Couleur des particules — flocons, gouttes, traînées de nuages.
    ///
    /// Elles étaient blanches en dur : parfaites sur un ciel de nuit,
    /// invisibles sur le ciel pâle du mode clair. En pleine nuit le fond
    /// reste sombre quel que soit le thème, donc on garde le blanc.
    private var encre: Color {
        (schemaCouleur == .light && !phase.estNuit)
            ? Color(red: 0.22, green: 0.26, blue: 0.34)
            : .white
    }

    /// `.inactive` quand l'app passe en arrière-plan. Inutile d'animer
    /// un décor que personne ne regarde.
    @Environment(\.controlActiveState) private var etatFenetre

    private var key: String {
        let cleBrute = keyBrute
        // Pluie, bruine, brouillard, neige, ciel dégagé, nuages et les dix
        // régimes extrêmes : rendus par CielMetal sur le GPU. Le Canvas ne
        // doit pas les dessiner une seconde fois — il ne garde que les
        // éclairs de l'orage. Les enums FX ci-dessous restent le repli
        // d'un Mac sans Metal.
        return (CielMetal.disponible && ConditionMetal.clesGerees.contains(cleBrute)) ? "default" : cleBrute
    }

    private var keyBrute: String {
        let c = condition.lowercased()
        // Les régimes extrêmes arrivent déjà sous forme de clé (`conditionDecor`),
        // mais on reconnaît aussi les mots d'OpenWeather au cas où.
        if c == "tornado" || c.contains("tornad")      { return "tornado" }
        if c == "storm"   || c.contains("squall")      { return "storm" }
        if c == "hail"    || c.contains("hail")        { return "hail" }
        if c == "heat"                                 { return "heat" }
        if c == "cold"                                 { return "cold" }
        if c == "dust" || c.contains("dust") || c.contains("sand") || c.contains("ash") { return "dust" }
        if c == "cyclone" || c.contains("hurricane") || c.contains("typhoon") { return "cyclone" }
        if c == "blizzard" || c.contains("blizzard")   { return "blizzard" }
        if c == "sleet"   || c.contains("sleet") || c.contains("freezing") { return "sleet" }
        if c == "deluge"                               { return "deluge" }
        if c.contains("thunder")                       { return "thunder" }
        if c.contains("rain")                          { return "rain" }
        if c.contains("drizzle")                       { return "drizzle" }
        if c.contains("snow")                          { return "snow" }
        if c.contains("clear")                         { return "clear" }
        if c.contains("fog") || c.contains("mist")     { return "fog" }
        if c.contains("cloud")                         { return "cloud" }
        return "default"
    }

    var body: some View {
        Group {
            // Rien à dessiner, ou app en arrière-plan : on ne monte même pas
            // le TimelineView. Pas de vue = pas d'horloge = zéro redraw.
            if key == "default" || etatFenetre == .inactive {
                Color.clear
            } else {
                animationDeFond
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var animationDeFond: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                switch key {
                case "rain":    RainFX.draw(ctx: ctx, s: size, t: t, heavy: true, encre: encre)
                case "drizzle": RainFX.draw(ctx: ctx, s: size, t: t, heavy: false, encre: encre)
                case "thunder": ThunderFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "snow":    SnowFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "clear":
                    // Ciel dégagé la nuit : étoiles et lune, pas un soleil.
                    if phase.estNuit { NuitFX.draw(ctx: ctx, s: size, t: t, phase: phase) }
                    else             { ClearFX.draw(ctx: ctx, s: size, t: t, phase: phase) }
                case "fog":     FogFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "cloud":   CloudFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                // Régimes extrêmes
                case "tornado": TornadeFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "storm":   TempeteFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "hail":    GreleFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "heat":    CaniculeFX.draw(ctx: ctx, s: size, t: t, phase: phase)
                case "cold":    GrandFroidFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "dust":    PoussiereFX.draw(ctx: ctx, s: size, t: t)
                case "cyclone": CycloneFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "blizzard": BlizzardFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "sleet":   VerglasFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                case "deluge":  DelugeFX.draw(ctx: ctx, s: size, t: t, encre: encre)
                default:        break
                }
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — NOISE & MATH ENGINE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private func H(_ n: Double) -> Double {
    let v = sin(n) * 43758.5453123
    return v - floor(v)
}
private func H2(_ x: Double, _ y: Double) -> Double { H(x * 127.1 + y * 311.7) }

// Value noise 1D — smooth organic motion
private func vnoise(_ x: Double) -> Double {
    let i = floor(x)
    let f = x - i
    let u = f * f * (3 - 2 * f)  // smoothstep
    return H(i) * (1 - u) + H(i + 1) * u
}
// FBM (fractal brownian motion) — layered noise for natural turbulence
private func fbm(_ x: Double, octaves: Int = 4) -> Double {
    var v = 0.0, amp = 0.5, freq = 1.0
    for _ in 0..<octaves { v += vnoise(x * freq) * amp; amp *= 0.5; freq *= 2.0 }
    return v
}
private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — SHARED GEOMETRY
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Goutte larme bezier haute-fidélité
private func dropPath(cx: Double, cy: Double, w: Double, h: Double, angle: Double) -> Path {
    Path { p in
        let ca = cos(angle), sa = sin(angle)
        func r(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: cx+dx*ca-dy*sa, y: cy+dx*sa+dy*ca) }
        p.move(to: r(0, h*0.5))
        p.addCurve(to: r(0, -h*0.5), control1: r(w*0.62, h*0.22), control2: r(w*0.56, -h*0.18))
        p.addCurve(to: r(0, h*0.5), control1: r(-w*0.56, -h*0.18), control2: r(-w*0.62, h*0.22))
    }
}

// Flocon cristallin 6 branches — 3 niveaux de ramification
private func crystalPath(cx: Double, cy: Double, r: Double, seed: Double) -> Path {
    Path { p in
        for arm in 0..<6 {
            let ba = Double(arm) * (.pi / 3.0) + seed * 0.5
            p.move(to: CGPoint(x: cx, y: cy))
            p.addLine(to: CGPoint(x: cx + cos(ba)*r, y: cy + sin(ba)*r))
            for (frac, bLen) in [(0.25, r*0.35), (0.48, r*0.28), (0.70, r*0.20)] {
                let bx = cx + cos(ba)*r*frac, by = cy + sin(ba)*r*frac
                for side in [-1.0, 1.0] {
                    let sub = ba + side * (.pi / 3.0)
                    p.move(to: CGPoint(x: bx, y: by))
                    p.addLine(to: CGPoint(x: bx + cos(sub)*bLen, y: by + sin(sub)*bLen))
                    // Sous-sous-branches pour les plus grands
                    if frac < 0.3 && r > 7 {
                        let sbx = bx + cos(sub)*bLen*0.6, sby = by + sin(sub)*bLen*0.6
                        for s2 in [-1.0, 1.0] {
                            let sub2 = sub + s2 * (.pi / 3.0)
                            p.move(to: CGPoint(x: sbx, y: sby))
                            p.addLine(to: CGPoint(x: sbx + cos(sub2)*bLen*0.4, y: sby + sin(sub2)*bLen*0.4))
                        }
                    }
                }
            }
            if arm == 0 {
                let hr = r * 0.13
                p.move(to: CGPoint(x: cx + hr, y: cy))
                for k in 1...6 { let a = Double(k)*(.pi/3); p.addLine(to: CGPoint(x: cx+cos(a)*hr, y: cy+sin(a)*hr)) }
            }
        }
    }
}

// Nuage volumique organique avec bruit
private func cloudShape(cx: Double, cy: Double, scale: Double, seed: Double) -> Path {
    Path { p in
        let n = 18
        var pts: [(Double, Double)] = []
        for i in 0..<n {
            let a = Double(i) / Double(n) * (.pi * 2)
            let noise = H2(seed + Double(i), a) * 0.45 + H2(seed + Double(i)*2.3, a*1.7) * 0.25
                + H2(seed + Double(i)*4.1, a*3.1) * 0.10
            let r = scale * (0.60 + noise)
            let flat = max(0, sin(a)) * scale * 0.32
            pts.append((cx + cos(a)*r, cy + sin(a)*r - flat))
        }
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for i in 0..<n {
            let nx = (i+1)%n, pv = (i-1+n)%n, nn = (i+2)%n
            let c = pts[i], next = pts[nx]
            let cp1 = (c.0 + (next.0 - pts[pv].0)*0.25, c.1 + (next.1 - pts[pv].1)*0.25)
            let cp2 = (next.0 - (pts[nn].0 - c.0)*0.25, next.1 - (pts[nn].1 - c.1)*0.25)
            p.addCurve(to: CGPoint(x: next.0, y: next.1),
                       control1: CGPoint(x: cp1.0, y: cp1.1), control2: CGPoint(x: cp2.0, y: cp2.1))
        }
        p.closeSubpath()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — ☀️ CLEAR SKY
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — 🌙 NUIT CLAIRE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum NuitFX {

    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, phase: PhaseSolaire) {
        let w = s.width, h = s.height

        // Les étoiles n'apparaissent pas d'un coup au coucher : elles
        // émergent à mesure que le ciel s'assombrit.
        let obscurite = min(1.0, -phase.elevation / 0.55)
        guard obscurite > 0.02 else { return }

        // ── Voie lactée : une bande diffuse en diagonale ──
        for i in 0..<5 {
            let decalage = Double(i) - 2
            var bande = Path()
            var x = -60.0
            bande.move(to: CGPoint(x: x, y: h * 0.12 + decalage * 26))
            while x <= w + 60 {
                let y = h * 0.12 + decalage * 26 + x * 0.34 + fbm(x * 0.004 + Double(i)) * 22
                bande.addLine(to: CGPoint(x: x, y: y)); x += 14
            }
            bande.addLine(to: CGPoint(x: w + 60, y: h + 200))
            bande.addLine(to: CGPoint(x: -60, y: h + 200)); bande.closeSubpath()
            ctx.fill(bande, with: .color(.white.opacity(0.008 * obscurite)))
        }

        // ── Étoiles ──
        // Positions tirées d'un bruit déterministe : elles ne sautillent
        // pas d'une image à l'autre, seul leur éclat varie.
        for i in 0..<150 {
            let seed = Double(i) * 7.31
            let sx = H(seed) * w
            let sy = H(seed + 1) * h * 0.82
            let taille = 0.5 + H(seed + 2) * 1.5

            // Scintillement : deux sinusoïdes de périodes différentes,
            // pour que le clignotement ne soit pas régulier.
            let scintille = 0.55
                + sin(t * (0.6 + H(seed + 3) * 1.8) + seed) * 0.30
                + sin(t * (0.23 + H(seed + 4) * 0.5) + seed * 2) * 0.15
            let eclat = max(0, scintille) * obscurite * (0.35 + H(seed + 5) * 0.65)

            // Quelques étoiles tirent vers le bleu ou l'orangé, comme
            // les vraies — un champ uniformément blanc fait synthétique.
            let teinte = H(seed + 6)
            let couleur = teinte > 0.85 ? Color(red: 0.75, green: 0.83, blue: 1.0)
                        : teinte < 0.12 ? Color(red: 1.0, green: 0.87, blue: 0.72)
                        : Color.white

            ctx.fill(Path(ellipseIn: CGRect(x: sx - taille, y: sy - taille,
                                            width: taille * 2, height: taille * 2)),
                     with: .color(couleur.opacity(eclat)))

            // Halo et croix de diffraction sur les plus brillantes
            if taille > 1.5 {
                ctx.fill(Path(ellipseIn: CGRect(x: sx - taille * 3, y: sy - taille * 3,
                                                width: taille * 6, height: taille * 6)),
                         with: .color(couleur.opacity(eclat * 0.10)))
                var croix = Path()
                croix.move(to: CGPoint(x: sx - taille * 4, y: sy))
                croix.addLine(to: CGPoint(x: sx + taille * 4, y: sy))
                croix.move(to: CGPoint(x: sx, y: sy - taille * 4))
                croix.addLine(to: CGPoint(x: sx, y: sy + taille * 4))
                ctx.stroke(croix, with: .color(couleur.opacity(eclat * 0.22)),
                           style: StrokeStyle(lineWidth: 0.6))
            }
        }

        // ── Étoile filante, rare ──
        // Un cycle de 23 s dont seule la première seconde est visible :
        // elle surprend au lieu de tourner en boucle.
        let cycle = fmod(t, 23.0)
        if cycle < 1.0 {
            let avance = cycle
            let dx = w * 0.30, dy = h * 0.16
            let ox = w * 0.15 + dx * avance, oy = h * 0.10 + dy * avance
            let visible = sin(avance * .pi)
            var trainee = Path()
            trainee.move(to: CGPoint(x: ox, y: oy))
            trainee.addLine(to: CGPoint(x: ox - dx * 0.14, y: oy - dy * 0.14))
            ctx.stroke(trainee, with: .color(.white.opacity(0.55 * visible * obscurite)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }

        // ── Lune ──
        let lx = w * 0.76, ly = h * 0.16
        let r = 30.0
        for i in 0..<5 {   // halo diffus
            let hr = r * (1.6 + Double(i) * 0.75)
            ctx.fill(Path(ellipseIn: CGRect(x: lx - hr, y: ly - hr, width: hr * 2, height: hr * 2)),
                     with: .color(Color(red: 0.85, green: 0.90, blue: 1.0)
                        .opacity(0.030 * obscurite / Double(i + 1))))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: lx - r, y: ly - r, width: r * 2, height: r * 2)),
                 with: .color(Color(red: 0.96, green: 0.96, blue: 0.90).opacity(0.92 * obscurite)))

        // Mers lunaires : trois taches sombres, sinon le disque fait plat.
        let meres: [(Double, Double, Double)] = [(-8, -7, 7), (6, 4, 9), (-3, 10, 5)]
        for (mx, my, mr) in meres {
            ctx.fill(Path(ellipseIn: CGRect(x: lx + mx - mr, y: ly + my - mr,
                                            width: mr * 2, height: mr * 2)),
                     with: .color(Color(red: 0.78, green: 0.79, blue: 0.76).opacity(0.35 * obscurite)))
        }
    }
}

private enum ClearFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, phase: PhaseSolaire) {
        let w = s.width, h = s.height

        // Le soleil traverse le ciel d'est en ouest et monte d'autant plus
        // haut qu'on approche de midi. Avant, il était figé à y = −40,
        // c'est-à-dire toujours coupé par le haut de la fenêtre.
        let sunX = w * (0.12 + phase.progression * 0.76)
        let sunY = h * (0.80 - phase.elevation * 0.74)

        // ── 1. Atmospheric scattering (dégradé radial depuis le soleil) ──
        for i in 0..<5 {
            let r = 250.0 + Double(i) * 80
            let op = 0.012 - Double(i) * 0.002
            let pulse = 1.0 + sin(t * 0.08 + Double(i) * 0.5) * 0.02
            ctx.fill(Path(ellipseIn: CGRect(x: sunX - r*pulse, y: sunY - r*pulse*0.8,
                                             width: r*2*pulse, height: r*1.6*pulse)),
                     with: .color(Color(red: 1, green: 0.95, blue: 0.75).opacity(op)))
        }

        // ── 2. Caustiques dansantes (réseau de lumière réfractée) ──
        for row in 0..<12 {
            for col in 0..<16 {
                let bx = w * Double(col) / 15.0, by = h * Double(row) / 11.0
                let phase = Double(col) * 0.67 + Double(row) * 1.13
                let dx = sin(t * 0.50 + phase) * 22 + sin(t * 0.28 + phase * 2.1) * 10
                let dy = cos(t * 0.42 + phase * 0.9) * 16 + cos(t * 0.22 + phase * 1.7) * 7
                let cr = 2.0 + sin(t * 0.75 + phase) * 2.2
                let stretch = 1.0 + sin(t * 0.33 + Double(col) * 0.8) * 0.55
                let brightness = 0.018 + sin(t * 0.55 + phase * 0.7) * 0.010
                ctx.fill(Path(ellipseIn: CGRect(x: bx+dx-cr*stretch, y: by+dy-cr/stretch,
                                                 width: cr*stretch*2, height: cr/stretch*2)),
                         with: .color(Color(red: 1, green: 0.97, blue: 0.80).opacity(brightness)))
            }
        }

        // ── 3. Heat shimmer (ondulations de chaleur) ──
        for i in 0..<8 {
            let yy = h * 0.55 + Double(i) * 25
            var path = Path()
            path.move(to: CGPoint(x: -10, y: yy))
            var x = 0.0
            while x <= w + 10 {
                let dy = sin(x * 0.018 + t * 1.8 + Double(i) * 0.7) * 2.5
                    + sin(x * 0.045 + t * 2.5) * 1.0
                path.addLine(to: CGPoint(x: x, y: yy + dy))
                x += 5
            }
            ctx.stroke(path, with: .color(Color(red: 1, green: 0.96, blue: 0.85).opacity(0.010)),
                       style: StrokeStyle(lineWidth: 1.8 + sin(t * 0.4 + Double(i)) * 0.8))
        }

        // ── 4. God rays — faisceaux volumétriques trapézoïdaux ──
        for i in 0..<13 {
            let baseA = Double(i) / 13.0 * (.pi * 0.85) + (.pi * 0.08)
            let spread = 0.025 + sin(t * 0.13 + Double(i) * 0.5) * 0.010
            let turbulence = fbm(t * 0.1 + Double(i) * 3.7)
            let pulse = 0.50 + turbulence * 0.35
            let rayLen = h * 2.0 * pulse
            let baseOp = (0.016 + sin(t * 0.18 + Double(i) * 0.95) * 0.008) * pulse

            for sub in 0..<3 {
                let sa = baseA + Double(sub - 1) * spread
                let ox = sunX + cos(baseA) * 38, oy = sunY + sin(baseA) * 38
                let ex = ox + cos(sa) * rayLen, ey = oy + sin(sa) * rayLen
                let curveX = sin(t * 0.10 + Double(i)) * 28
                let curveY = cos(t * 0.08) * 18
                let cpx = ox + cos(sa) * rayLen * 0.5 + curveX
                let cpy = oy + sin(sa) * rayLen * 0.5 + curveY
                let tipW = sub == 1 ? 22.0 : 13.0

                var ray = Path()
                ray.move(to: CGPoint(x: ox - sin(sa)*3, y: oy + cos(sa)*3))
                ray.addLine(to: CGPoint(x: ox + sin(sa)*3, y: oy - cos(sa)*3))
                ray.addQuadCurve(to: CGPoint(x: ex + sin(sa)*tipW, y: ey - cos(sa)*tipW),
                                  control: CGPoint(x: cpx + sin(sa)*tipW, y: cpy - cos(sa)*tipW))
                ray.addLine(to: CGPoint(x: ex - sin(sa)*tipW, y: ey + cos(sa)*tipW))
                ray.addQuadCurve(to: CGPoint(x: ox - sin(sa)*3, y: oy + cos(sa)*3),
                                  control: CGPoint(x: cpx - sin(sa)*3, y: cpy + cos(sa)*3))
                ray.closeSubpath()
                ctx.fill(ray, with: .color(Color(red: 1, green: 0.91, blue: 0.56).opacity(baseOp * (sub == 1 ? 1.5 : 0.55))))
            }
        }

        // ── 5. Halo solaire (dégradé continu) ──
        //
        // C'étaient cinq ellipses opaques empilées. Chaque bord créait une
        // marche de luminosité que l'œil accentue (bandes de Mach), d'où
        // les anneaux concentriques bien visibles autour du soleil.
        // Un vrai dégradé radial supprime les marches : la lumière décroît
        // sans discontinuité, comme une vraie diffusion atmosphérique.
        // Atténué de 40 % : à midi le soleil est en haut au centre, pile
        // sous le champ de recherche, qu'il rendait illisible en thème clair.
        let att = 0.6
        let rHalo = 340.0 * (1.0 + sin(t * 0.35) * 0.03)
        let halo = Gradient(stops: [
            .init(color: Color(red: 1, green: 0.97, blue: 0.82).opacity(0.30 * att), location: 0.00),
            .init(color: Color(red: 1, green: 0.92, blue: 0.64).opacity(0.13 * att), location: 0.16),
            .init(color: Color(red: 1, green: 0.87, blue: 0.52).opacity(0.05 * att), location: 0.40),
            .init(color: Color(red: 1, green: 0.84, blue: 0.48).opacity(0.00), location: 1.00),
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: sunX - rHalo, y: sunY - rHalo * 0.9,
                                        width: rHalo * 2, height: rHalo * 1.8)),
                 with: .radialGradient(halo, center: CGPoint(x: sunX, y: sunY),
                                       startRadius: 0, endRadius: rHalo))

        // ── 6. Disque solaire + couronne dynamique ──
        let sr = 52.0 + sin(t * 0.35) * 2.8

        // Couronne irrégulière avec bruit
        var corona = Path()
        let cN = 48
        for k in 0..<cN {
            let a = Double(k) / Double(cN) * (.pi * 2) + t * 0.15
            let noiseVal = sin(Double(k)*2.9 + t*0.8)*5 + sin(Double(k)*6.3 + t*1.3)*3 + sin(Double(k)*11.7 + t*2.1)*1.5
            let cr = sr + 12 + noiseVal
            let pt = CGPoint(x: sunX + cos(a)*cr, y: sunY + sin(a)*cr)
            k == 0 ? corona.move(to: pt) : corona.addLine(to: pt)
        }
        corona.closeSubpath()
        ctx.fill(corona, with: .color(Color(red: 1, green: 0.80, blue: 0.25).opacity(0.16 * att)))

        // Anneau chaud
        ctx.fill(Path(ellipseIn: CGRect(x: sunX-sr*1.12, y: sunY-sr*1.12, width: sr*2.24, height: sr*2.24)),
                 with: .color(Color(red: 1, green: 0.73, blue: 0.22).opacity(0.22 * att)))
        // Disque principal
        ctx.fill(Path(ellipseIn: CGRect(x: sunX-sr, y: sunY-sr, width: sr*2, height: sr*2)),
                 with: .color(Color(red: 1, green: 0.95, blue: 0.68).opacity(0.88 * att)))
        // Noyau surexposé
        ctx.fill(Path(ellipseIn: CGRect(x: sunX-sr*0.55, y: sunY-sr*0.55, width: sr*1.1, height: sr*1.1)),
                 with: .color(Color(red: 1, green: 0.98, blue: 0.88).opacity(0.35 * att)))
        // Spéculaire
        ctx.fill(Path(ellipseIn: CGRect(x: sunX-sr*0.35, y: sunY-sr*0.50, width: sr*0.38, height: sr*0.20)),
                 with: .color(.white.opacity(0.70 * att)))

        // ── 7. Lens flares anamorphiques ──
        let flarePoints: [(Double, Double, Double, Double)] = [
            (sunX, sunY, 12, 0.45), (sunX-100, sunY+80, 7, 0.22), (sunX-195, sunY+155, 9, 0.15),
            (sunX-280, sunY+220, 6, 0.09), (sunX+55, sunY+35, 5, 0.10), (sunX-50, sunY+45, 4, 0.08)
        ]
        for (fx, fy, fr, fop) in flarePoints {
            let p = 0.72 + sin(t * 0.60 + fx * 0.008) * 0.28
            // Disque flare anamorphique (étiré horizontalement)
            ctx.fill(Path(ellipseIn: CGRect(x: fx-fr*p*1.4, y: fy-fr*0.45*p, width: fr*2.8*p, height: fr*0.9*p)),
                     with: .color(Color(red: 0.93, green: 0.97, blue: 1).opacity(fop * p)))
            // Raies de diffraction
            let fl = fr * 4.0 * p
            ctx.stroke(Path { pa in pa.move(to: CGPoint(x: fx-fl, y: fy)); pa.addLine(to: CGPoint(x: fx+fl, y: fy)) },
                       with: .color(.white.opacity(fop * 0.22 * p)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
            ctx.stroke(Path { pa in pa.move(to: CGPoint(x: fx, y: fy-fl*0.5)); pa.addLine(to: CGPoint(x: fx, y: fy+fl*0.5)) },
                       with: .color(.white.opacity(fop * 0.12 * p)), style: StrokeStyle(lineWidth: 0.4, lineCap: .round))
        }

        // ── 8. Poussières dorées dans la lumière ──
        for i in 0..<20 {
            let seed = Double(i) * 137.508
            let baseX = H(seed) * w, baseY = H(seed + 1) * h * 0.4
            let sx = baseX + sin(t * 0.15 + seed) * 30 + sin(t * 0.07 + seed * 2) * 15
            let sy = baseY + cos(t * 0.10 + seed * 1.3) * 20
            let radius = 1.2 + sin(t * 0.8 + seed) * 1.2
            let twinkle = 0.035 + sin(t * 1.5 + seed * 3) * 0.025
            // Étoile 4 branches scintillante
            var star = Path()
            for k in 0..<8 {
                let a = Double(k) / 8.0 * (.pi * 2) + t * 0.25 + seed
                let rr = k % 2 == 0 ? radius : radius * 0.28
                let pt = CGPoint(x: sx + cos(a)*rr, y: sy + sin(a)*rr)
                k == 0 ? star.move(to: pt) : star.addLine(to: pt)
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(Color(red: 1, green: 0.97, blue: 0.82).opacity(twinkle)))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — 🌧 RAIN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum RainFX {
    // Configuration par couche de profondeur
    struct Layer { let count: Int; let speedMul: Double; let sizeMul: Double; let opMul: Double; let blurMul: Double }
    static let layers = [
        Layer(count: 50,  speedMul: 0.45, sizeMul: 0.40, opMul: 0.30, blurMul: 0.4),  // très loin (brumeux)
        Layer(count: 80,  speedMul: 0.70, sizeMul: 0.65, opMul: 0.55, blurMul: 0.7),  // moyen
        Layer(count: 90,  speedMul: 1.00, sizeMul: 1.00, opMul: 1.00, blurMul: 1.0),  // proche
        Layer(count: 35,  speedMul: 1.35, sizeMul: 1.40, opMul: 0.45, blurMul: 1.3),  // très proche (bokeh)
    ]

    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, heavy: Bool, encre: Color) {
        let w = s.width, h = s.height
        // Vent dynamique (varie dans le temps)
        let windStrength = sin(t * 0.12) * 0.05 + sin(t * 0.04) * 0.03
        let baseAngle = 0.20 + windStrength

        // ── Brume atmosphérique multicouche ──
        for i in 0..<6 {
            let yy = Double(i) * h * 0.20 - 20
            let drift = sin(t * 0.035 + Double(i) * 1.5) * 50 + cos(t * 0.02 + Double(i) * 0.8) * 20
            let thickness = 55.0 + sin(Double(i) * 0.7) * 15
            let op = heavy ? (0.022 - Double(i) * 0.002) : (0.012 - Double(i) * 0.001)
            var mist = Path()
            mist.move(to: CGPoint(x: -80 + drift, y: yy - thickness))
            var x = -80.0 + drift
            while x <= w + 80 + drift {
                let yOff = fbm(x * 0.005 + t * 0.03 + Double(i)) * 20
                mist.addLine(to: CGPoint(x: x, y: yy - thickness + yOff))
                x += 12
            }
            mist.addLine(to: CGPoint(x: w + 80 + drift, y: yy + thickness))
            x = w + 80 + drift
            while x >= -80 + drift {
                let yOff = fbm(x * 0.006 + t * 0.025 + Double(i) + 50) * 15
                mist.addLine(to: CGPoint(x: x, y: yy + thickness + yOff))
                x -= 12
            }
            mist.closeSubpath()
            ctx.fill(mist, with: .color(Color(red: 0.50, green: 0.62, blue: 0.78).opacity(op)))
        }

        // ── Gouttes par couche de profondeur ──
        let globalMul = heavy ? 1.0 : 0.55
        for (li, layer) in layers.enumerated() {
            let cnt = heavy ? layer.count : max(10, layer.count / 2)
            for i in 0..<cnt {
                let seed = Double(li * 10000 + i) * 1013 + 7
                let spd = (heavy ? 540.0 : 330.0) * layer.speedMul
                let windDrift = sin(t * 0.22 + H(seed) * 6.28) * 3 * layer.speedMul
                let x = fmod(seed * 0.00129 * w + t * spd * 0.14 + windDrift, w + 60) - 30
                let y = fmod(seed * 0.00263 * h + t * spd, h + 50) - 25

                let dropW = (0.8 + H(seed) * 1.2) * layer.sizeMul * globalMul
                let dropH = (10.0 + H(seed + 2) * 18) * layer.sizeMul * globalMul
                let op = (0.12 + H(seed + 3) * 0.20) * layer.opMul * globalMul

                // Corps de la goutte
                let drop = dropPath(cx: x, cy: y + dropH * 0.3, w: dropW, h: dropH, angle: baseAngle)
                let dropColor = Color(red: 0.58 + layer.blurMul * 0.08,
                                      green: 0.78 + layer.blurMul * 0.06,
                                      blue: 1.0)
                ctx.fill(drop, with: .color(dropColor.opacity(op)))

                // Motion blur (traîne)
                if dropH > 7 * layer.sizeMul {
                    let trailLen = dropH * (1.2 + layer.speedMul * 0.5)
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: x - sin(baseAngle)*trailLen, y: y - cos(baseAngle)*trailLen))
                        p.addLine(to: CGPoint(x: x, y: y))
                    }, with: .color(encre.opacity(op * 0.20)),
                       style: StrokeStyle(lineWidth: dropW * 0.45, lineCap: .round))
                }

                // Reflet spéculaire (grosses gouttes proches)
                if dropH > 14 * layer.sizeMul && li >= 2 {
                    ctx.fill(Path(ellipseIn: CGRect(x: x + dropW*0.25 - 0.7, y: y - dropH*0.12 - 0.5,
                                                     width: 1.4, height: 1.0)),
                             with: .color(encre.opacity(op * 0.55)))
                }

                // ── Éclaboussures au sol ──
                if li >= 1 && y > h - 60, y < h - 2 {
                    let age = clamp01(1.0 - (h - y) / 58.0)
                    let splR = (3.0 + age * 8) * layer.sizeMul
                    // Anneau principal
                    ctx.stroke(Path(ellipseIn: CGRect(x: x-splR*1.35, y: h-10-splR*0.30,
                                                       width: splR*2.7, height: splR*0.60)),
                               with: .color(encre.opacity(age * 0.13 * layer.opMul)),
                               style: StrokeStyle(lineWidth: 0.8))
                    // Onde secondaire
                    ctx.stroke(Path(ellipseIn: CGRect(x: x-splR*2.0, y: h-10-splR*0.14,
                                                       width: splR*4.0, height: splR*0.30)),
                               with: .color(encre.opacity(age * 0.05 * layer.opMul)),
                               style: StrokeStyle(lineWidth: 0.4))
                    // Gouttelettes projetées (couronne)
                    if li >= 2 {
                        for j in 0..<6 {
                            let pa = Double(j) * (.pi / 3.0) + seed * 0.2
                            let dist = splR * (0.6 + H(seed + Double(j)) * 0.9)
                            let projH = dist * 0.65 * (1 - age)
                            let px = x + cos(pa) * dist
                            let py = h - 10 - sin(abs(pa)) * projH
                            let sz = (0.8 + H(seed + Double(j)*3) * 1.0) * layer.sizeMul
                            ctx.fill(Path(ellipseIn: CGRect(x: px-sz*0.5, y: py-sz*0.5, width: sz, height: sz)),
                                     with: .color(encre.opacity(age * 0.08 * (1 - age) * layer.opMul)))
                        }
                    }
                }
            }
        }

        // ── Brume au sol ──
        if heavy {
            for i in 0..<10 {
                let yMist = h - 4 - Double(i) * 18
                let drift = sin(t * 0.045 + Double(i) * 0.85) * 35
                let op = 0.028 - Double(i) * 0.0025
                var fog = Path()
                fog.move(to: CGPoint(x: -30 + drift, y: yMist - 14))
                var fx = -30.0 + drift
                while fx <= w + 30 + drift {
                    fog.addLine(to: CGPoint(x: fx, y: yMist - 14 + fbm(fx * 0.008 + t * 0.04 + Double(i)) * 8))
                    fx += 10
                }
                fog.addLine(to: CGPoint(x: w + 30 + drift, y: yMist + 14))
                fog.addLine(to: CGPoint(x: -30 + drift, y: yMist + 14))
                fog.closeSubpath()
                ctx.fill(fog, with: .color(Color(red: 0.48, green: 0.60, blue: 0.78).opacity(max(0, op))))
            }
            // Flaques réfléchissantes.
            // Remontées de 15 à 95 px : à 15 px elles tombaient derrière
            // la barre d'onglets et n'ont jamais été visibles.
            for i in 0..<8 {
                let seed = Double(i) * 457.3
                let px = H(seed) * w, pw = 25.0 + H(seed+1) * 55
                let shimmer = 0.018 + sin(t * 0.9 + seed) * 0.010
                ctx.fill(Path(ellipseIn: CGRect(x: px-pw*0.5, y: h-95, width: pw, height: 7)),
                         with: .color(Color(red: 0.55, green: 0.70, blue: 0.92).opacity(shimmer)))
            }
        }

        // ── Ruissellement sur la vitre ──
        //
        // Des gouttes collées à l'écran qui glissent en laissant une
        // traînée, comme derrière une fenêtre. C'est l'effet le plus
        // reconnaissable de la pluie, et surtout le seul visible sur
        // TOUTE la hauteur : les éclaboussures et les flaques ci-dessus
        // vivent en bas de l'écran, là où les cartes les recouvrent.
        let ruisseaux = heavy ? 16 : 9
        for i in 0..<ruisseaux {
            let seed = Double(i) * 811.7
            let rx = H(seed) * w
            let vitesse = 0.035 + H(seed + 1) * 0.085

            // Une goutte de vitre ne descend pas à vitesse constante :
            // elle stagne, accroche, puis file d'un coup. La sinusoïde
            // ajoutée à la progression donne ce glissement par à-coups.
            let cycle = fmod(t * vitesse + H(seed + 2), 1.0)
            let saccade = cycle + sin(cycle * .pi * 7) * 0.018
            let ry = saccade * (h + 80) - 40
            let taille = 1.8 + H(seed + 3) * 2.4
            let op = (0.10 + H(seed + 4) * 0.12) * (heavy ? 1.3 : 1.0)

            // Traînée laissée derrière
            var trainee = Path()
            trainee.move(to: CGPoint(x: rx, y: ry))
            trainee.addLine(to: CGPoint(x: rx, y: max(-40, ry - 35 - H(seed + 5) * 70)))
            ctx.stroke(trainee, with: .color(encre.opacity(op * 0.22)),
                       style: StrokeStyle(lineWidth: taille * 0.55, lineCap: .round))

            // Tête de la goutte, légèrement ovale (elle s'étire en tombant)
            ctx.fill(Path(ellipseIn: CGRect(x: rx - taille, y: ry - taille * 1.3,
                                            width: taille * 2, height: taille * 2.6)),
                     with: .color(encre.opacity(op)))

            // Reflet spéculaire : c'est lui qui fait « goutte d'eau »
            // plutôt que « point flou ».
            ctx.fill(Path(ellipseIn: CGRect(x: rx - taille * 0.34, y: ry - taille * 0.85,
                                            width: taille * 0.52, height: taille * 0.75)),
                     with: .color(.white.opacity(op * 0.45)))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — ❄️ SNOW
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum SnowFX {
    struct Flake {
        let tx, ty, r, spd, op, ph, rot: Double
        let layer: Int  // 0=lointain, 1=moyen, 2=proche
    }
    static let flakes: [Flake] = (0..<150).map { i in
        let s = Double(i) * 1.618033988
        return Flake(tx: fmod(s*0.314, 1), ty: fmod(s*0.271, 1),
                     r: 1.5 + fmod(s*0.773, 10.0),
                     spd: 0.18 + fmod(s*0.411, 0.92),
                     op: 0.22 + fmod(s*0.351, 0.58),
                     ph: s * 0.927, rot: fmod(s*2.718, .pi*2),
                     layer: i % 3)
    }

    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        let layerSpeed: [Double] = [0.28, 0.62, 1.0]
        let layerOpacity: [Double] = [0.40, 0.72, 1.0]

        // ── Lueur atmosphérique ambiante (ciel hivernal) ──
        let glow1X = w * 0.5 + sin(t * 0.06) * w * 0.18
        let glow1Y = h * 0.15 + cos(t * 0.04) * 25
        ctx.fill(Path(ellipseIn: CGRect(x: glow1X-240, y: glow1Y-140, width: 480, height: 280)),
                 with: .color(Color(red: 0.72, green: 0.82, blue: 1.0).opacity(0.020)))
        let glow2X = w * 0.3 + cos(t * 0.05) * 40
        ctx.fill(Path(ellipseIn: CGRect(x: glow2X-150, y: -60, width: 300, height: 200)),
                 with: .color(Color(red: 0.80, green: 0.85, blue: 0.95).opacity(0.015)))

        // ── Flocons ──
        for f in flakes {
            let sp = layerSpeed[f.layer]
            let opMul = layerOpacity[f.layer]

            // Mouvement complexe : vent tourbillonnant multi-fréquence
            let wb1 = sin(t * 0.50 * sp + f.ph) * 5.5
            let wb2 = cos(t * 0.30 * sp + f.ph * 1.7) * 3.5
            let wb3 = sin(t * 0.18 * sp + f.ph * 3.1) * 2.0  // basse fréquence
            let drift = sin(t * 0.10 + f.ph) * 10 * sp
            let x = fmod(f.tx * w + wb1 + wb2 + wb3 + drift + t * 7.5 * sp, w + 30) - 15
            let y = fmod(f.ty * h + t * (35 + f.spd * 25) * sp, h + 30) - 15
            let rot = f.rot + t * 0.10 * sp + sin(t * 0.25 + f.ph) * 0.25
            let finalOp = f.op * opMul

            if f.r > 6.0 {
                // ══ Grand flocon cristallin — rendu multi-passe ══
                let flake = crystalPath(cx: x, cy: y, r: f.r, seed: f.ph)
                // Passe 1 : lueur externe diffuse
                ctx.stroke(flake, with: .color(Color(red: 0.82, green: 0.90, blue: 1.0).opacity(finalOp * 0.22)),
                           style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
                // Passe 2 : lueur moyenne
                ctx.stroke(flake, with: .color(Color(red: 0.90, green: 0.95, blue: 1.0).opacity(finalOp * 0.50)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                // Passe 3 : cristal net
                ctx.stroke(flake, with: .color(encre.opacity(finalOp)),
                           style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
                // Noyau
                ctx.fill(Path(ellipseIn: CGRect(x: x-f.r*0.16, y: y-f.r*0.16, width: f.r*0.32, height: f.r*0.32)),
                         with: .color(encre.opacity(finalOp * 0.95)))
                // Scintillement pulsant
                let sparkle = 0.25 + sin(t * 2.2 + f.ph * 3.3) * 0.25
                ctx.fill(Path(ellipseIn: CGRect(x: x-1.8, y: y-1.8, width: 3.6, height: 3.6)),
                         with: .color(encre.opacity(sparkle * finalOp)))
                // Reflet spéculaire mobile
                let specA = t * 0.18 + f.ph
                let specX = x + cos(specA) * f.r * 0.28
                let specY = y + sin(specA) * f.r * 0.28
                ctx.fill(Path(ellipseIn: CGRect(x: specX-1.2, y: specY-0.8, width: 2.4, height: 1.6)),
                         with: .color(encre.opacity(0.50)))

            } else if f.r > 3.5 {
                // ══ Flocon moyen — 6 branches + halo ══
                var mini = Path()
                for arm in 0..<6 {
                    let a = Double(arm) * (.pi / 3.0) + rot
                    mini.move(to: CGPoint(x: x, y: y))
                    mini.addLine(to: CGPoint(x: x + cos(a)*f.r, y: y + sin(a)*f.r))
                    // Petites sous-branches
                    let bx = x + cos(a)*f.r*0.55, by = y + sin(a)*f.r*0.55
                    for side in [-1.0, 1.0] {
                        let sa = a + side * (.pi / 3.5)
                        mini.move(to: CGPoint(x: bx, y: by))
                        mini.addLine(to: CGPoint(x: bx + cos(sa)*f.r*0.25, y: by + sin(sa)*f.r*0.25))
                    }
                }
                // Halo
                ctx.fill(Path(ellipseIn: CGRect(x: x-f.r*0.7, y: y-f.r*0.7, width: f.r*1.4, height: f.r*1.4)),
                         with: .color(encre.opacity(finalOp * 0.06)))
                ctx.stroke(mini, with: .color(encre.opacity(finalOp)),
                           style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: x-1.4, y: y-1.4, width: 2.8, height: 2.8)),
                         with: .color(encre.opacity(finalOp)))

            } else {
                // ══ Petit flocon — étoile scintillante ══
                let twinkle = 0.5 + sin(t * 3.5 + f.ph * 5.5) * 0.5
                var star = Path()
                for k in 0..<8 {
                    let a = Double(k) / 8.0 * (.pi * 2) + rot
                    let rr = k % 2 == 0 ? f.r : f.r * 0.25
                    let pt = CGPoint(x: x + cos(a)*rr, y: y + sin(a)*rr)
                    k == 0 ? star.move(to: pt) : star.addLine(to: pt)
                }
                star.closeSubpath()
                ctx.fill(star, with: .color(encre.opacity(finalOp * twinkle)))
                // Micro-halo
                ctx.fill(Path(ellipseIn: CGRect(x: x-f.r, y: y-f.r, width: f.r*2, height: f.r*2)),
                         with: .color(encre.opacity(finalOp * 0.04)))
            }
        }

        // ── Accumulation neige au sol (courbe organique) ──
        var acc = Path()
        acc.move(to: CGPoint(x: 0, y: h))
        var px = 0.0
        while px <= w {
            let b = fbm(px * 0.003 + t * 0.008) * 12 + sin(px * 0.015 + t * 0.03) * 4 + sin(px * 0.06) * 1.5
            acc.addLine(to: CGPoint(x: px, y: h - 13 - b))
            px += 2.5
        }
        acc.addLine(to: CGPoint(x: w, y: h)); acc.closeSubpath()
        ctx.fill(acc, with: .color(encre.opacity(0.20)))
        // Liseré lumineux
        var edge = Path()
        px = 0; edge.move(to: CGPoint(x: 0, y: h - 13 - fbm(t * 0.008) * 12))
        while px <= w {
            let b = fbm(px * 0.003 + t * 0.008) * 12 + sin(px * 0.015 + t * 0.03) * 4 + sin(px * 0.06) * 1.5
            edge.addLine(to: CGPoint(x: px, y: h - 13 - b)); px += 2.5
        }
        ctx.stroke(edge, with: .color(encre.opacity(0.35)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

        // Givre scintillant sur la neige
        for i in 0..<22 {
            let gx = w * Double(i) / 22.0 + sin(Double(i) * 2.1) * 12
            let b = fbm(gx * 0.003 + t * 0.008) * 12 + sin(gx * 0.015 + t * 0.03) * 4
            let gy = h - 15 - b
            let gs = 1.5 + H(Double(i) * 7.3) * 4.0
            let twinkle = 0.12 + sin(t * 1.8 + Double(i) * 2.5) * 0.10
            let micro = crystalPath(cx: gx, cy: gy, r: gs, seed: Double(i))
            ctx.stroke(micro, with: .color(encre.opacity(twinkle)), style: StrokeStyle(lineWidth: 0.45, lineCap: .round))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — ⛈ THUNDER
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum ThunderFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        // Pluie forte de base — sauf si le GPU la rend déjà (CielMetal)
        if !CielMetal.disponible { RainFX.draw(ctx: ctx, s: s, t: t, heavy: true, encre: encre) }
        let w = s.width, h = s.height

        // ── Flash double (flash + écho réaliste) ──
        let fc = fmod(t * 0.60, 6.5)
        var fOp = 0.0
        if fc < 0.035 { fOp = fc / 0.035 * 0.35 }
        else if fc < 0.07 { fOp = 0.35 * (1 - (fc - 0.035) / 0.035) * 0.4 }
        else if fc < 0.10 { fOp = 0.14 * ((fc - 0.07) / 0.03) }
        else if fc < 0.20 { fOp = 0.14 * (1 - (fc - 0.10) / 0.10) }
        // Écho secondaire
        let fc2 = fmod(t * 0.60 + 3.2, 6.5)
        if fc2 < 0.05 { fOp += fc2 / 0.05 * 0.10 }
        else if fc2 < 0.12 { fOp += 0.10 * (1 - (fc2 - 0.05) / 0.07) }

        if fOp > 0.001 {
            // Illumination non-uniforme (plus brillant en haut + gauche)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.45)),
                     with: .color(Color(red: 0.82, green: 0.88, blue: 1.0).opacity(fOp)))
            ctx.fill(Path(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)),
                     with: .color(Color(red: 0.82, green: 0.88, blue: 1.0).opacity(fOp * 0.40)))
        }

        // ── Éclairs (3 canaux à fréquences différentes) ──
        let bolts: [(Double, Double, Double)] = [(0.44, 1.3, 6.0), (0.33, 5.2, 10.0), (0.22, 2.1, 14.0)]
        for (freq, offset, period) in bolts {
            let bc = fmod(t * freq + offset, period)
            let dur = period < 8 ? 0.60 : 0.40
            if bc < dur {
                let rise = period < 8 ? 0.08 : 0.05
                let op = bc < rise ? bc / rise : max(0, 1 - (bc - rise) / (dur - rise))
                let mul = period < 8 ? 1.0 : (period < 12 ? 0.65 : 0.45)
                drawBolt(ctx: ctx, s: s, t: t, opacity: op * mul,
                         seed: Double(Int(t * freq)) * (period < 8 ? 100 : 77) + offset * 10)
            }
        }

        // ── Nuages illuminés par les flashs ──
        if fOp > 0.04 {
            for i in 0..<4 {
                let seed = Double(i) * 3333
                let ccx = w * (0.15 + H(seed) * 0.7)
                let ccy = h * 0.03 + H(seed + 1) * h * 0.12
                let cloud = cloudShape(cx: ccx, cy: ccy, scale: 75 + H(seed + 2) * 70, seed: seed)
                ctx.fill(cloud, with: .color(Color(red: 0.68, green: 0.76, blue: 0.95).opacity(fOp * 0.28)))
            }
        }
    }

    static func drawBolt(ctx: GraphicsContext, s: CGSize, t: Double, opacity: Double, seed: Double) {
        let w = s.width, h = s.height
        // Point de départ et d'arrivée
        var pts: [(Double, Double)] = [
            (w * (0.15 + H(seed) * 0.70), -20),
            (w * (0.20 + H(seed + 1) * 0.60), h * 0.92 + H(seed + 2) * h * 0.08)
        ]
        // 7 niveaux de subdivision midpoint pour un maximum de détail
        for level in 0..<7 {
            let displace = w * 0.22 / pow(2, Double(level))
            var newPts: [(Double, Double)] = [pts[0]]
            for i in 0..<pts.count - 1 {
                let mx = (pts[i].0 + pts[i+1].0) * 0.5 + (H(seed + Double(i) + Double(level) * 100) - 0.5) * displace
                let my = (pts[i].1 + pts[i+1].1) * 0.5
                newPts.append((mx, my)); newPts.append(pts[i + 1])
            }
            pts = newPts
        }

        var main = Path()
        main.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for p in pts.dropFirst() { main.addLine(to: CGPoint(x: p.0, y: p.1)) }

        // 6 passes de rendu : lueur externe très diffuse → cœur brillant
        let passes: [(Double, Double)] = [
            (42, 0.030), (26, 0.065), (14, 0.15), (7, 0.32), (3, 0.60), (1.0, 1.0)
        ]
        let colors: [Color] = [
            Color(red: 0.30, green: 0.45, blue: 1.0), Color(red: 0.45, green: 0.60, blue: 1.0),
            Color(red: 0.60, green: 0.78, blue: 1.0), Color(red: 0.78, green: 0.88, blue: 1.0),
            Color(red: 0.90, green: 0.95, blue: 1.0), Color(red: 0.98, green: 0.99, blue: 1.0)
        ]
        for i in 0..<passes.count {
            ctx.stroke(main, with: .color(colors[i].opacity(opacity * passes[i].1)),
                       style: StrokeStyle(lineWidth: CGFloat(passes[i].0), lineCap: .round, lineJoin: .round))
        }

        // ── Branches secondaires avec sous-ramifications ──
        let interval = max(3, pts.count / 12)
        for i in stride(from: interval, to: pts.count - 3, by: interval) {
            let bx0 = pts[i].0, by0 = pts[i].1
            let dir = H(seed + Double(i)) > 0.5 ? 1.0 : -1.0
            let bLen = 3 + Int(H(seed + Double(i) + 0.5) * 5)
            var bPts: [(Double, Double)] = [(bx0, by0)]
            var bx = bx0, by = by0
            for b in 0..<bLen {
                bx += dir * (15 + H(seed + Double(i) + Double(b)) * 42) + (H(seed + Double(b + i) * 2) - 0.5) * 22
                by += (h - by0) / Double(bLen + 1)
                bPts.append((bx, by))
            }
            var branch = Path()
            branch.move(to: CGPoint(x: bPts[0].0, y: bPts[0].1))
            for bp in bPts.dropFirst() { branch.addLine(to: CGPoint(x: bp.0, y: bp.1)) }
            ctx.stroke(branch, with: .color(Color(red: 0.45, green: 0.65, blue: 1.0).opacity(opacity * 0.12)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            ctx.stroke(branch, with: .color(Color(red: 0.75, green: 0.88, blue: 1.0).opacity(opacity * 0.30)),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            // Le cœur de l'éclair reste blanc quel que soit le thème :
            // c'est une source lumineuse, pas une particule.
            ctx.stroke(branch, with: .color(.white.opacity(opacity * 0.18)),
                       style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round))

            // Sous-ramifications tertiaires
            if bLen > 3 {
                let subIdx = bLen / 2
                if subIdx < bPts.count {
                    let sbx0 = bPts[subIdx].0, sby0 = bPts[subIdx].1
                    let sd = H(seed + Double(i) * 5) > 0.5 ? 1.0 : -1.0
                    var sub = Path()
                    sub.move(to: CGPoint(x: sbx0, y: sby0))
                    let endX = sbx0 + sd * (20 + H(seed + Double(i)*3) * 35)
                    let endY = sby0 + 35 + H(seed + Double(i)*4) * 30
                    sub.addLine(to: CGPoint(x: endX, y: endY))
                    ctx.stroke(sub, with: .color(Color(red: 0.70, green: 0.85, blue: 1.0).opacity(opacity * 0.14)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            }
        }

        // ── Point d'impact (lueur au sol) ──
        if opacity > 0.25 {
            let impX = pts.last?.0 ?? w * 0.5
            let impR = 70.0 * opacity
            ctx.fill(Path(ellipseIn: CGRect(x: impX - impR, y: h - 22 - impR * 0.25,
                                             width: impR * 2, height: impR * 0.5)),
                     with: .color(Color(red: 0.65, green: 0.82, blue: 1.0).opacity(0.07 * opacity)))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — ☁️ CLOUDS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum CloudFX {
    struct Def { let speed: Double; let yBase: Double; let scaleRange: (Double, Double); let op: Double; let count: Int }
    static let defs = [
        Def(speed: 4,  yBase: -0.04, scaleRange: (150, 220), op: 0.055, count: 4),   // cirrus lointain
        Def(speed: 8,  yBase: 0.04,  scaleRange: (100, 170), op: 0.095, count: 5),   // alto
        Def(speed: 14, yBase: 0.14,  scaleRange: (70, 125),  op: 0.085, count: 6),   // cumulus moyen
        Def(speed: 20, yBase: 0.26,  scaleRange: (50, 95),   op: 0.070, count: 4),   // proche
    ]

    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height

        // ── Voile atmosphérique haute altitude ──
        for i in 0..<3 {
            let vY = h * (-0.02 + Double(i) * 0.06) + sin(t * 0.03 + Double(i)) * 8
            let drift = t * 3 + Double(i) * 50
            var veil = Path()
            veil.move(to: CGPoint(x: -60, y: vY - 35))
            var vx = -60.0
            while vx <= w + 60 {
                let yOff = fbm(vx * 0.003 + drift * 0.001 + Double(i) * 10) * 18
                veil.addLine(to: CGPoint(x: vx, y: vY - 35 + yOff)); vx += 10
            }
            veil.addLine(to: CGPoint(x: w + 60, y: vY + 50))
            veil.addLine(to: CGPoint(x: -60, y: vY + 50)); veil.closeSubpath()
            ctx.fill(veil, with: .color(encre.opacity(0.022)))
        }

        for (li, def) in defs.enumerated() {
            for ci in 0..<def.count {
                let seed = Double(li * 5000 + ci * 997)
                let cxc = fmod(H(seed) * (w + 500) + t * def.speed, w + 550) - 275
                let cyc = h * def.yBase + sin(t * 0.08 + seed * 0.4) * 14
                let scale = def.scaleRange.0 + H(seed + 1) * (def.scaleRange.1 - def.scaleRange.0)
                let op = def.op * (0.65 + H(seed + 2) * 0.7)

                // Ombre portée (projetée en-dessous, décalée)
                let shadowOff = 5 + scale * 0.06
                ctx.fill(cloudShape(cx: cxc + shadowOff, cy: cyc + shadowOff * 2.5, scale: scale * 0.82, seed: seed + 0.1),
                         with: .color(Color(red: 0.28, green: 0.32, blue: 0.48).opacity(op * 0.22)))

                // Corps principal
                ctx.fill(cloudShape(cx: cxc, cy: cyc, scale: scale, seed: seed),
                         with: .color(encre.opacity(op)))

                // Auto-ombrage (face inférieure plus sombre)
                ctx.fill(cloudShape(cx: cxc + 2, cy: cyc + scale * 0.14, scale: scale * 0.65, seed: seed + 0.3),
                         with: .color(Color(red: 0.55, green: 0.60, blue: 0.72).opacity(op * 0.22)))

                // Demi-ton intermédiaire
                ctx.fill(cloudShape(cx: cxc - 1, cy: cyc + scale * 0.05, scale: scale * 0.50, seed: seed + 0.6),
                         with: .color(Color(red: 0.70, green: 0.73, blue: 0.82).opacity(op * 0.12)))

                // Silver lining (bord supérieur lumineux)
                ctx.fill(cloudShape(cx: cxc - 5, cy: cyc - scale * 0.13, scale: scale * 0.42, seed: seed + 0.5),
                         with: .color(encre.opacity(op * 0.55)))

                // Rim lighting (éclat fin)
                ctx.fill(cloudShape(cx: cxc - 7, cy: cyc - scale * 0.20, scale: scale * 0.28, seed: seed + 0.8),
                         with: .color(encre.opacity(op * 0.40)))

                // Mouvement interne (convection)
                let inDrift = sin(t * 0.07 + seed) * 10
                ctx.fill(cloudShape(cx: cxc + inDrift, cy: cyc - scale * 0.04, scale: scale * 0.32, seed: seed + 3),
                         with: .color(encre.opacity(op * 0.14)))
                let inDrift2 = cos(t * 0.06 + seed * 1.5) * 8
                ctx.fill(cloudShape(cx: cxc + inDrift2 * 0.5, cy: cyc + scale * 0.08, scale: scale * 0.25, seed: seed + 5),
                         with: .color(encre.opacity(op * 0.08)))
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — 🌫 FOG
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum FogFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height

        // ── Couches ondulées de brume (FBM-driven) ──
        for i in 0..<20 {
            let yBase = h * (Double(i) / 20.0) - 25
            let drift = sin(t * 0.040 + Double(i) * 0.72) * 70 + cos(t * 0.025 + Double(i) * 1.25) * 30
            let op = 0.032 + sin(t * 0.06 + Double(i) * 1.15) * 0.016
            let thickness = 30.0 + sin(Double(i) * 0.45) * 12

            var fog = Path()
            fog.move(to: CGPoint(x: -100 + drift, y: yBase - thickness))
            let steps = 14
            for step in 0...steps {
                let sx = Double(step) / Double(steps)
                let xx = -100 + drift + (w + 200) * sx
                let yOff = fbm(xx * 0.004 + t * 0.015 + Double(i) * 3) * 18
                    + sin(sx * .pi * 2 + Double(i) * 0.75 + t * 0.05) * 8
                fog.addLine(to: CGPoint(x: xx, y: yBase - thickness + yOff))
            }
            for step in (0...steps).reversed() {
                let sx = Double(step) / Double(steps)
                let xx = -100 + drift + (w + 200) * sx
                let yOff = fbm(xx * 0.005 + t * 0.012 + Double(i) * 3 + 50) * 12
                    + sin(sx * .pi * 2.3 + Double(i) * 1.05 + t * 0.04) * 6
                fog.addLine(to: CGPoint(x: xx, y: yBase + thickness + yOff))
            }
            fog.closeSubpath()
            ctx.fill(fog, with: .color(Color(red: 0.82, green: 0.87, blue: 0.93).opacity(op)))
        }

        // ── Bancs de brouillard denses (masses compactes) ──
        for i in 0..<7 {
            let seed = Double(i) * 523.7
            let bx = fmod(H(seed) * w + t * (2.5 + H(seed + 1) * 4.5), w + 350) - 175
            let by = h * (0.15 + H(seed + 2) * 0.65)
            let bScale = 80 + H(seed + 3) * 90
            let bOp = 0.035 + H(seed + 4) * 0.030

            // Ombre du banc
            ctx.fill(cloudShape(cx: bx + 4, cy: by + 12, scale: bScale * 0.85, seed: seed + 0.1),
                     with: .color(Color(red: 0.65, green: 0.70, blue: 0.78).opacity(bOp * 0.3)))
            // Corps du banc
            ctx.fill(cloudShape(cx: bx, cy: by, scale: bScale, seed: seed),
                     with: .color(Color(red: 0.84, green: 0.89, blue: 0.95).opacity(bOp)))
            // Reflet lumineux supérieur
            ctx.fill(cloudShape(cx: bx - 5, cy: by - bScale * 0.12, scale: bScale * 0.38, seed: seed + 10),
                     with: .color(encre.opacity(bOp * 0.45)))
        }

        // ── Micro-gouttelettes en suspension (humidité visible) ──
        for i in 0..<40 {
            let seed = Double(i) * 97.3
            let px = fmod(H(seed) * w + sin(t * 0.07 + seed) * 22, w)
            let py = H(seed + 1) * h
            let pr = 1.2 + H(seed + 2) * 3.5
            let twinkle = 0.012 + sin(t * 0.45 + seed * 2.1) * 0.008
            ctx.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                     with: .color(encre.opacity(twinkle)))
        }

        // ── Puits de lumière (rayons filtrant à travers le brouillard) ──
        for i in 0..<4 {
            let seed = Double(i) * 777
            let lx = w * (0.10 + H(seed) * 0.80)
            let pulse = 0.45 + sin(t * 0.12 + seed) * 0.30 + sin(t * 0.05 + seed * 2) * 0.15
            let op = 0.013 * pulse
            let topW = 12.0, botW = 55.0
            var shaft = Path()
            shaft.move(to: CGPoint(x: lx - topW, y: 0))
            shaft.addLine(to: CGPoint(x: lx + topW, y: 0))
            shaft.addLine(to: CGPoint(x: lx + botW, y: h))
            shaft.addLine(to: CGPoint(x: lx - botW * 0.3, y: h))
            shaft.closeSubpath()
            ctx.fill(shaft, with: .color(Color(red: 0.94, green: 0.95, blue: 1.0).opacity(op)))
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: — RÉGIMES EXTRÊMES
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Tornade : la pluie de tempête, un plafond nuageux qui pèse, un
/// entonnoir sombre qui descend en se tordant, et des débris qui
/// tourbillonnent à sa base.
private enum TornadeFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        RainFX.draw(ctx: ctx, s: s, t: t, heavy: true, encre: encre)

        // Plafond nuageux : le haut de l'écran s'assombrit
        ctx.fill(Path(CGRect(x: -20, y: -20, width: w + 40, height: h * 0.24 + 20)),
                 with: .linearGradient(Gradient(colors: [Color.black.opacity(0.42), Color.black.opacity(0)]),
                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h * 0.24)))

        // L'entonnoir : des ellipses empilées, de plus en plus étroites,
        // décalées par un balancement lent et une torsion plus rapide.
        let baseX = w * 0.64 + sin(t * 0.21) * 28
        let sommetY = h * 0.15, solY = h * 0.93
        let n = 28
        for i in 0..<n {
            let f = Double(i) / Double(n - 1)                 // 0 au plafond, 1 au sol
            let y = sommetY + (solY - sommetY) * f
            let rayon = (120.0 * (1 - f) * (1 - f) + 16) * (1 + sin(t * 3 + f * 9) * 0.06)
            let x = baseX + sin(f * 3.2 + t * 0.9) * 30 * f + fbm(t * 0.3 + f * 4) * 22 * f
            ctx.fill(Path(ellipseIn: CGRect(x: x - rayon, y: y - rayon * 0.22, width: rayon * 2, height: rayon * 0.44)),
                     with: .color(Color(red: 0.15, green: 0.15, blue: 0.16).opacity(0.28 + f * 0.30)))
            // Un filet clair qui tourne autour : c'est lui qui donne la rotation
            let a = t * 4 + f * 6
            let px = x + cos(a) * rayon, py = y + sin(a) * rayon * 0.22
            ctx.fill(Path(ellipseIn: CGRect(x: px - 2, y: py - 1, width: 4, height: 2)),
                     with: .color(encre.opacity(0.08 + 0.16 * f)))
        }

        // Débris : un tourbillon de points bruns à la base
        for i in 0..<70 {
            let seed = Double(i) * 977 + 13
            let a = t * (1.6 + H(seed) * 1.4) + H(seed + 1) * 6.28
            let r = 30 + H(seed + 2) * 150 + sin(t * 0.7 + H(seed + 3) * 6) * 20
            let x = baseX + cos(a) * r
            let y = solY - 8 - H(seed + 4) * 100 + sin(a * 2) * 10
            let taille = 1.5 + H(seed + 5) * 3
            ctx.fill(Path(ellipseIn: CGRect(x: x - taille / 2, y: y - taille / 2, width: taille, height: taille)),
                     with: .color(Color(red: 0.55, green: 0.48, blue: 0.38).opacity(0.30 + H(seed + 6) * 0.45)))
        }
    }
}

/// Tempête : la pluie forte, et le vent rendu visible — de longues
/// traînées presque horizontales qui filent de gauche à droite.
private enum TempeteFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        RainFX.draw(ctx: ctx, s: s, t: t, heavy: true, encre: encre)
        for i in 0..<80 {
            let seed = Double(i) * 733 + 5
            let y = H(seed) * h
            let vitesse = 620 + H(seed + 1) * 520
            let x = fmod(H(seed + 2) * (w + 400) + t * vitesse, w + 400) - 200
            let longueur = 60 + H(seed + 3) * 170
            var trait = Path()
            trait.move(to: CGPoint(x: x, y: y))
            trait.addLine(to: CGPoint(x: x + longueur, y: y + longueur * 0.14))
            ctx.stroke(trait, with: .color(encre.opacity(0.04 + H(seed + 4) * 0.10)),
                       style: StrokeStyle(lineWidth: 0.8 + H(seed + 5) * 0.8, lineCap: .round))
        }
    }
}

/// Grêle : des grêlons blancs et opaques qui tombent vite, presque droit,
/// avec un léger tremblement — rien à voir avec la neige qui flotte.
private enum GreleFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        // Une brume froide en haut, comme sous un cumulonimbus
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.3)),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.3)))
        for i in 0..<170 {
            let seed = Double(i) * 641 + 3
            let vitesse = 700 + H(seed) * 350
            let x = fmod(H(seed + 1) * w + sin(t * 0.6 + H(seed + 2) * 6.28) * 18, w + 40) - 20
            let y = fmod(H(seed + 3) * h + t * vitesse, h + 40) - 20
            let r = 1.6 + H(seed + 4) * 2.6
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(encre.opacity(0.55 + H(seed + 5) * 0.4)))
            // Un reflet : le grêlon est une bille, pas un flocon
            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.6, height: r * 0.45)),
                     with: .color(.white.opacity(0.5)))
        }
    }
}

/// Canicule : le soleil du beau temps, puis l'air qui tremble — des
/// ondulations serrées sur toute la moitié basse et une brume chaude.
private enum CaniculeFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, phase: PhaseSolaire) {
        let w = s.width, h = s.height
        if phase.estNuit { NuitFX.draw(ctx: ctx, s: s, t: t, phase: phase) }
        else             { ClearFX.draw(ctx: ctx, s: s, t: t, phase: phase) }
        for i in 0..<16 {
            let yy = h * 0.40 + Double(i) * (h * 0.6 / 16)
            var onde = Path()
            onde.move(to: CGPoint(x: -10, y: yy))
            var x = -10.0
            while x <= w + 10 {
                let dy = sin(x * 0.05 + t * 3.2 + Double(i) * 0.9) * 2.2 + sin(x * 0.11 - t * 2.1) * 1.2
                onde.addLine(to: CGPoint(x: x, y: yy + dy))
                x += 6
            }
            ctx.stroke(onde, with: .color(Color(red: 1, green: 0.90, blue: 0.70).opacity(0.05)),
                       style: StrokeStyle(lineWidth: 1.4 + sin(t * 0.6 + Double(i)) * 0.6))
        }
        ctx.fill(Path(CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45)),
                 with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.55, blue: 0.15).opacity(0),
                                                         Color(red: 1, green: 0.55, blue: 0.15).opacity(0.16)]),
                                       startPoint: CGPoint(x: 0, y: h * 0.55), endPoint: CGPoint(x: 0, y: h)))
    }
}

/// Grand froid : l'air scintille de cristaux, du givre gagne les coins de
/// la fenêtre, et quelques flocons fins tombent sans hâte.
private enum GrandFroidFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        // Givre : un halo blanc bleuté dans chaque coin
        for (cx, cy) in [(0.0, 0.0), (w, 0.0), (0.0, h), (w, h)] {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 260, y: cy - 200, width: 520, height: 400)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.85, green: 0.92, blue: 1).opacity(0.14),
                                                             Color(red: 0.85, green: 0.92, blue: 1).opacity(0)]),
                                           center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: 260))
        }
        // Cristaux en suspension : ils scintillent plus qu'ils ne bougent
        for i in 0..<110 {
            let seed = Double(i) * 877 + 9
            let x = fmod(H(seed) * w + sin(t * 0.15 + H(seed + 1) * 6.28) * 6, w)
            let y = fmod(H(seed + 2) * h + t * (4 + H(seed + 3) * 6), h)
            let scintille = max(0, sin(t * (1.5 + H(seed + 4) * 2) + H(seed + 5) * 6.28))
            let r = 0.6 + H(seed + 6) * 1.4
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(encre.opacity(0.15 + scintille * 0.6)))
        }
        // Quelques flocons fins, lents
        for i in 0..<40 {
            let seed = Double(i) * 313 + 1
            let x = fmod(H(seed) * w + sin(t * 0.4 + H(seed + 1) * 6.28) * 14, w + 20) - 10
            let y = fmod(H(seed + 2) * h + t * (18 + H(seed + 3) * 14), h + 20) - 10
            let r = 1 + H(seed + 4) * 1.6
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(encre.opacity(0.35 + H(seed + 5) * 0.4)))
        }
    }
}

/// Tempête de poussière : la brume du brouillard, mais ocre, et des grains
/// qui filent à l'horizontale.
private enum PoussiereFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double) {
        let w = s.width, h = s.height
        let ocre = Color(red: 0.85, green: 0.70, blue: 0.45)
        FogFX.draw(ctx: ctx, s: s, t: t, encre: ocre)
        for i in 0..<220 {
            let seed = Double(i) * 419 + 7
            let y = H(seed) * h
            let vitesse = 260 + H(seed + 1) * 420
            let x = fmod(H(seed + 2) * (w + 100) + t * vitesse, w + 100) - 50
            let r = 0.7 + H(seed + 3) * 1.6
            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 2, y: y - r * 0.5, width: r * 4, height: r)),
                     with: .color(ocre.opacity(0.10 + H(seed + 4) * 0.30)))
        }
    }
}

/// Cyclone : la pluie de tempête, le vent deux fois plus dense que la
/// tempête, et les bandes spiralées qui tournent autour d'un œil hors
/// champ, en haut à droite.
private enum CycloneFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        RainFX.draw(ctx: ctx, s: s, t: t, heavy: true, encre: encre)
        // Les bandes spiralées : trois arcs épais qui tournent lentement
        let oeil = CGPoint(x: w * 0.88, y: h * 0.06)
        for k in 0..<3 {
            let r = 260.0 + Double(k) * 200
            let debut = t * 0.18 + Double(k) * 1.4
            var bande = Path()
            bande.addArc(center: oeil, radius: r, startAngle: .radians(debut), endAngle: .radians(debut + 1.9), clockwise: false)
            ctx.stroke(bande, with: .color(Color.black.opacity(0.13)), style: StrokeStyle(lineWidth: 70 + Double(k) * 20, lineCap: .round))
        }
        // Le vent, deux fois plus dense qu'en tempête
        for i in 0..<160 {
            let seed = Double(i) * 733 + 5
            let y = H(seed) * h
            let vitesse = 800 + H(seed + 1) * 700
            let x = fmod(H(seed + 2) * (w + 400) + t * vitesse, w + 400) - 200
            let longueur = 80 + H(seed + 3) * 200
            var trait = Path()
            trait.move(to: CGPoint(x: x, y: y))
            trait.addLine(to: CGPoint(x: x + longueur, y: y + longueur * 0.18))
            ctx.stroke(trait, with: .color(encre.opacity(0.05 + H(seed + 4) * 0.12)),
                       style: StrokeStyle(lineWidth: 0.8 + H(seed + 5) * 1.0, lineCap: .round))
        }
    }
}

/// Blizzard : le voile blanc du brouillard, la neige, et un vent qui la
/// couche à l'horizontale — on ne voit plus rien.
private enum BlizzardFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        FogFX.draw(ctx: ctx, s: s, t: t, encre: .white)
        SnowFX.draw(ctx: ctx, s: s, t: t, encre: encre)
        for i in 0..<140 {
            let seed = Double(i) * 547 + 11
            let y = H(seed) * h
            let vitesse = 500 + H(seed + 1) * 500
            let x = fmod(H(seed + 2) * (w + 300) + t * vitesse, w + 300) - 150
            let longueur = 30 + H(seed + 3) * 110
            var trait = Path()
            trait.move(to: CGPoint(x: x, y: y))
            trait.addLine(to: CGPoint(x: x + longueur, y: y + longueur * 0.10))
            ctx.stroke(trait, with: .color(Color.white.opacity(0.08 + H(seed + 4) * 0.22)),
                       style: StrokeStyle(lineWidth: 1 + H(seed + 5) * 1.4, lineCap: .round))
        }
    }
}

/// Pluie verglaçante : une pluie fine, du givre qui gagne les coins, et
/// en bas le sol qui luit — la glace, c'est de la pluie qui brille.
private enum VerglasFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        RainFX.draw(ctx: ctx, s: s, t: t, heavy: false, encre: encre)
        for (cx, cy) in [(0.0, 0.0), (w, 0.0), (0.0, h), (w, h)] {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 240, y: cy - 180, width: 480, height: 360)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.85, green: 0.92, blue: 1).opacity(0.16),
                                                             Color(red: 0.85, green: 0.92, blue: 1).opacity(0)]),
                                           center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: 240))
        }
        // Le sol glacé : un reflet qui ondule doucement en bas de l'écran
        for i in 0..<10 {
            let yy = h * 0.82 + Double(i) * (h * 0.18 / 10)
            var reflet = Path()
            var x = -10.0
            reflet.move(to: CGPoint(x: x, y: yy))
            while x <= w + 10 {
                reflet.addLine(to: CGPoint(x: x, y: yy + sin(x * 0.02 + t * 0.8 + Double(i)) * 1.5))
                x += 8
            }
            ctx.stroke(reflet, with: .color(Color.white.opacity(0.05 + Double(i) * 0.012)),
                       style: StrokeStyle(lineWidth: 1.2))
        }
    }
}

/// Déluge : deux pluies fortes superposées, décalées dans le temps pour
/// doubler la densité, et l'eau qui monte en bas de l'écran.
private enum DelugeFX {
    static func draw(ctx: GraphicsContext, s: CGSize, t: Double, encre: Color) {
        let w = s.width, h = s.height
        RainFX.draw(ctx: ctx, s: s, t: t, heavy: true, encre: encre)
        RainFX.draw(ctx: ctx, s: s, t: t + 37.3, heavy: true, encre: encre)
        // L'eau : une nappe bleutée dont la surface ondule
        let niveau = h * 0.90 + sin(t * 0.6) * 2
        var eau = Path()
        eau.move(to: CGPoint(x: 0, y: h))
        eau.addLine(to: CGPoint(x: 0, y: niveau))
        var x = 0.0
        while x <= w {
            eau.addLine(to: CGPoint(x: x, y: niveau + sin(x * 0.03 + t * 1.6) * 3 + sin(x * 0.07 - t * 2.3) * 1.5))
            x += 8
        }
        eau.addLine(to: CGPoint(x: w, y: h))
        eau.closeSubpath()
        ctx.fill(eau, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.70, blue: 0.90).opacity(0.22),
                                                              Color(red: 0.30, green: 0.45, blue: 0.70).opacity(0.10)]),
                                            startPoint: CGPoint(x: 0, y: niveau), endPoint: CGPoint(x: 0, y: h)))
        // Les impacts : des ronds qui s'élargissent à la surface
        for i in 0..<30 {
            let seed = Double(i) * 271 + 3
            let phase = fmod(t * (0.8 + H(seed) * 0.6) + H(seed + 1) * 3, 1)
            let cx = H(seed + 2) * w, r = 2 + phase * 14
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - r, y: niveau - r * 0.25, width: r * 2, height: r * 0.5)),
                       with: .color(Color.white.opacity((1 - phase) * 0.35)), lineWidth: 1)
        }
    }
}

