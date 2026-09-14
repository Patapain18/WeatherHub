#include <metal_stdlib>
using namespace metal;

// ╔══════════════════════════════════════════════════════════════════╗
// ║  Ciel.metal — le ciel et ses intempéries, calculés pixel par     ║
// ║  pixel sur le GPU. Rien n'est « dessiné » : pour chaque pixel,   ║
// ║  la fonction répond « quelle couleur ici, à cet instant ? ».     ║
// ║  Les gouttes n'existent pas en mémoire : elles sont déduites de  ║
// ║  la position et du temps par une fonction de hachage.            ║
// ╚══════════════════════════════════════════════════════════════════╝

/// Ce que SwiftUI envoie à chaque image. Même disposition que la struct
/// Swift `UniformesCiel` — les float4 sont alignés sur 16 octets.
struct Uniformes {
    float2 resolution;   // pixels
    float  temps;        // secondes (ramenées sous 1 000 côté Swift)
    int    condition;    // 0 rien, 1 pluie, 2 bruine, 3 brouillard, 4 neige, 5 dégagé, 6 nuit dégagée, 7 nuages, 8 orage, 9 averse
                         // 10 tornade, 11 tempête, 12 grêle, 13 canicule, 14 grand froid, 15 poussière, 16 cyclone, 17 blizzard, 18 verglas, 19 déluge
    float  intensite;    // 0 → 1
    float  vent;         // inclinaison des traits, −1 → 1
    float  elevation;    // soleil, −1 → 1
    float2 soleil;       // position du soleil dans l'écran (uv), même formule que l'ancien ClearFX
    float  crepuscule;   // 1 pile au lever/coucher, 0 sinon
    float  eclat;        // soleil : bloom, trait et reflets (0,20 → 0,30 selon l'heure)
    float  disque;       // soleil : taille et chaleur du disque (2 = le réglage de Mathis)
    float4 encre;        // couleur des particules (blanc, ou sombre en thème clair)
    float4 haut;         // ciel en haut
    float4 bas;          // ciel en bas
};

struct SortieVertex {
    float4 position [[position]];
    float2 uv;
};

/// Un seul triangle qui déborde de l'écran : trois sommets, pas de
/// tampon. Le GPU ne garde que la partie visible.
vertex SortieVertex ciel_vertex(uint id [[vertex_id]]) {
    float2 p = float2(id == 1 ? 3.0 : -1.0, id == 2 ? 3.0 : -1.0);
    SortieVertex s;
    s.position = float4(p, 0, 1);
    s.uv = float2((p.x + 1) * 0.5, 1 - (p.y + 1) * 0.5);   // (0,0) en haut à gauche
    return s;
}

// ── Bruit ───────────────────────────────────────────────────────────

/// Un nombre « aléatoire » mais reproductible pour une cellule donnée :
/// même entrée, même sortie, à chaque image. C'est ce qui rend les
/// gouttes stables d'une image à l'autre.
float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// Bruit de valeur lissé, puis empilé en octaves (fbm) : des nappes
/// irrégulières, comme de la brume.
float bruit(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3 - 2 * f);
    return mix(mix(hash12(i), hash12(i + float2(1, 0)), f.x),
               mix(hash12(i + float2(0, 1)), hash12(i + float2(1, 1)), f.x), f.y);
}
float fbm(float2 p) {
    float v = 0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * bruit(p); p *= 2.03; a *= 0.5; }
    return v;
}

// ── Pluie ───────────────────────────────────────────────────────────

/// Une couche de traits : le plan est découpé en cellules ; chaque cellule
/// tire au sort si elle contient un trait, et où. `couche` > 1 = plus
/// loin : cellules plus grandes, traits plus fins, chute plus lente.
/// `largeur` et `longueur` règlent l'épaisseur et la part de cellule
/// occupée par le trait — c'est ce qui distingue la bruine de l'averse.
float pluie(float2 p, float t, float couche, float vent, float densite, float largeur, float longueur) {
    float2 taille = float2(0.035, 0.16) * couche;
    p.x += p.y * vent * 0.35;              // l'inclinaison due au vent
    p.y -= t * (1.6 / couche);            // la grille défile vers le bas
    float2 cellule = floor(p / taille), f = fract(p / taille);
    if (hash12(cellule) > densite) return 0;
    float x = 0.25 + 0.5 * hash12(cellule + 7.1);
    float trait = 1 - smoothstep(0.0, largeur / couche, abs(f.x - x));
    float l = smoothstep(0.0, 0.10, f.y) * smoothstep(0.85, 0.85 - longueur, f.y);
    return trait * l;
}

