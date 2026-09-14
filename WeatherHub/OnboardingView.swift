import SwiftUI

// MARK: - Étapes d'onboarding

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case name    = 1
    case email   = 2
    case sports  = 3
    case done    = 4
}

// MARK: - Vue principale

struct OnboardingView: View {

    @StateObject private var store = UserAccountStore.shared
    @State private var step: OnboardingStep = .welcome
    @State private var firstName: String = ""
    @State private var email: String = ""
    @State private var selectedSports: Set<String> = []

    // Animations
    @State private var contentAppeared = false
    @State private var logoScale: CGFloat = 0.4
    @State private var logoOpacity: Double = 0
    @State private var particleOffset: [CGSize] = (0..<20).map { _ in
        CGSize(width: CGFloat.random(in: -200...200), height: CGFloat.random(in: -200...200))
    }

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Fond animé
            animatedBackground

            // Contenu par étape
            VStack {
                switch step {
                case .welcome: welcomeStep
                case .name:    nameStep
                case .email:   emailStep
                case .sports:  sportsStep
                case .done:    doneStep
                }
            }
            .frame(maxWidth: 480)
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Logo apparaît avec un léger rebond élastique
            withAnimation(.spring(duration: 1.2, bounce: 0.4).delay(0.15)) {
                logoScale = 1.0; logoOpacity = 1.0
            }
            // Contenu apparaît légèrement après
            withAnimation(.spring(duration: 0.8, bounce: 0.2).delay(0.4)) {
                contentAppeared = true
            }
            // Particules avec mouvement organique varié
            for i in 0..<20 {
                let baseDuration = Double.random(in: 4...8)
                withAnimation(.easeInOut(duration: baseDuration)
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.08)) {
                    particleOffset[i] = CGSize(
                        width: CGFloat.random(in: -250...250),
                        height: CGFloat.random(in: -250...250)
                    )
                }
            }
        }
    }

    // MARK: - Background animé

    private var animatedBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.06,green:0.14,blue:0.35),
                                    Color(red:0.02,green:0.06,blue:0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            // Particules flottantes — orbes avec dégradé cyan/violet
            ForEach(0..<20, id: \.self) { i in
                let size = CGFloat(40 + (i * 7) % 90)
                let blurAmt = CGFloat(15 + (i * 3) % 20)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: i % 3 == 0
                                ? [Color.cyan.opacity(0.10), Color.cyan.opacity(0.0)]
                                : i % 3 == 1
                                    ? [Color.purple.opacity(0.08), Color.purple.opacity(0.0)]
                                    : [Color.texte.opacity(0.06), Color.texte.opacity(0.0)],
                            center: .center, startRadius: 0, endRadius: size * 0.5
                        )
                    )
                    .frame(width: size, height: size)
                    .offset(particleOffset[i])
                    .blur(radius: blurAmt)
            }
        }
    }

    // MARK: - Barre de progression

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(1...4, id: \.self) { i in
                Capsule()
                    .fill(step.rawValue >= i ? Color.cyan : Color.texte.opacity(0.2))
                    .frame(height: 3)
                    .shadow(color: step.rawValue >= i ? Color.cyan.opacity(0.4) : .clear, radius: 4, x: 0, y: 0)
                    .animation(.spring(duration: 0.5, bounce: 0.3).delay(Double(i) * 0.05), value: step)
            }
        }
        .frame(width: 120)
    }

    // MARK: - ÉTAPE 1 : Bienvenue

    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo animé avec halo pulsant
            VStack(spacing: 16) {
                ZStack {
                    // Halo extérieur pulsant
                    Circle()
                        .fill(Color.cyan.opacity(0.08))
                        .frame(width: 180, height: 180)
                        .blur(radius: 30)
                        .scaleEffect(contentAppeared ? 1.1 : 0.6)
                        .opacity(contentAppeared ? 1 : 0)
                        .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: contentAppeared)
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 130, height: 130)
                        .blur(radius: 20)
                        .scaleEffect(logoScale)
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 70))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.yellow, .cyan)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .shadow(color: .yellow.opacity(0.3), radius: 20, x: 0, y: 4)
                        .rotationEffect(.degrees(contentAppeared ? 0 : -8))
                        .animation(.spring(duration: 1.2, bounce: 0.4).delay(0.15), value: contentAppeared)
                }

                Text("WeatherHub")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.texte)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 24)
                    .scaleEffect(contentAppeared ? 1 : 0.9)
                    .animation(.spring(duration: 0.7, bounce: 0.25).delay(0.35), value: contentAppeared)

                Text("La météo qui s'adapte\nà vos sports")
                    .font(.title3)
                    .foregroundColor(.texte.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 18)
                    .animation(.spring(duration: 0.7, bounce: 0.2).delay(0.55), value: contentAppeared)
            }

            Spacer()

            // Features rapides — apparition en cascade
            VStack(spacing: 12) {
                featurePill("sun.max.fill", "UV, qualité de l'air, alertes en temps réel", .yellow)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(x: contentAppeared ? 0 : -30)
                    .animation(.spring(duration: 0.6, bounce: 0.2).delay(0.7), value: contentAppeared)
                featurePill("figure.run", "Conseils sport personnalisés selon la météo", .cyan)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(x: contentAppeared ? 0 : -30)
                    .animation(.spring(duration: 0.6, bounce: 0.2).delay(0.85), value: contentAppeared)
                featurePill("map.fill", "Équipements sportifs à proximité", .green)
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(x: contentAppeared ? 0 : -30)
                    .animation(.spring(duration: 0.6, bounce: 0.2).delay(1.0), value: contentAppeared)
            }

            Spacer()

            primaryButton("Commencer →") {
                withAnimation(.spring(duration: 0.5)) { step = .name }
            }
        }
    }

    private func featurePill(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(color).frame(width: 24)
            Text(text).font(.subheadline).foregroundColor(.texte.opacity(0.75))
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color.surface.opacity(0.07))
        .cornerRadius(14)
    }

    // MARK: - ÉTAPE 2 : Prénom

    private var nameStep: some View {
        VStack(spacing: 36) {
            stepHeader(number: 1, title: "Comment vous appeler ?",
                       subtitle: "Votre prénom pour personnaliser l'expérience")

            VStack(spacing: 8) {
                TextField("Votre prénom", text: $firstName)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.texte)
                    .padding(16)
                    .background(Color.surface.opacity(0.1))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(firstName.isEmpty ? Color.texte.opacity(0.15) : Color.cyan.opacity(0.6), lineWidth: 1.5))

                if !firstName.isEmpty {
                    Text("Bonjour \(firstName) 👋")
                        .font(.subheadline).foregroundColor(.cyan)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer()

            primaryButton("Suivant →") {
                withAnimation(.spring(duration: 0.5)) { step = .email }
            }
            .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(firstName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)

            skipButton()
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                                removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.95))))
    }

    // MARK: - ÉTAPE 3 : Email

    private var emailStep: some View {
        VStack(spacing: 36) {
            stepHeader(number: 2, title: "Votre email",
                       subtitle: "Pour recevoir vos alertes météo sport\net rejoindre la communauté WeatherHub")

            VStack(spacing: 12) {
                TextField("votre@email.com", text: $email)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.texte)
                    .padding(16)
                    .background(Color.surface.opacity(0.1))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(emailStrokeColor, lineWidth: 1.5))

                // Badge futur
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill").font(.caption).foregroundColor(.purple)
                    Text("Fonctionnalités communautaires à venir en V3")
                        .font(.caption).foregroundColor(.texte.opacity(0.5))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(10)
            }

            Text("Vos données restent privées et ne sont jamais revendues.")
                .font(.caption2).foregroundColor(.texte.opacity(0.35))
                .multilineTextAlignment(.center)

            Spacer()

            primaryButton("Suivant →") {
                withAnimation(.spring(duration: 0.5)) { step = .sports }
            }
            .disabled(!isEmailValid)
            .opacity(isEmailValid ? 1 : 0.4)

            skipButton()
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                                removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.95))))
    }

    private var emailStrokeColor: Color {
        if email.isEmpty { return Color.texte.opacity(0.15) }
        return isEmailValid ? Color.cyan.opacity(0.6) : Color.red.opacity(0.5)
    }

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }

    // MARK: - ÉTAPE 4 : Sports

    private var sportsStep: some View {
        VStack(spacing: 24) {
            stepHeader(number: 3, title: "Vos sports favoris",
                       subtitle: "Choisissez ceux que vous pratiquez en extérieur\n(modifiable dans le profil)")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(OnboardingSport.all) { sport in
                    sportCard(sport)
                }
            }

            if !selectedSports.isEmpty {
                Text("\(selectedSports.count) sport\(selectedSports.count > 1 ? "s" : "") sélectionné\(selectedSports.count > 1 ? "s" : "")")
                    .font(.caption).foregroundColor(.cyan)
            }

            primaryButton(selectedSports.isEmpty ? "Passer →" : "Créer mon profil →") {
                finishOnboarding()
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                                removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.95))))
    }

    private func sportCard(_ sport: OnboardingSport) -> some View {
        let selected = selectedSports.contains(sport.id)
        return Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.45)) {
                if selected { selectedSports.remove(sport.id) }
                else        { selectedSports.insert(sport.id) }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    // Halo de sélection
                    Circle()
                        .fill(selected ? sport.color.opacity(0.2) : Color.clear)
                        .frame(width: 62, height: 62)
                        .blur(radius: 8)
                    Circle()
                        .fill(selected ? sport.color.opacity(0.3) : Color.texte.opacity(0.08))
                        .frame(width: 52, height: 52)
                    Image(systemName: sport.icon)
                        .font(.title2)
                        .foregroundColor(selected ? sport.color : .texte.opacity(0.5))
                        .rotationEffect(.degrees(selected ? 8 : 0))
                }
                Text(sport.name)
                    .font(.subheadline.bold())
                    .foregroundColor(selected ? .texte : .texte.opacity(0.55))
                Text(sport.description)
                    .font(.caption2)
                    .foregroundColor(.texte.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 8)
            .background(selected ? sport.color.opacity(0.15) : Color.texte.opacity(0.06))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? sport.color.opacity(0.6) : Color.clear, lineWidth: 1.5))
            .shadow(color: selected ? sport.color.opacity(0.25) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(selected ? 1.05 : 1.0)
        .animation(.spring(duration: 0.4, bounce: 0.45), value: selected)
    }

    // MARK: - ÉTAPE 5 : Terminé

    private var doneStep: some View {
        VStack(spacing: 32) {
            Spacer()

            // Checkmark animé avec anneaux de célébration
            ZStack {
                // Anneau extérieur pulsant
                Circle()
                    .stroke(Color.green.opacity(0.15), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .scaleEffect(contentAppeared ? 1.2 : 0.5)
                    .opacity(contentAppeared ? 0 : 1)
                    .animation(.easeOut(duration: 1.2).delay(0.3), value: contentAppeared)
                // Second anneau
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .scaleEffect(contentAppeared ? 1.15 : 0.5)
                    .opacity(contentAppeared ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.0).delay(0.2), value: contentAppeared)
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .shadow(color: .green.opacity(0.3), radius: 20, x: 0, y: 0)
                Circle()
                    .stroke(Color.green.opacity(0.4), lineWidth: 2)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, Color.green.opacity(0.3))
            }
            .scaleEffect(contentAppeared ? 1.0 : 0.3)
            .rotationEffect(.degrees(contentAppeared ? 0 : -20))
            .animation(.spring(duration: 0.7, bounce: 0.5), value: contentAppeared)

            VStack(spacing: 8) {
                Text("Bienvenue \(firstName.isEmpty ? "" : firstName) !")
                    .font(.system(size: 32, weight: .bold)).foregroundColor(.texte)
                Text("Votre profil est prêt.\nWeatherHub va maintenant personnaliser\ntous les conseils selon vos sports.")
                    .font(.body).foregroundColor(.texte.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            if !selectedSports.isEmpty {
                HStack {
                    ForEach(OnboardingSport.all.filter { selectedSports.contains($0.id) }.prefix(4)) { s in
                        Text(s.emoji).font(.title2)
                    }
                    if selectedSports.count > 4 {
                        Text("+\(selectedSports.count - 4)").font(.caption).foregroundColor(.texte.opacity(0.5))
                    }
                }
            }

            Spacer()

            primaryButton("Découvrir WeatherHub") {
                withAnimation(.easeInOut(duration: 0.5)) { onComplete() }
            }
        }
    }

    // MARK: - Helpers UI

    private func stepHeader(number: Int, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            progressBar
            Text(title)
                .font(.system(size: 26, weight: .bold)).foregroundColor(.texte)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline).foregroundColor(.texte.opacity(0.55))
                .multilineTextAlignment(.center).lineSpacing(3)
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline).foregroundColor(.texte)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(
                    ZStack {
                        LinearGradient(colors: [Color.cyan.opacity(0.8), Color.blue],
                                       startPoint: .leading, endPoint: .trailing)
                        // Reflet lumineux subtil en haut
                        LinearGradient(colors: [Color.texte.opacity(0.15), Color.clear],
                                       startPoint: .top, endPoint: .center)
                    }
                )
                .cornerRadius(18)
                .shadow(color: .cyan.opacity(0.35), radius: 12, x: 0, y: 6)
                .shadow(color: .blue.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func skipButton() -> some View {
        Button("Passer cette étape") {
            withAnimation(.spring(duration: 0.5)) {
                step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done
            }
        }
        .font(.caption).foregroundColor(.texte.opacity(0.35)).buttonStyle(.plain)
    }

    // MARK: - Finalisation

    private func finishOnboarding() {
        store.completeOnboarding(
            firstName: firstName,
            email: email,
            sportIDs: Array(selectedSports)
        )
        withAnimation(.spring(duration: 0.55, bounce: 0.25)) { step = .done }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            contentAppeared = false
            withAnimation(.spring(duration: 0.8, bounce: 0.4).delay(0.05)) {
                contentAppeared = true
            }
        }
    }
}
