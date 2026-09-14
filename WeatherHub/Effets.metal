#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ╔══════════════════════════════════════════════════════════════════╗
// ║  Effets Metal — le GPU prend le relais du Canvas                 ║
// ║  Un shader de déformation reçoit la position d'un pixel et       ║
// ║  renvoie d'où il faut aller chercher sa couleur. C'est tout.     ║
// ╚══════════════════════════════════════════════════════════════════╝

/// Chaleur : l'air qui tremble au-dessus du bitume.
/// Deux sinus qui glissent dans le temps décalent chaque pixel de
/// quelques points ; l'amplitude grandit vers le bas, là où le sol
/// chauffe, et reste presque nulle en haut (le texte du haut se lit).
///
/// `position`  : le pixel en cours, en points
/// `temps`     : les secondes, pour faire bouger les ondes
/// `taille`    : la taille de la vue, pour savoir où est « le bas »
/// `intensite` : 0 = rien, 1 = canicule
[[ stitchable ]] float2 chaleur(float2 position, float temps, float2 taille, float intensite) {
    float y = position.y / taille.y;                        // 0 en haut, 1 en bas
    float force = intensite * (0.15 + 0.85 * y * y);        // quadratique : discret en haut, net en bas
    float dx = sin(position.y * 0.045 + temps * 3.1) * 2.8
             + sin(position.y * 0.110 - temps * 2.3 + position.x * 0.010) * 1.4;
    float dy = sin(position.x * 0.050 + temps * 2.6) * 1.2;
    return position + float2(dx, dy) * force;
}