/// Au sol : des anneaux qui s'élargissent puis s'effacent, dans une bande
/// en bas de l'écran — l'impact des gouttes sur une flaque.
float eclabous(float2 p, float2 uv, float t, float densite) {
    if (uv.y < 0.86) return 0;
    float2 taille = float2(0.045, 0.05);
    float2 cellule = floor(p / taille), f = fract(p / taille) - 0.5;
    float r = hash12(cellule);
    if (r > densite) return 0;
    float phase = fract(t * (1.2 + r) + hash12(cellule + 3.3));
    float rayon = 0.05 + phase * 0.40;
    float d = length(f * float2(1.0, 2.2));
    float anneau = smoothstep(0.06, 0.0, abs(d - rayon));
    return anneau * (1 - phase) * (1 - phase);
}

/// D · La pluie fine d'ambiance (pluie et bruine) : peu de traits, fins
/// et lents, une brume douce, des ondes au sol. On la sent plus qu'on
/// ne la voit.
float3 pluieFine(float2 uv, float2 p, float t, float vent, float intensite, float3 ciel, float3 encre) {
    float dens = 0.2 + 0.3 * intensite;
    float r = pluie(p, t * 0.75, 1.2, vent * 0.6, dens, 0.03, 0.35) * 0.8
            + pluie(p + 3.7, t * 0.75, 2.0, vent * 0.6, dens, 0.035, 0.35) * 0.5;
    float3 c = ciel;
    float brume = fbm(p * 2.5 + float2(t * 0.03, t * 0.01));
    c = mix(c, encre, smoothstep(0.35, 0.8, brume) * 0.14 * intensite);
    c = mix(c, encre, clamp(r, 0.0, 1.0) * 0.30 * intensite);
    float ondes = eclabous(p, uv, t * 0.7, 0.35 * intensite + 0.1);
    return mix(c, encre, ondes * 0.25);
}

/// Au sol aussi : des gouttelettes qui rebondissent — par cellule, un
/// petit point qui remonte puis s'éteint (phase 0 → 1). Sert à l'averse
/// et aux grêlons.
float rebonds(float2 p, float2 uv, float t) {
    float2 g = fract(p * float2(28.0, 40.0)) - 0.5;
    float2 cellule = floor(p * float2(28.0, 40.0));
    float ph = fract(t * 2.0 + hash12(cellule));
    return smoothstep(0.12, 0.0, length(g - float2(0.0, -ph * 0.35)))
         * step(0.88, uv.y) * (1 - ph) * step(0.6, hash12(cellule + 2.0));
}

/// E · L'averse (averses et orages) : un rideau dense qui arrive par
/// vagues, des rafales qui couchent les traits, et au sol des impacts —
/// anneaux et gouttelettes qui rebondissent.
float3 averse(float2 uv, float2 p, float t, float vent, float intensite, float3 ciel, float3 encre) {
    float vague = 0.75 + 0.25 * sin(t * 0.35) * sin(t * 0.11 + 1.0);
    float rafale = vent * (0.7 + 0.6 * vague) + 0.12 * sin(t * 0.9);
    float dens = (0.55 + 0.45 * intensite) * vague;
    float r = pluie(p, t * 1.15, 0.9, rafale, dens, 0.05, 0.5) * 1.0
            + pluie(p + 3.7, t * 1.15, 1.5, rafale, dens, 0.06, 0.5) * 0.65
            + pluie(p + 9.1, t * 1.15, 2.3, rafale, dens, 0.07, 0.45) * 0.4;
    float3 c = ciel * (1 - 0.10 * vague * intensite);
    c = mix(c, encre, clamp(r, 0.0, 1.0) * 0.40 * intensite);
    float imp = eclabous(p, uv, t * 1.6, 0.6 * intensite + 0.2);
    return mix(c, encre, (imp * 0.35 + rebonds(p, uv, t) * 0.6) * intensite);
}

// ── Beau temps, nuit, nuages ────────────────────────────────────────

