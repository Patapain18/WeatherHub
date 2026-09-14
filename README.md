# WeatherHub — Guide de compilation

## Prérequis
- Mac avec macOS 13 ou supérieur
- Xcode 15 ou supérieur (gratuit sur l'App Store)

---

## Ouvrir le projet

Double-cliquer sur `WeatherHub.xcodeproj`
→ Xcode s'ouvre automatiquement avec tous les fichiers chargés.

---

## Compiler et lancer (le plus simple)

1. En haut à gauche de Xcode, sélectionner la cible : **"My Mac"**
2. Appuyer sur ▶ (ou `Cmd + R`)
3. L'app se lance immédiatement

---

## Créer un .app distribuable

### Méthode 1 — Copie rapide (pour usage personnel)
```
Product → Build (Cmd+B)
```
Puis dans le menu :
```
Product → Show Build Folder in Finder
```
Aller dans `Products/Release/` → `WeatherHub.app` est prêt.

### Méthode 2 — Archive (pour partager)
1. `Product → Archive`
2. Dans l'Organizer : `Distribute App → Copy App`
3. Choisir un dossier → `WeatherHub.app` est exporté

---

## Résolution des problèmes fréquents

### "Signing requires a development team"
→ Aller dans `WeatherHub target → Signing & Capabilities`
→ Cocher `Automatically manage signing`
→ Sélectionner votre compte Apple ID (gratuit suffit)

### "Cannot find module 'SwiftUI'"
→ Vérifier que la cible est bien **macOS** et non iOS Simulator

### Erreur de réseau (données météo vides)
→ Vérifier que `Info.plist` contient bien `NSAllowsArbitraryLoads = true`
→ C'est déjà configuré dans ce projet

---

## Structure des fichiers

```
WeatherHub/
├── WeatherHubApp.swift      ← Point d'entrée de l'app (@main)
├── Cles.swift               ← Clé API — ignoré par git (modèle : Cles.exemple.swift)
├── Config.swift             ← Adresses des API, version
├── WeatherModels.swift      ← Modèles de données, régimes extrêmes, moteur d'alertes, mode démo
├── WeatherViewModel.swift   ← Logique métier (async/await)
├── WeatherService.swift     ← Appels réseau (Open-Meteo, OpenWeather, Sensor.Community…)
├── ContentView.swift        ← Fenêtre principale, barre d'onglets, ciels
├── CielMetal.swift          ← La couche GPU (MTKView) sous le contenu
├── Ciel.metal               ← Le shader du ciel : 19 conditions calculées pixel par pixel
├── Effets.metal             ← L'air chaud qui déforme l'en-tête (canicule)
├── WeatherTabView.swift     ← Onglet météo (grille de tuiles)
├── TuileMeteo.swift         ← Les tuiles façon Apple Météo
├── DetailMeteo.swift        ← La fiche détaillée d'une tuile (graphique 48 h)
├── SportTabView.swift       ← Onglet sport
├── IconColorHelpers.swift   ← Couleurs des icônes
└── Info.plist               ← Configuration de l'app
```

---

## La clé API (première ouverture du projet)

La clé OpenWeather n'est **pas** dans le dépôt. Après un clone :

1. Dans le dossier `WeatherHub/`, copier `Cles.exemple.swift` sous le nom `Cles.swift`
   (Xcode connaît déjà ce fichier, il attend juste qu'il existe).
2. Y coller votre clé obtenue sur https://openweathermap.org/api
   (plan gratuit suffisant — 1 000 appels/jour).

`Cles.swift` est listé dans `.gitignore` : il ne partira jamais dans un commit.

---

## Mode démo (pour tester les décors)

Menu « ⋯ » → Mode démo : choisir une condition (ordinaire ou extrême), un moment
de la journée, une alerte fictive. En ligne de commande :

```
WeatherHub.app/Contents/MacOS/WeatherHub --simuler=tornado,nuit,alerte
```

Conditions : clear, clouds, rain, shower, drizzle, thunder, snow, fog, tornado, cyclone,
storm, hail, blizzard, freezing, deluge, heat, cold, dust · Moments : jour, lever, coucher, nuit.
