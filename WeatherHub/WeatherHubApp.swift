import SwiftUI

@main
struct WeatherHubApp: App {

    // Persisté dans UserDefaults
    @AppStorage("appearanceMode") private var appearanceMode: String = "dark"

    /// Un seul modèle pour la fenêtre ET la barre de menus.
    @StateObject private var vm = WeatherViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .frame(minWidth: 800, minHeight: 600)
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        // ── Barre de menus ──────────────────────────────────────────
        //
        // L'usage courant d'une app météo, c'est un coup d'œil, pas une
        // fenêtre à ouvrir. `MenuBarExtra` affiche la température en
        // permanence en haut de l'écran ; le menu déroulant donne
        // l'essentiel sans quitter ce qu'on est en train de faire.
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.city.capitalized).font(.headline)
                Text(vm.state.condition).font(.caption).foregroundColor(.secondary)
                Divider()
                if vm.state.modelCount > 1 {
                    Text(vm.uncertaintyString).font(.caption2).foregroundColor(.secondary)
                }
                if let comparaison = vm.comparaisonHier {
                    Text(comparaison).font(.caption2).foregroundColor(.secondary)
                }
                if let pluie = vm.prochainePluie {
                    Text("Pluie dans \(pluie.minutes) min").font(.caption).foregroundColor(.blue)
                }
                if let alerte = vm.alertes.first(where: { $0.niveau >= .danger }) {
                    Text("⚠︎ \(alerte.titre)").font(.caption).foregroundColor(.orange)
                }
                Divider()
                Button("Actualiser") { vm.refresh() }
                Button("Quitter") { NSApplication.shared.terminate(nil) }
            }
            .padding(10)
            .frame(width: 220)
        } label: {
            // Le libellé reste court : la barre de menus est un espace
            // partagé, une app météo n'a pas à y prendre toute la place.
            Text(vm.state.condition.isEmpty ? "—" : "\(Int(vm.state.temperature))°")
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil  // "system" → suit le système
        }
    }
}