/// Le soleil « photographique », réglé par Mathis sur la maquette :
/// un disque doré deux fois plus grand que le trait de départ, plus chaud
/// vers son bord (le limbe), une lueur collée à lui, et un éclat discret
/// — bloom, trait horizontal, chaîne de reflets vers le centre — qui
/// varie avec l'heure (0,20 le matin, 0,25 à midi, 0,30 l'après-midi,
/// 0,20 au coucher : voir `eclatSoleil` côté Swift).
float3 beauTemps(float2 p, float aspect, float t, float2 soleil, float crepuscule, float eclat, float disqueF, float3 ciel) {
    float2 ps = float2(soleil.x * aspect, soleil.y);
    float d = distance(p, ps);
    float3 chaud = mix(float3(1.0, 0.94, 0.74), float3(1.0, 0.60, 0.28), crepuscule);
    float3 c = ciel;
    // Éclat : le bloom, le trait et les reflets ; Soleil : la taille et la chaleur du disque
    float bloom = (exp(-d * 3.2) * 0.5 + exp(-d * 14.0) * 0.7) * eclat;
    float rayon = 0.040 * disqueF;
    float disque = smoothstep(rayon * 1.12, rayon * 0.88, d);                 // bord un peu doux
    float limbe = smoothstep(rayon * 0.15, rayon, d);                          // plus chaud vers le bord
    float3 couleurDisque = mix(float3(1.0, 0.96, 0.80), chaud * 0.96, limbe * 0.85 * min(disqueF, 1.5));
    float couronne = exp(-max(0.0, d - rayon) * 38.0) * 0.32 * disqueF;       // la lueur collée au disque
    float trait = exp(-abs(p.y - ps.y) * 45.0) * exp(-abs(p.x - ps.x) * 1.8) * 0.45 * eclat;
    c += chaud * (bloom + trait + couronne) + couleurDisque * disque * (0.55 + 0.45 * eclat);
    // Les reflets : sur la droite soleil → centre de l'écran, à des fractions fixes, chacun sa teinte
    float2 centre = float2(0.5 * aspect, 0.5), axe = centre - ps;
    float ts[6] = {0.22, 0.38, 0.55, 0.72, 0.95, 1.35};
    float rs[6] = {0.020, 0.045, 0.030, 0.075, 0.040, 0.110};
    float3 cols[6] = {float3(1.0, 0.8, 0.5), float3(0.5, 0.9, 1.0), float3(1.0, 0.6, 0.7),
                      float3(0.6, 1.0, 0.7), float3(1.0, 0.9, 0.5), float3(0.6, 0.7, 1.0)};
    for (int i = 0; i < 6; i++) {
        float2 pos = ps + axe * ts[i];
        float dd = distance(p, pos);
        float anneau = smoothstep(rs[i], rs[i] * 0.75, dd) * (i == 5 ? 0.35 : 1.0);
        float bord = smoothstep(rs[i] * 0.85, rs[i], dd) * smoothstep(rs[i] * 1.05, rs[i], dd);
        c += cols[i] * (anneau * 0.06 + bord * 0.10) * (1.0 - crepuscule * 0.4) * (0.4 + 0.6 * eclat);
    }
    return c;
}

/// La nuit : des étoiles qui scintillent, une lune en haut à droite.
float3 nuit(float2 uv, float2 p, float aspect, float t, float3 ciel) {
    float3 c = ciel;
    float2 g = p * 70.0;
    float2 cellule = floor(g), f = fract(g);
    float r = hash12(cellule);
    if (r > 0.94 && uv.y < 0.88) {
        float2 centre = float2(hash12(cellule + 1.3), hash12(cellule + 4.1));
        float d = length(f - centre);
        float scint = 0.55 + 0.45 * sin(t * (1.0 + hash12(cellule + 7.7) * 2.5) + r * 40.0);
        c += float3(1.0) * smoothstep(0.22, 0.0, d) * scint * (0.35 + 0.65 * hash12(cellule + 2.2));
    }
    float2 lune = float2(0.86 * aspect, 0.13);
    float d = distance(p, lune);
    c += float3(0.80, 0.86, 1.0) * exp(-d * 9.0) * 0.45;                       // le halo
    float disque = smoothstep(0.042, 0.036, d);
    float3 surface = float3(0.93, 0.95, 1.0);
    surface -= 0.18 * smoothstep(0.012, 0.004, distance(p, lune + float2(-0.012, -0.008)));   // les mers
    surface -= 0.14 * smoothstep(0.010, 0.003, distance(p, lune + float2(0.011, 0.009)));
    return mix(c, surface, disque);
}

/// Les nuages : deux nappes de bruit qui dérivent à des vitesses
/// différentes ; le dessous des nuages est plus sombre que le dessus.
float3 nuages(float2 p, float t, float3 ciel, float3 encre, float intensite) {
    float n1 = fbm(p * 1.5 + float2(t * 0.018, 0.0));
    float n2 = fbm(p * 3.1 + float2(-t * 0.03, 3.1));
    float dens = smoothstep(0.40, 0.74, n1 * 0.7 + n2 * 0.3);
    float3 clair = mix(encre, ciel, 0.5);
    float3 c = mix(ciel, clair, dens * 0.5 * intensite);
    float ombre = smoothstep(0.55, 0.95, n1) * dens;
    return mix(c, ciel * 0.72, ombre * 0.45 * intensite);
}

// ── Neige ───────────────────────────────────────────────────────────

