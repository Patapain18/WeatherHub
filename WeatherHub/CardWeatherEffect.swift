import SwiftUI

// ╔══════════════════════════════════════════════════════════════════════╗
// ║  CardWeatherEffect — Apple Weather-style miniature card effects    ║
// ╚══════════════════════════════════════════════════════════════════════╝

struct CardWeatherEffect: View {
    let condition: String

    /// Même logique que WeatherBackground — et ici l'enjeu est x8,
    /// puisque huit cartes portent cet effet.
    @Environment(\.controlActiveState) private var etatFenetre
    @Environment(\.colorScheme) private var schemaCouleur

    /// Même logique que le décor de fond : une goutte blanche ne se voit
    /// pas sur une carte claire.
    private var encre: Color {
        schemaCouleur == .light ? Color(red: 0.22, green: 0.26, blue: 0.34) : .white
    }

    private var key: String {
        let c = condition.lowercased()
        if c.contains("thunder")  { return "thunder" }
        if c.contains("rain")     { return "rain" }
        if c.contains("drizzle")  { return "drizzle" }
        if c.contains("snow")     { return "snow" }
        if c.contains("clear")    { return "clear" }
        if c.contains("wind")     { return "wind" }
        return "none"
    }

    var body: some View {
        if key == "none" || etatFenetre == .inactive {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    switch key {
                    case "rain", "thunder": cardRain(ctx, size, t, encre: encre, heavy: key == "thunder")
                    case "drizzle":         cardRain(ctx, size, t, encre: encre, heavy: false)
                    case "snow":            cardSnow(ctx, size, t, encre: encre)
                    case "clear":           cardSun(ctx, size, t, encre: encre)
                    case "wind":            cardWind(ctx, size, t, encre: encre)
                    default: break
                    }
                }
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }

    // MARK: — Helpers

    private func h(_ n: Double) -> Double { abs(fmod(sin(n) * 43758.5453, 1.0)) }
    private func fbm1(_ x: Double) -> Double {
        var v = 0.0, amp = 0.5, freq = 1.0
        for _ in 0..<3 {
            let i = floor(x * freq); let f = x * freq - i; let u = f*f*(3-2*f)
            v += (fmod(sin(i)*43758.5453123, 1.0 - fmod(sin(i)*43758.5453123, 1.0)) * (1-u)
                  + fmod(sin(i+1)*43758.5453123, 1.0 - fmod(sin(i+1)*43758.5453123, 1.0)) * u) * amp
            amp *= 0.5; freq *= 2.0
        }
        return abs(v)
    }

