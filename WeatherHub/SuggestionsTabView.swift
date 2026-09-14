import SwiftUI
import AppKit

// MARK: - Onglet Suggestions

struct SuggestionsTabView: View {

    @State private var selectedCategory: SuggestionCategory = .feature
    @State private var title: String = ""
    @State private var messageBody: String = ""
    @State private var authorName: String = ""
    @State private var sendState: SendState = .idle

    enum SendState { case idle, success, error }

    var body: some View {
        ScrollView {
            SondeDefilement()
            VStack(spacing: 0) {

                // MARK: Header
                VStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.yellow.opacity(0.9))
                    Text("Vos suggestions")
                        .font(.largeTitle.bold())
                        .foregroundColor(.texte)
                    Text("Aidez-nous à améliorer WeatherHub")
                        .font(.subheadline)
                        .foregroundColor(.texte.opacity(0.55))
                }
                .padding(.top, 60)
                .padding(.bottom, 36)

                VStack(spacing: 20) {

                    // MARK: Catégorie
                    formCard {
                        VStack(alignment: .leading, spacing: 12) {
                            formLabel(icon: "tag.fill", text: "Catégorie")
                            HStack(spacing: 10) {
                                ForEach(SuggestionCategory.allCases, id: \.self) { cat in
                                    categoryChip(cat)
                                }
                            }
                        }
                    }

                    // MARK: Votre nom (optionnel)
                    formCard {
                        VStack(alignment: .leading, spacing: 10) {
                            formLabel(icon: "person.fill", text: "Votre prénom (optionnel)")
                            TextField("Ex: Marie", text: $authorName)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundColor(.texte)
                                .padding(12)
                                .background(Color.surface.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }

                    // MARK: Titre
                    formCard {
                        VStack(alignment: .leading, spacing: 10) {
                            formLabel(icon: "pencil", text: "Titre de votre suggestion")
                            TextField("Ex: Ajouter la météo radar en temps réel", text: $title)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundColor(.texte)
                                .padding(12)
                                .background(Color.surface.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }

                    // MARK: Description
                    formCard {
                        VStack(alignment: .leading, spacing: 10) {
                            formLabel(icon: "text.alignleft", text: "Description")
                            TextEditor(text: $messageBody)
                                .font(.body)
                                .foregroundColor(.texte)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(Color.surface.opacity(0.08))
                                .cornerRadius(12)
                                .frame(minHeight: 120)
                                .overlay(alignment: .topLeading) {
                                    if messageBody.isEmpty {
                                        Text("Décrivez votre idée, ce qui vous manque, ce qui pourrait être amélioré…")
                                            .font(.body)
                                            .foregroundColor(.texte.opacity(0.3))
                                            .padding(16)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }
                    }

                    // MARK: Bouton envoyer
                    sendButton

                    // MARK: Feedback
                    if sendState == .success {
                        successBanner
                    } else if sendState == .error {
                        errorBanner
                    }

                    // MARK: Note de confidentialité
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("Vos données ne sont utilisées que pour améliorer WeatherHub.")
                            .font(.caption2)
                    }
                    .foregroundColor(.texte.opacity(0.35))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Category chip

    private func categoryChip(_ cat: SuggestionCategory) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { selectedCategory = cat }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.caption)
                Text(cat.label)
                    .font(.caption.bold())
            }
            .foregroundColor(isSelected ? .black : .texte)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.texte : Color.texte.opacity(0.12))
            .cornerRadius(20)
            .shadow(color: isSelected ? Color.texte.opacity(0.15) : .clear, radius: 6, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: selectedCategory)
    }

    // MARK: - Form helpers

    private func formCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fondCarte()
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private func formLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundColor(.texte.opacity(0.5))
            Text(text)
                .font(.caption.bold())
                .foregroundColor(.texte.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    // MARK: - Send button

    private var sendButton: some View {
        let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty ||
                         messageBody.trimmingCharacters(in: .whitespaces).isEmpty

        return Button(action: sendSuggestion) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .rotationEffect(.degrees(isDisabled ? 0 : -5))
                Text("Envoyer la suggestion")
                    .font(.headline)
            }
            .foregroundColor(isDisabled ? .texte.opacity(0.4) : .texte)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    if isDisabled {
                        Color.texte.opacity(0.1)
                    } else {
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.45, blue: 0.9), Color(red: 0.2, green: 0.65, blue: 1.0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        // Reflet lumineux subtil
                        LinearGradient(colors: [Color.texte.opacity(0.12), Color.clear],
                                       startPoint: .top, endPoint: .center)
                    }
                }
            )
            .cornerRadius(18)
            .shadow(color: isDisabled ? .clear : .blue.opacity(0.35), radius: 10, x: 0, y: 5)
            .shadow(color: isDisabled ? .clear : .cyan.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .animation(.spring(duration: 0.3), value: isDisabled)
    }

    private var successBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggestion envoyée !")
                    .font(.subheadline.bold())
                    .foregroundColor(.texte)
                Text("Votre messagerie va s'ouvrir. Envoyez l'e-mail préparé.")
                    .font(.caption)
                    .foregroundColor(.texte.opacity(0.6))
            }
            Spacer()
        }
        .padding(14)
        .background(Color(red: 0.3, green: 0.8, blue: 0.5).opacity(0.15))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.3, green: 0.8, blue: 0.5).opacity(0.3), lineWidth: 1))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .move(edge: .top)),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }

    private var errorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Impossible d'ouvrir la messagerie")
                    .font(.subheadline.bold())
                    .foregroundColor(.texte)
                Text("Envoyez manuellement à mathissoupizon@gmail.com")
                    .font(.caption)
                    .foregroundColor(.texte.opacity(0.6))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .move(edge: .top)),
            removal: .scale(scale: 0.95).combined(with: .opacity)
        ))
    }

    // MARK: - Send logic (mailto)

    private func sendSuggestion() {
        let recipient = "mathissoupizon@gmail.com"
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanBody  = messageBody.trimmingCharacters(in: .whitespaces)
        let name       = authorName.trimmingCharacters(in: .whitespaces)

        let subject = "[\(selectedCategory.label)] \(cleanTitle)"
        let emailBody = """
        \(name.isEmpty ? "" : "De : \(name)\n\n")Catégorie : \(selectedCategory.label)
        Titre : \(cleanTitle)

        \(cleanBody)

        ---
        Envoyé depuis WeatherHub \(VersionHistory.current?.number ?? "")
        """

        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded    = emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailtoString   = "mailto:\(recipient)?subject=\(subjectEncoded)&body=\(bodyEncoded)"

        if let url = URL(string: mailtoString) {
            let opened = NSWorkspace.shared.open(url)
            withAnimation(.spring(duration: 0.4)) {
                sendState = opened ? .success : .error
            }
            if opened {
                // Reset form après 3 secondes
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        title = ""
                        messageBody = ""
                        authorName = ""
                        sendState = .idle
                        selectedCategory = .feature
                    }
                }
            }
        } else {
            withAnimation { sendState = .error }
        }
    }
}

// MARK: - Suggestion Category

enum SuggestionCategory: CaseIterable {
    case feature, improvement, bug, design

    var label: String {
        switch self {
        case .feature:     return "Nouvelle fonctionnalité"
        case .improvement: return "Amélioration"
        case .bug:         return "Bug"
        case .design:      return "Design"
        }
    }

    var icon: String {
        switch self {
        case .feature:     return "plus.circle"
        case .improvement: return "arrow.up.circle"
        case .bug:         return "ant.circle"
        case .design:      return "paintbrush"
        }
    }
}