/// La neige « scintillante » choisie par Mathis (préréglage I de l'atelier) :
/// des flocons mi-ronds mi-cristaux, qui tremblent en tombant sur trois
/// couches de profondeur, et qui attrapent la lumière — chacun s'allume
/// brièvement, comme sous un lampadaire.
float formeFlocon(float2 v, float r, float rot) {
    float d = length(v);
    float rond = smoothstep(r, r * 0.3, d);
    float a = atan2(v.y, v.x) + rot;
    float branches = pow(abs(cos(3.0 * a)), 6.0);              // six pointes
    float sous = pow(abs(cos(3.0 * a + 0.52)), 30.0) * 0.5;    // six petites pointes secondaires
    float fr = r * (0.28 + 0.72 * branches + sous);
    float cristal = max(smoothstep(fr, fr * 0.7, d), smoothstep(r * 0.28, r * 0.14, d));
    return mix(rond, cristal, 0.5);                            // forme 0,5 : moitié rond, moitié cristal
}

/// Une couche de flocons ; k = 1 la plus proche. Quantité 0,7, taille 1,1,
/// vitesse 0,2, tremblement 1, flou 0,02 devant — la recette de la maquette.
float coucheNeige(float2 p, float t, float k, float vent, float quantite) {
    float prof = 1.0 + (k - 1.0) * 0.6;                         // plus loin = cellules plus grandes, chute plus lente
    float2 q = p;
    q.x += q.y * vent * 0.5 + t * vent * 0.12 / prof;
    q.y -= t * (0.2 / prof);
    float2 g = q / (float2(0.07) * prof * 1.1);
    float2 id = floor(g), f = fract(g);
    float n = hash12(id);
    if (n > clamp(quantite * 0.55, 0.0, 0.95)) return 0;
    float2 centre = float2(0.5) + 0.2 * (float2(hash12(id + 3.3), hash12(id + 9.1)) - 0.5);
    centre.x += sin(t * (0.6 + hash12(id + 2.2)) + n * 6.28) * 0.15;
    float r = min(0.40, 0.09 + (k == 1.0 ? 0.02 : 0.005));      // un rayon borné : jamais plus grand que sa cellule
    float rot = t * (hash12(id + 7.7) - 0.5) * 1.2;
    float fl = formeFlocon(f - centre, r, rot);
    // Le scintillement : une impulsion brève et aléatoire par flocon
    float sc = 0.35 + 1.6 * pow(0.5 + 0.5 * sin(t * (2.0 + n * 3.0) + n * 40.0), 6.0);
    return fl * sc;
}

float neige(float2 p, float t, float vent, float intensite) {
    float total = 0;
    for (int i = 1; i <= 3; i++) {
        float k = float(i);
        total += coucheNeige(p + k * 2.9, t, k, vent, 0.7 * intensite) * pow(0.72, k - 1.0);
    }
    return clamp(total, 0.0, 1.0);
}

// ── Régimes extrêmes ────────────────────────────────────────────────
//  Dix régimes, bâtis avec les briques choisies plus haut — l'averse E,
//  la pluie fine D, la neige I, le soleil photographique — plus trois
//  briques à eux : les rafales, les grêlons et le givre. Tout souffle
//  vers la gauche, comme la pluie et la neige (le vent vient de droite).

/// Le vent rendu visible : de longues traînées presque horizontales qui
/// filent de droite à gauche. Même principe que la pluie, mais la cellule
/// est couchée (large 0,34, basse 0,028) et c'est vers la gauche que la
/// grille défile. `pente` : les traînées descendent un peu en avançant.
float rafales(float2 p, float t, float vitesse, float densite, float pente, float epaisseur) {
    float2 q = p;
    q.y += q.x * pente;
    q.x += t * vitesse;
    float2 taille = float2(0.34, 0.028);
    float2 cellule = floor(q / taille), f = fract(q / taille);
    if (hash12(cellule) > densite) return 0;
    float y0 = 0.2 + 0.6 * hash12(cellule + 5.3);
    float longueur = 0.3 + 0.5 * hash12(cellule + 8.8);
    float x0 = hash12(cellule + 1.7) * (1 - longueur);
    float trait = 1 - smoothstep(0.0, epaisseur, abs(f.y - y0));
    float l = smoothstep(x0, x0 + 0.08, f.x) * smoothstep(x0 + longueur, x0 + longueur - 0.15, f.x);
    return trait * l * (0.4 + 0.6 * hash12(cellule + 2.9));
}