    private func dropPath(cx: Double, cy: Double, w: Double, ht: Double, angle: Double) -> Path {
        Path { p in
            let ca = cos(angle), sa = sin(angle)
            func r(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: cx+dx*ca-dy*sa, y: cy+dx*sa+dy*ca) }
            p.move(to: r(0, ht*0.5))
            p.addCurve(to: r(0, -ht*0.5), control1: r(w*0.62, ht*0.22), control2: r(w*0.56, -ht*0.18))
            p.addCurve(to: r(0, ht*0.5), control1: r(-w*0.56, -ht*0.18), control2: r(-w*0.62, ht*0.22))
        }
    }

    // MARK: — 🌧 Rain Card

    private func cardRain(_ ctx: GraphicsContext, _ s: CGSize, _ t: Double, encre: Color, heavy: Bool) {
        let w = s.width, ht = s.height
        let windPhase = sin(t * 0.18) * 0.04
        let ang = 0.20 + windPhase

        // Brume atmosphérique
        for i in 0..<3 {
            let yy = Double(i) * ht * 0.35
            let drift = sin(t * 0.04 + Double(i) * 1.5) * 25
            let op = heavy ? 0.020 : 0.010
            ctx.fill(Path(CGRect(x: -10 + drift, y: yy - 20, width: w + 20, height: 40)),
                     with: .color(Color(red: 0.50, green: 0.62, blue: 0.78).opacity(op)))
        }

        // 3 couches de gouttes
        let layerConfigs: [(Int, Double, Double, Double)] = [
            (heavy ? 18 : 8,  0.50, 0.45, 0.35),  // lointain
            (heavy ? 40 : 18, 0.75, 0.70, 0.65),   // moyen
            (heavy ? 50 : 22, 1.00, 1.00, 1.00),   // proche
        ]
        for (li, cfg) in layerConfigs.enumerated() {
            let (cnt, spdMul, sizeMul, opMul) = cfg
            for i in 0..<cnt {
                let seed = Double(li * 5000 + i) * 1013 + 5
                let spd = (heavy ? 460.0 : 290.0) * spdMul
                let windCurve = sin(t * 0.25 + h(seed) * 6.28) * 2 * spdMul
                let x = fmod(seed*0.00141*w + t*spd*0.15 + windCurve, w + 30) - 15
                let y = fmod(seed*0.00283*ht + t*spd, ht + 25) - 12
                let dH = (heavy ? (10.0 + h(seed)*13) : (5.0 + h(seed)*8)) * sizeMul
                let dW = (heavy ? (0.9 + h(seed+1)*0.9) : 0.55) * sizeMul
                let op = (heavy ? (0.14 + h(seed+2)*0.18) : (0.07 + h(seed+2)*0.12)) * opMul

                let drop = dropPath(cx: x, cy: y+dH*0.3, w: dW, ht: dH, angle: ang)
                ctx.fill(drop, with: .color(Color(red: 0.58+Double(li)*0.04, green: 0.80+Double(li)*0.03, blue: 1).opacity(op)))

                // Motion blur
                if dH > 7 * sizeMul {
                    let trailLen = dH * 1.3
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: x-sin(ang)*trailLen, y: y-cos(ang)*trailLen))
                        p.addLine(to: CGPoint(x: x, y: y))
                    }, with: .color(encre.opacity(op*0.18)),
                       style: StrokeStyle(lineWidth: dW*0.4, lineCap: .round))
                }

                // Reflet spéculaire
                if dH > 12 * sizeMul && li >= 1 {
                    ctx.fill(Path(ellipseIn: CGRect(x: x+dW*0.2-0.4, y: y-dH*0.12-0.3, width: 0.8, height: 0.6)),
                             with: .color(encre.opacity(op*0.5)))
                }

                // Éclaboussures
                if li >= 1, y > ht-40, y < ht-3 {
                    let age = min(max(1.0 - (ht-y) / 37.0, 0), 1)
                    let sr = (2.5 + age*5) * sizeMul
                    ctx.stroke(Path(ellipseIn: CGRect(x: x-sr*1.3, y: ht-8-sr*0.28, width: sr*2.6, height: sr*0.56)),
                               with: .color(encre.opacity(age*0.11*opMul)), style: StrokeStyle(lineWidth: 0.6))
                    ctx.stroke(Path(ellipseIn: CGRect(x: x-sr*1.8, y: ht-8-sr*0.12, width: sr*3.6, height: sr*0.28)),
                               with: .color(encre.opacity(age*0.04*opMul)), style: StrokeStyle(lineWidth: 0.3))
                }
            }
        }

        // Flash orage
        if heavy {
            let fc = fmod(t*0.68, 8.0)
            var fOp = 0.0
            if fc < 0.035 { fOp = fc/0.035 * 0.18 }
            else if fc < 0.07 { fOp = 0.18 * (1-(fc-0.035)/0.035)*0.4 }
            else if fc < 0.10 { fOp = 0.07 * ((fc-0.07)/0.03) }
            else if fc < 0.18 { fOp = 0.07 * (1-(fc-0.10)/0.08) }
            if fOp > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: ht*0.5)),
                         with: .color(Color(red:0.82, green:0.88, blue:1).opacity(fOp)))
                ctx.fill(Path(CGRect(x: 0, y: ht*0.5, width: w, height: ht*0.5)),
                         with: .color(Color(red:0.82, green:0.88, blue:1).opacity(fOp*0.4)))
            }
        }
    }

    // MARK: — ❄️ Snow Card

    private func cardSnow(_ ctx: GraphicsContext, _ s: CGSize, _ t: Double, encre: Color) {
        let w = s.width, ht = s.height

        for i in 0..<28 {
            let seed = Double(i) * 1.618
            let tx = h(seed), ty = h(seed+1)
            let r = 1.5 + h(seed+2)*6.5
            let spd = 0.20 + h(seed+3)*0.78
            let op = 0.25 + h(seed+4)*0.48
            let ph = seed * 0.927
            let rot = h(seed+5) * (.pi * 2)
            let layer = i % 3
            let layerMul: [Double] = [0.42, 0.72, 1.0]

            let wb = sin(t*0.52+ph)*4.0 + cos(t*0.32+ph*1.7)*2.5
            let drift = sin(t*0.11+ph) * 5 * layerMul[layer]
            let x = fmod(tx*w + wb + drift + t*7*spd, w+16) - 8
            let y = fmod(ty*ht + t*(40+spd*22), ht+16) - 8
            let a = rot + t*0.11*spd + sin(t*0.28+ph)*0.2
            let finalOp = op * layerMul[layer]

            if r > 5.0 {
                // Grand flocon cristallin multi-passe
                var flake = Path()
                for arm in 0..<6 {
                    let ba = Double(arm) * (.pi/3) + a
                    flake.move(to: CGPoint(x: x, y: y))
                    flake.addLine(to: CGPoint(x: x+cos(ba)*r, y: y+sin(ba)*r))
                    for (frac, bLen) in [(0.28, r*0.34), (0.58, r*0.24)] {
                        let bx = x + cos(ba)*r*frac, by = y + sin(ba)*r*frac
                        for side in [-1.0, 1.0] {
                            let sb = ba + side * (.pi/3)
                            flake.move(to: CGPoint(x: bx, y: by))
                            flake.addLine(to: CGPoint(x: bx+cos(sb)*bLen, y: by+sin(sb)*bLen))
                        }
                    }
                }
                // Lueur
                ctx.stroke(flake, with: .color(Color(red:0.82, green:0.90, blue:1).opacity(finalOp*0.22)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                // Cristal
                ctx.stroke(flake, with: .color(encre.opacity(finalOp)),
                           style: StrokeStyle(lineWidth: 0.75, lineCap: .round, lineJoin: .round))
                // Noyau + scintillement
                ctx.fill(Path(ellipseIn: CGRect(x: x-r*0.15, y: y-r*0.15, width: r*0.3, height: r*0.3)),
                         with: .color(encre.opacity(finalOp*0.9)))
                let sparkle = 0.25 + sin(t*2.3+ph*3)*0.25
                ctx.fill(Path(ellipseIn: CGRect(x: x-1.2, y: y-1.2, width: 2.4, height: 2.4)),
                         with: .color(encre.opacity(sparkle*finalOp)))
            } else if r > 2.8 {
                // Flocon moyen
                var mini = Path()
                for arm in 0..<6 {
                    let ba = Double(arm)*(.pi/3) + a
                    mini.move(to: CGPoint(x: x, y: y))
                    mini.addLine(to: CGPoint(x: x+cos(ba)*r, y: y+sin(ba)*r))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: x-r*0.55, y: y-r*0.55, width: r*1.1, height: r*1.1)),
                         with: .color(encre.opacity(finalOp*0.05)))
                ctx.stroke(mini, with: .color(encre.opacity(finalOp)),
                           style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: x-1.2, y: y-1.2, width: 2.4, height: 2.4)),
                         with: .color(encre.opacity(finalOp)))
            } else {
                // Étoile scintillante
                let twinkle = 0.5 + sin(t*3.2+ph*5)*0.5
                var star = Path()
                for k in 0..<8 {
                    let sa = Double(k)/8.0*(.pi*2) + a
                    let rr = k%2==0 ? r : r*0.25
                    let pt = CGPoint(x: x+cos(sa)*rr, y: y+sin(sa)*rr)
                    k==0 ? star.move(to: pt) : star.addLine(to: pt)
                }
                star.closeSubpath()
                ctx.fill(star, with: .color(encre.opacity(finalOp*twinkle)))
            }
        }
    }

    // MARK: — ☀️ Sun Card

    private func cardSun(_ ctx: GraphicsContext, _ s: CGSize, _ t: Double, encre: Color) {
        let w = s.width, ht = s.height

        // Caustiques
        for row in 0..<5 {
            for col in 0..<7 {
                let bx = w*Double(col)/6.0, by = ht*Double(row)/4.0
                let phase = Double(col)*0.67 + Double(row)*1.13
                let dx = sin(t*0.52+phase)*15 + sin(t*0.3+phase*2.1)*6
                let dy = cos(t*0.43+phase*0.9)*11 + cos(t*0.24+phase*1.7)*4
                let cr = 2.0 + sin(t*0.8+phase)*1.8
                let st = 1.0 + sin(t*0.38+Double(col))*0.5
                let op = 0.025 + sin(t*0.6+phase*0.7)*0.014
                ctx.fill(Path(ellipseIn: CGRect(x: bx+dx-cr*st, y: by+dy-cr/st, width: cr*st*2, height: cr/st*2)),
                         with: .color(Color(red:1, green:0.96, blue:0.78).opacity(op)))
            }
        }

        // Bande lumineuse traversante
        let sweep = fmod(t * 30, w * 1.8) - w * 0.4
        var band = Path()
        band.move(to: CGPoint(x: sweep-32, y: 0))
        band.addLine(to: CGPoint(x: sweep+22, y: 0))
        band.addLine(to: CGPoint(x: sweep+65, y: ht))
        band.addLine(to: CGPoint(x: sweep+8, y: ht))
        band.closeSubpath()
        ctx.fill(band, with: .color(encre.opacity(0.048 + sin(t*0.4)*0.015)))

        // Halo coin
        for (r, op) in [(70.0, 0.035), (42.0, 0.058), (25.0, 0.088)] {
            let pulse = 1.0 + sin(t*0.50)*0.06
            ctx.fill(Path(ellipseIn: CGRect(x: w-r*pulse, y: -r*0.55*pulse, width: r*pulse*2, height: r*pulse*2)),
                     with: .color(Color(red:1, green:0.92, blue:0.70).opacity(op)))
        }

        // Lens flare + croix
        let fx = w*0.16 + sin(t*0.28)*12, fy = ht*0.21 + cos(t*0.21)*8
        ctx.fill(Path(ellipseIn: CGRect(x: fx-11, y: fy-6, width: 22, height: 12)),
                 with: .color(encre.opacity(0.055+sin(t*0.7)*0.028)))
        for a in [0.0, Double.pi/4, Double.pi/2, 3*Double.pi/4] {
            let fl = 22.0 + sin(t*0.5+a)*5
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: fx-cos(a)*fl, y: fy-sin(a)*fl))
                p.addLine(to: CGPoint(x: fx+cos(a)*fl, y: fy+sin(a)*fl))
            }, with: .color(encre.opacity(0.040)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }

        // Étoiles scintillantes
        for i in 0..<8 {
            let seed = Double(i)*137.5
            let sx = w*(0.08+Double(i)*0.12) + sin(t*0.25+seed)*10
            let sy = ht*(0.10+cos(Double(i)*2.0+t*0.18)*0.18)
            let sr = 1.8 + sin(t*1.0+seed)*1.8
            let op = 0.035 + sin(t*0.75+seed)*0.022
            var star = Path()
            for k in 0..<8 {
                let a = Double(k)/8.0*(.pi*2) + t*0.22 + seed
                let rr = k%2==0 ? sr : sr*0.28
                let pt = CGPoint(x: sx+cos(a)*rr, y: sy+sin(a)*rr)
                k==0 ? star.move(to: pt) : star.addLine(to: pt)
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(Color(red:1, green:0.97, blue:0.82).opacity(op)))
        }

        // Reflet bas ondulé
        var refl = Path()
        refl.move(to: CGPoint(x: 0, y: ht-11))
        var rpx = 0.0
        while rpx <= w { refl.addLine(to: CGPoint(x: rpx, y: ht-11 + sin(rpx*0.04+t*0.5)*2)); rpx += 5 }
        ctx.stroke(refl, with: .color(encre.opacity(0.055 + sin(t*0.33)*0.022)),
                   style: StrokeStyle(lineWidth: 1.1+sin(t*0.55)*0.4, lineCap: .round))
    }

    // MARK: — 💨 Wind Card

    private func cardWind(_ ctx: GraphicsContext, _ s: CGSize, _ t: Double, encre: Color) {
        let w = s.width, ht = s.height

        for i in 0..<14 {
            let seed = Double(i) * 199.7
            let yPos = ht * (0.05 + h(seed)*0.90)
            let xOff = fmod(t*(2.8+h(seed+1)*5.5) + seed*0.3, w*1.8) - w*0.4
            let len = 25.0 + h(seed+2)*75
            let op = 0.055 + h(seed+3)*0.13
            let amp = 2.0 + h(seed+4)*5.5

            // Courbe bezier double-ondulation
            var wind = Path()
            wind.move(to: CGPoint(x: xOff, y: yPos))
            wind.addCurve(to: CGPoint(x: xOff+len*0.5, y: yPos-amp*0.7),
                          control1: CGPoint(x: xOff+len*0.15, y: yPos-amp),
                          control2: CGPoint(x: xOff+len*0.35, y: yPos-amp*0.5))
            wind.addCurve(to: CGPoint(x: xOff+len, y: yPos),
                          control1: CGPoint(x: xOff+len*0.65, y: yPos-amp*0.9),
                          control2: CGPoint(x: xOff+len*0.85, y: yPos+amp*0.3))

            let lineW = 0.5 + h(seed+5)*0.8
            // Lueur
            ctx.stroke(wind, with: .color(encre.opacity(op*0.28)),
                       style: StrokeStyle(lineWidth: lineW+2.2, lineCap: .round))
            // Ligne
            ctx.stroke(wind, with: .color(encre.opacity(op)),
                       style: StrokeStyle(lineWidth: lineW, lineCap: .round))

            // Particules emportées
            if h(seed+6) > 0.4 {
                let px = xOff + len * h(seed+7)
                let py = yPos - amp * h(seed+8) + sin(t*1.5+seed)*2
                ctx.fill(Path(ellipseIn: CGRect(x: px-0.9, y: py-0.9, width: 1.8, height: 1.8)),
                         with: .color(encre.opacity(op*0.55)))
            }
        }
    }
}

// MARK: — Modificateur

extension View {
    func weatherEffect(condition: String) -> some View {
        overlay(CardWeatherEffect(condition: condition).allowsHitTesting(false))
    }
}
