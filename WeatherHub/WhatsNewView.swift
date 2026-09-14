import SwiftUI

// MARK: - Popup "Quoi de neuf" (affiché au premier lancement d'une nouvelle version)

struct WhatsNewPopup: View {

    let version: AppVersion
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Fond assombri
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Carte centrale
            VStack(spacing: 0) {

                // Header dégradé
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.45, blue: 0.9), Color(red: 0.3, green: 0.75, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Cercles décoratifs
                    Circle()
                        .fill(Color.surface.opacity(0.08))
                        .frame(width: 180, height: 180)
                        .offset(x: -80, y: 40)
                    Circle()
                        .fill(Color.surface.opacity(0.06))
                        .frame(width: 120, height: 120)
                        .offset(x: 100, y: 20)

                    VStack(spacing: 8) {
                        Text("✦ Quoi de neuf")
                            .font(.caption.bold())
                            .foregroundColor(.texte.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.surface.opacity(0.15))
                            .cornerRadius(20)

                        Text(version.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.texte)
                            .multilineTextAlignment(.center)

                        Text("Version \(version.number) — \(version.date)")
                            .font(.subheadline)
                            .foregroundColor(.texte.opacity(0.65))
                    }
                    .padding(.bottom, 28)
                }
                .frame(height: 160)

                // Liste des features
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(version.features) { feature in
                            featureRow(feature)
                            if feature.id != version.features.last?.id {
                                Divider()
                                    .background(Color.surface.opacity(0.08))
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 320)

                // Bouton continuer
                Button(action: dismiss) {
                    Text("Continuer")
                        .font(.headline)
                        .foregroundColor(.texte)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.45, blue: 0.9), Color(red: 0.2, green: 0.65, blue: 1.0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
                .padding(20)
            }
            .fondCarte()
            .cornerRadius(28)
            .shadow(color: .black.opacity(0.45), radius: 35, x: 0, y: 12)
            .shadow(color: .cyan.opacity(0.08), radius: 20, x: 0, y: 0)
            .frame(width: 420)
            .scaleEffect(appeared ? 1 : 0.82)
            .offset(y: appeared ? 0 : 30)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.6, bounce: 0.35)) {
                    appeared = true
                }
            }
        }
    }

    private func featureRow(_ feature: VersionFeature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Icône
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(featureTypeColor(feature.type).opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: feature.icon)
                    .font(.system(size: 18))
                    .foregroundColor(featureTypeColor(feature.type))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feature.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.texte)
                    typeBadge(feature.type)
                }
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(.texte.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func typeBadge(_ type: FeatureType) -> some View {
        Text(type.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(featureTypeColor(type))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(featureTypeColor(type).opacity(0.18))
            .cornerRadius(6)
    }

    private func featureTypeColor(_ type: FeatureType) -> Color {
        switch type {
        case .new:      return Color(red: 0.3, green: 0.8, blue: 0.5)
        case .improved: return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .fixed:    return Color(red: 1.0, green: 0.7, blue: 0.3)
        }
    }

    private func dismiss() {
        withAnimation(.spring(duration: 0.35, bounce: 0.0)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            VersionHistory.markCurrentVersionAsSeen()
            onDismiss()
        }
    }
}

// MARK: - Onglet "Nouveautés" (historique complet)

struct WhatsNewTabView: View {

    @State private var expandedVersion: String? = VersionHistory.current?.number

    var body: some View {
        ScrollView {
            SondeDefilement()
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundColor(.texte.opacity(0.9))
                    Text("Nouveautés")
                        .font(.largeTitle.bold())
                        .foregroundColor(.texte)
                    Text("Historique des mises à jour de WeatherHub")
                        .font(.subheadline)
                        .foregroundColor(.texte.opacity(0.55))
                }
                .padding(.top, 60)
                .padding(.bottom, 32)

                // Versions
                VStack(spacing: 14) {
                    ForEach(VersionHistory.all) { version in
                        versionCard(version)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    private func versionCard(_ version: AppVersion) -> some View {
        let isExpanded = expandedVersion == version.number

        return VStack(spacing: 0) {
            // Header de la carte (toujours visible)
            Button {
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                    expandedVersion = isExpanded ? nil : version.number
                }
            } label: {
                HStack(spacing: 14) {
                    // Badge version
                    VStack(spacing: 2) {
                        Text(version.number)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.texte)
                        if version.isCurrentVersion {
                            Text("Actuelle")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.5))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(red: 0.3, green: 0.8, blue: 0.5).opacity(0.2))
                                .cornerRadius(5)
                        }
                    }
                    .frame(width: 60)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.title)
                            .font(.headline)
                            .foregroundColor(.texte)
                        Text(version.date)
                            .font(.caption)
                            .foregroundColor(.texte.opacity(0.5))
                    }

                    Spacer()

                    Text("\(version.features.count) changement\(version.features.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundColor(.texte.opacity(0.5))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.texte.opacity(0.4))
                }
                .padding(18)
            }
            .buttonStyle(.plain)

            // Contenu dépliable
            if isExpanded {
                Divider()
                    .background(Color.surface.opacity(0.12))
                    .padding(.horizontal, 18)

                VStack(spacing: 0) {
                    ForEach(version.features) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(featureTypeColor(feature.type).opacity(0.18))
                                    .frame(width: 34, height: 34)
                                Image(systemName: feature.icon)
                                    .font(.system(size: 15))
                                    .foregroundColor(featureTypeColor(feature.type))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(feature.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.texte)
                                    Text(feature.type.label)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(featureTypeColor(feature.type))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(featureTypeColor(feature.type).opacity(0.18))
                                        .cornerRadius(5)
                                }
                                Text(feature.description)
                                    .font(.caption)
                                    .foregroundColor(.texte.opacity(0.55))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)

                        if feature.id != version.features.last?.id {
                            Divider()
                                .background(Color.surface.opacity(0.07))
                                .padding(.leading, 64)
                        }
                    }
                }
                .padding(.vertical, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                ))
            }
        }
        .fondCarte()
        .cornerRadius(22)
        .shadow(color: .black.opacity(version.isCurrentVersion ? 0.3 : 0.15), radius: version.isCurrentVersion ? 12 : 6, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(version.isCurrentVersion ? Color.texte.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }

    private func featureTypeColor(_ type: FeatureType) -> Color {
        switch type {
        case .new:      return Color(red: 0.3, green: 0.8, blue: 0.5)
        case .improved: return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .fixed:    return Color(red: 1.0, green: 0.7, blue: 0.3)
        }
    }
}