/// Les grêlons : des billes opaques qui tombent vite, presque droit, avec
/// un léger tremblement. Retourne (bille, reflet) : le reflet, c'est ce
/// qui fait la bille et pas le flocon. `couche` > 1 : plus loin, plus
/// petit, plus lent.
float2 grelons(float2 p, float t, float couche, float vent) {
    float2 taille = float2(0.05, 0.075) * couche;
    float2 q = p;
    q.x += q.y * vent * 0.12;
    q.y -= t * (1.9 / couche);
    float2 cellule = floor(q / taille), f = fract(q / taille);
    float n = hash12(cellule);
    if (n > 0.55) return float2(0);
    float2 centre = float2(0.5) + 0.3 * (float2(hash12(cellule + 3.3), hash12(cellule + 9.1)) - 0.5);
    centre.x += sin(t * 0.6 + n * 6.28) * 0.08;
    float2 d = (f - centre) * taille;                        // en unités d'écran : des billes rondes
    float r = (0.0018 + 0.0027 * hash12(cellule + 4.4)) / couche;
    float bille = smoothstep(r, r * 0.55, length(d));
    // La traînée : la même bille, étirée vers le haut — le flou de la vitesse
    float dy = d.y < 0.0 ? -d.y * 0.3 : d.y;                 // au-dessus de la bille, la distance compte 3× moins
    float trainee = smoothstep(r, r * 0.3, length(float2(d.x, dy)));
    bille = max(bille, trainee * 0.30);
    float reflet = smoothstep(r * 0.5, 0.0, length(d - float2(-0.3, -0.35) * r));
    return float2(bille, reflet * bille);
}

/// Du givre dans les quatre coins de la fenêtre : un halo blanc bleuté.
float3 givre(float3 c, float2 p, float aspect, float force) {
    float g = pow(smoothstep(0.34, 0.0, distance(p, float2(0.0, 0.0))), 1.5)
            + pow(smoothstep(0.34, 0.0, distance(p, float2(aspect, 0.0))), 1.5)
            + pow(smoothstep(0.34, 0.0, distance(p, float2(0.0, 1.0))), 1.5)
            + pow(smoothstep(0.34, 0.0, distance(p, float2(aspect, 1.0))), 1.5);
    return mix(c, float3(0.85, 0.92, 1.0), clamp(g, 0.0, 1.0) * force);
}

/// Tornade : l'averse couchée par le vent, un plafond nuageux qui pèse,
/// et l'entonnoir — seul, sans débris ni poussière (choix de Mathis).
/// L'entonnoir est un cylindre vu de face : à chaque hauteur f (0 au
/// plafond, 1 au sol), un centre qui se balance et se tord, un rayon qui
/// se rétrécit. Les stries sont posées sur l'angle asin(dx / r) : elles
/// défilent vite au centre et lentement aux bords — c'est ce qui fait
/// tourner le cylindre.
float3 tornade(float2 uv, float2 p, float aspect, float t, float vent, float3 ciel, float3 encre) {
    float3 c = averse(uv, p, t, vent * 1.6, 1.0, ciel, encre);
    c *= 1.0 - 0.42 * smoothstep(0.24, 0.0, uv.y);                            // le plafond
    float f = clamp((uv.y - 0.15) / 0.78, 0.0, 1.0);
    // À 80 % de la largeur : dans la bande libre à droite des tuiles sur
    // une fenêtre large, au-dessus d'elles sur une fenêtre étroite.
    float baseX = 0.80 * aspect + sin(t * 0.21) * 0.033;
    float cx = baseX + sin(f * 3.2 + t * 0.9) * 0.035 * f
             + (fbm(float2(t * 0.3 + f * 4.0, 1.7)) - 0.5) * 0.05 * f;
    float r = (0.14 * (1 - f) * (1 - f) + 0.019) * (1 + sin(t * 3.0 + f * 9.0) * 0.06);
    float dx = (p.x - cx) / r;
    float dedans = smoothstep(1.0, 0.85, abs(dx)) * smoothstep(0.12, 0.17, uv.y) * smoothstep(0.95, 0.91, uv.y);
    float ombre = sqrt(max(0.0, 1.0 - dx * dx));                              // plus clair au centre du cylindre
    float theta = asin(clamp(dx, -1.0, 1.0));
    float stries = pow(0.5 + 0.5 * sin(theta * 3.0 + t * 4.0 + f * 9.0), 2.0);
    // Un gris moyen : plus clair que le ciel d'orage sombre, plus sombre
    // que le ciel vert-gris du thème clair — lisible dans les deux cas
    float fumee = 0.85 + 0.30 * fbm(float2(theta * 2.0, uv.y * 8.0 - t * 0.8));   // la texture qui monte et tourne
    float3 gris = float3(0.34, 0.34, 0.36) * (0.55 + 0.45 * ombre) * fumee;
    c = mix(c, gris, dedans * (0.70 + f * 0.25));
    c = mix(c, float3(0.62), dedans * stries * ombre * (0.10 + 0.18 * f));
    return c;
}

/// Tempête : l'averse fouettée par le vent, et le vent lui-même rendu
/// visible — deux couches de traînées, la plus lointaine plus fine.
float3 tempete(float2 uv, float2 p, float t, float vent, float3 ciel, float3 encre) {
    float3 c = averse(uv, p, t, vent * 1.4 + 0.3, 1.0, ciel, encre);
    float v = rafales(p, t, 1.1, 0.5, 0.14, 0.06) + rafales(p + 4.3, t, 1.6, 0.35, 0.14, 0.05) * 0.7;
    return mix(c, encre, clamp(v, 0.0, 1.0) * 0.20);
}

/// Grêle : une brume froide en haut, comme sous un cumulonimbus, deux
/// couches de grêlons, et au sol les billes qui rebondissent.
float3 grele(float2 uv, float2 p, float t, float vent, float3 ciel, float3 encre) {
    float3 c = mix(ciel, float3(1.0), 0.06 * smoothstep(0.3, 0.0, uv.y));
    float2 b1 = grelons(p, t, 1.0, vent), b2 = grelons(p + 2.7, t, 1.5, vent);
    c = mix(c, encre, clamp(b1.x + b2.x * 0.7, 0.0, 1.0) * 0.85);
    c = mix(c, float3(1.0), clamp(b1.y + b2.y * 0.5, 0.0, 1.0) * 0.5);
    return mix(c, encre, rebonds(p, uv, t) * 0.6);
}

/// Canicule : le soleil photographique, un peu plus éclatant (la nuit,
/// les étoiles), puis l'air qui tremble — des ondulations
/// serrées sur la moitié basse — et une brume orangée qui monte du sol.
float3 canicule(float2 uv, float2 p, float aspect, float t, float elevation, float2 soleil,
                float crepuscule, float eclat, float disque, float3 ciel) {
    float3 c = elevation <= 0.0 ? nuit(uv, p, aspect, t, ciel)
                                : beauTemps(p, aspect, t, soleil, crepuscule, eclat + 0.05, disque, ciel);
    float onde = sin(p.x * 43.0 + t * 3.2 + uv.y * 24.0) * 0.6 + sin(p.x * 95.0 - t * 2.1) * 0.4;
    float lignes = pow(0.5 + 0.5 * sin(uv.y * 167.0 + onde * 0.45), 24.0);
    c += float3(1.0, 0.90, 0.70) * lignes * 0.06 * smoothstep(0.36, 0.48, uv.y);
    return mix(c, float3(1.0, 0.55, 0.15), 0.16 * smoothstep(0.55, 1.0, uv.y));
}

/// Grand froid : un soleil pâle (ou les étoiles), du givre dans les coins,
/// l'air qui scintille de cristaux en suspension — ils brillent plus qu'ils
/// ne bougent — et quelques flocons fins qui tombent sans hâte.
float3 grandFroid(float2 uv, float2 p, float aspect, float t, float elevation, float vent,
                  float2 soleil, float crepuscule, float3 ciel, float3 encre) {
    float3 c = elevation <= 0.0 ? nuit(uv, p, aspect, t, ciel)
                                : beauTemps(p, aspect, t, soleil, crepuscule, 0.14, 1.6, ciel);
    c = givre(c, p, aspect, 0.14);
    float2 q = p + float2(sin(t * 0.15) * 0.007, -t * 0.008);
    float2 cellule = floor(q / 0.035), f = fract(q / 0.035);
    float n = hash12(cellule);
    if (n < 0.55) {
        float2 centre = float2(0.15) + 0.7 * float2(hash12(cellule + 1.1), hash12(cellule + 2.2));
        float sc = max(0.0, sin(t * (1.5 + n * 2.0) + hash12(cellule + 3.3) * 6.28));
        float r = 0.025 + 0.045 * hash12(cellule + 4.4);
        float pt = smoothstep(r, r * 0.3, length(f - centre));
        c = mix(c, encre, pt * (0.15 + sc * 0.6));
    }
    // Des flocons fins : la neige I sur une grille trois fois plus serrée
    float fl = coucheNeige(p * 3.0 + 11.0, t * 0.5, 1.0, vent * 0.5, 0.08);
    return mix(c, encre, fl * 0.7);
}

/// Tempête de poussière : la brume du brouillard, mais ocre, et des grains
/// allongés qui filent à l'horizontale.
float grains(float2 p, float t, float vitesse) {
    float2 taille = float2(0.06, 0.016);
    float2 q = p;
    q.x += t * vitesse;
    float2 cellule = floor(q / taille), f = fract(q / taille);
    if (hash12(cellule) > 0.5) return 0;
    float2 centre = float2(0.2 + 0.6 * hash12(cellule + 1.3), 0.3 + 0.4 * hash12(cellule + 2.6));
    float r = 0.05 + 0.12 * hash12(cellule + 4.1);
    return smoothstep(r, r * 0.3, length(f - centre)) * (0.3 + 0.7 * hash12(cellule + 5.5));
}
float3 poussiere(float2 p, float t, float3 ciel) {
    float3 ocre = float3(0.85, 0.70, 0.45);
    float f1 = fbm(p * 2.2 + float2(t * 0.09, t * 0.012));
    float f2 = fbm(p * 5.0 - float2(t * 0.15, t * 0.02) + 4.7);
    float brume = smoothstep(0.30, 0.85, f1 * 0.65 + f2 * 0.35);
    float3 c = mix(ciel, ocre, brume * 0.38);
    float g = grains(p, t, 0.5) + grains(p + 3.1, t, 0.8) * 0.7;
    return mix(c, ocre, clamp(g, 0.0, 1.0) * 0.32);
}

/// Cyclone : l'averse fouettée, les bandes spiralées qui tournent autour
/// d'un œil hors champ (en haut à droite), et un vent deux fois plus dense
/// qu'en tempête. La spirale d'Archimède : le rayon et l'angle avancent
/// ensemble, sin(2π(4,3 r − a/2π)) — 4,3 tours de bande par unité de rayon.
float3 cyclone(float2 uv, float2 p, float aspect, float t, float vent, float3 ciel, float3 encre) {
    float3 c = averse(uv, p, t, vent * 1.5 + 0.4, 1.0, ciel, encre);
    float2 d = p - float2(0.88 * aspect, 0.06);
    float r = length(d), a = atan2(d.y, d.x);
    float spirale = 0.5 + 0.5 * sin(6.2832 * (r * 4.3 - a / 6.2832) + t * 0.35);
    float bande = smoothstep(0.35, 0.75, spirale + (fbm(p * 3.0 + t * 0.05) - 0.5) * 0.9);
    float3 clair = mix(encre, ciel, 0.5);                                     // la couleur des nuages
    c = mix(c, clair, 0.24 * bande * smoothstep(0.06, 0.25, r));
    float v = rafales(p, t, 1.4, 0.7, 0.18, 0.07) + rafales(p + 4.3, t, 1.9, 0.5, 0.18, 0.06) * 0.7;
    return mix(c, encre, clamp(v, 0.0, 1.0) * 0.24);
}

/// Blizzard : le voile blanc du brouillard, la neige scintillante deux fois
/// plus rapide et couchée par le vent, et les traînées du vent — on ne
/// voit plus rien.
float3 blizzard(float2 p, float t, float vent, float3 ciel, float3 encre) {
    float f1 = fbm(p * 2.2 + float2(t * 0.12, t * 0.02));
    float f2 = fbm(p * 5.0 - float2(t * 0.2, t * 0.03) + 4.7);
    float voile = smoothstep(0.30, 0.85, f1 * 0.65 + f2 * 0.35);
    float3 c = mix(ciel, float3(1.0), 0.10 + voile * 0.30);
    c = mix(c, encre, neige(p * 1.5, t * 2.2, 2.0 + vent * 2.0, 1.0) * 0.85);   // grille resserrée : flocons plus fins
    float v = rafales(p, t, 1.2, 0.6, 0.10, 0.08) + rafales(p + 7.7, t, 1.7, 0.45, 0.10, 0.06) * 0.6;
    return mix(c, float3(1.0), clamp(v, 0.0, 1.0) * 0.28);
}

/// Pluie verglaçante : la pluie fine, du givre qui gagne les coins, et en
/// bas le sol qui luit — la glace, c'est de la pluie qui brille.
float3 verglas(float2 uv, float2 p, float aspect, float t, float vent, float3 ciel, float3 encre) {
    float3 c = pluieFine(uv, p, t, vent, 0.8, ciel, encre);
    c = givre(c, p, aspect, 0.16);
    // Le sol glacé : une lueur pâle en bas, des flaques de lumière qui
    // glissent lentement, et quelques reflets fins
    float bande = smoothstep(0.78, 1.0, uv.y);
    float lueur = pow(bruit(float2(p.x * 9.0 + t * 0.15, uv.y * 30.0)), 2.0);
    float miroir = pow(0.5 + 0.5 * sin(uv.y * 120.0 + sin(p.x * 3.0 + t * 0.8) * 1.2), 8.0);
    return mix(c, float3(0.85, 0.92, 1.0), bande * (0.08 + lueur * 0.18 + miroir * 0.06));
}

/// Déluge : l'averse, plus une seconde pluie décalée dans le temps (deux
/// fois plus de traits), et l'eau qui monte — une nappe bleutée dont la
/// surface ondule, piquée d'impacts qui s'élargissent.
float3 deluge(float2 uv, float2 p, float t, float vent, float3 ciel, float3 encre) {
    float3 c = averse(uv, p, t, vent, 1.0, ciel, encre);
    float r = pluie(p + 1.3, (t + 37.3) * 1.15, 1.0, vent, 0.9, 0.05, 0.5)
            + pluie(p + 5.9, (t + 37.3) * 1.15, 1.7, vent, 0.9, 0.06, 0.5) * 0.6;
    c = mix(c, encre, clamp(r, 0.0, 1.0) * 0.35);
    float niveau = 0.90 + sin(t * 0.6) * 0.0025 + sin(p.x * 26.0 + t * 1.6) * 0.0035 + sin(p.x * 60.0 - t * 2.3) * 0.0017;
    float eau = smoothstep(niveau, niveau + 0.004, uv.y);
    float prof = clamp((uv.y - niveau) / (1.0 - niveau), 0.0, 1.0);
    float3 teinte = mix(float3(0.55, 0.70, 0.90), float3(0.30, 0.45, 0.70), prof);
    c = mix(c, teinte, eau * mix(0.22, 0.10, prof));
    // Les impacts à la surface : une cellule par tranche de largeur, un
    // anneau qui grandit puis s'efface
    float id = floor(p.x / 0.045);
    float ph = fract(t * (0.8 + 0.6 * hash12(float2(id, 1.0))) + hash12(float2(id, 2.0)) * 3.0);
    float cx = (id + 0.15 + 0.7 * hash12(float2(id, 3.0))) * 0.045;
    float dd = length((p - float2(cx, niveau)) * float2(1.0, 4.0));
    float anneau = smoothstep(0.0025, 0.0, abs(dd - (0.003 + ph * 0.02))) * (1 - ph) * 0.35;
    return mix(c, float3(1.0), anneau);
}

// ── Le pixel ────────────────────────────────────────────────────────

fragment float4 ciel_fragment(SortieVertex in [[stage_in]], constant Uniformes& u [[buffer(0)]]) {
    float2 uv = in.uv;
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);     // repère « carré », pour des gouttes non déformées
    float3 encre = u.encre.rgb;

    // Le ciel : un dégradé
    float3 ciel = mix(u.haut.rgb, u.bas.rgb, clamp(uv.y, 0.0, 1.0));
    float3 c = ciel;

    if (u.condition == 1 || u.condition == 2) {
        c = pluieFine(uv, p, u.temps, u.vent, u.intensite, ciel, encre);      // pluie, bruine
    } else if (u.condition == 8 || u.condition == 9) {
        c = averse(uv, p, u.temps, u.vent, u.intensite, ciel, encre);         // averse, orage
    } else if (u.condition == 5) {
        c = beauTemps(p, aspect, u.temps, u.soleil, u.crepuscule, u.eclat, u.disque, ciel);
    } else if (u.condition == 6) {
        c = nuit(uv, p, aspect, u.temps, ciel);
    } else if (u.condition == 7) {
        c = nuages(p, u.temps, ciel, encre, u.intensite);
    } else if (u.condition == 3) {
        float f1 = fbm(p * 2.2 + float2(u.temps * 0.045, u.temps * 0.012));
        float f2 = fbm(p * 5.0 - float2(u.temps * 0.075, u.temps * 0.02) + 4.7);
        float brume = smoothstep(0.30, 0.85, f1 * 0.65 + f2 * 0.35);
        c = mix(c, encre, brume * 0.38 * u.intensite);
    } else if (u.condition == 4) {
        c = mix(c, encre, neige(p, u.temps, u.vent, u.intensite) * 0.88);
    // Les régimes extrêmes
    } else if (u.condition == 10) {
        c = tornade(uv, p, aspect, u.temps, u.vent, ciel, encre);
    } else if (u.condition == 11) {
        c = tempete(uv, p, u.temps, u.vent, ciel, encre);
    } else if (u.condition == 12) {
        c = grele(uv, p, u.temps, u.vent, ciel, encre);
    } else if (u.condition == 13) {
        c = canicule(uv, p, aspect, u.temps, u.elevation, u.soleil, u.crepuscule, u.eclat, u.disque, ciel);
    } else if (u.condition == 14) {
        c = grandFroid(uv, p, aspect, u.temps, u.elevation, u.vent, u.soleil, u.crepuscule, ciel, encre);
    } else if (u.condition == 15) {
        c = poussiere(p, u.temps, ciel);
    } else if (u.condition == 16) {
        c = cyclone(uv, p, aspect, u.temps, u.vent, ciel, encre);
    } else if (u.condition == 17) {
        c = blizzard(p, u.temps, u.vent, ciel, encre);
    } else if (u.condition == 18) {
        c = verglas(uv, p, aspect, u.temps, u.vent, ciel, encre);
    } else if (u.condition == 19) {
        c = deluge(uv, p, u.temps, u.vent, ciel, encre);
    }
    return float4(c, 1);
}
