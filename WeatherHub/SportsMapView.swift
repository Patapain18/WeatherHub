import SwiftUI
import MapKit

// MARK: - Main Sports Map Card

struct SportsMapCard: View {

    @ObservedObject var vm: WeatherViewModel
    @StateObject private var locationManager = LocationManager()
    @State private var venues: [SportVenue] = []
    @State private var isSearching: Bool = false
    @State private var selectedVenue: SportVenue? = nil
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var searchRadius: Double = 2000
    @State private var activeFilter: SportVenueType? = nil   // nil = tous

    private let searchService = NearbySearchService()

    var filteredVenues: [SportVenue] {
        guard let filter = activeFilter else { return venues }
        return venues.filter { $0.sportType == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Équipements à proximité")
                        .font(.headline).foregroundColor(.texte)
                    Text("\(filteredVenues.count) lieu\(filteredVenues.count > 1 ? "x" : "") trouvé\(filteredVenues.count > 1 ? "s" : "")")
                        .font(.caption).foregroundColor(.texte.opacity(0.5))
                }
                Spacer()
                // Bouton réinitialiser filtre
                if activeFilter != nil {
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { activeFilter = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.texte.opacity(0.5)).font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)

            // MARK: Filtres par type de sport
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SportVenueType.allCases, id: \.self) { type in
                        sportFilterChip(type)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 10)
            }

            // MARK: Slider de rayon
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "circle.dashed").font(.caption).foregroundColor(.texte.opacity(0.5))
                    Text("Rayon de recherche").font(.caption).foregroundColor(.texte.opacity(0.6))
                    Spacer()
                    Text(radiusLabel).font(.caption.bold()).foregroundColor(.texte)
                }
                Slider(value: $searchRadius, in: 500...10000, step: 250)
                    .tint(.cyan)
                    .onChange(of: searchRadius) { _, _ in
                        guard let loc = locationManager.location else { return }
                        cameraPosition = .region(MKCoordinateRegion(
                            center: loc.coordinate,
                            latitudinalMeters: searchRadius * 2.5,
                            longitudinalMeters: searchRadius * 2.5
                        ))
                        loadVenues(at: loc.coordinate)
                    }
            }
            .padding(.horizontal, 18).padding(.bottom, 10)

            // MARK: Map
            mapContent
                .frame(height: 280)

            // MARK: Venue list
            venueList
                .padding(.bottom, 14)
        }
        .fondCarte()
        .cornerRadius(28)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .onAppear { locationManager.requestLocation() }
        .onChange(of: locationManager.location) { _, newLoc in
            guard let loc = newLoc else { return }
            cameraPosition = .region(MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: searchRadius * 2.5,
                longitudinalMeters: searchRadius * 2.5
            ))
            loadVenues(at: loc.coordinate)
        }
    }

    // MARK: - Radius label

    private var radiusLabel: String {
        searchRadius < 1000 ? "\(Int(searchRadius)) m" : String(format: "%.1f km", searchRadius / 1000)
    }

    // MARK: - Filtre chip

    private func sportFilterChip(_ type: SportVenueType) -> some View {
        let isActive = activeFilter == type
        let count = venues.filter { $0.sportType == type }.count
        return Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                activeFilter = isActive ? nil : type
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.sfSymbol).font(.caption)
                Text(type.rawValue).font(.caption.bold())
                if count > 0 {
                    Text("\(count)").font(.system(size: 9, weight: .bold))
                        .padding(3).background(Color.surface.opacity(0.2)).clipShape(Circle())
                }
            }
            .foregroundColor(isActive ? .black : .texte)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isActive ? Color.texte : Color.texte.opacity(0.12))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .opacity(count == 0 && !isActive ? 0.4 : 1.0)
    }

    // MARK: - Map content

    @ViewBuilder
    private var mapContent: some View {
        if locationManager.authorizationStatus == .denied {
            localisationDeniedView
        } else if locationManager.location == nil {
            localisationWaitingView
        } else {
            Map(position: $cameraPosition) {
                UserAnnotation()
                ForEach(filteredVenues) { venue in
                    Annotation(venue.name, coordinate: venue.coordinate) {
                        VenueMapPin(venue: venue, isSelected: selectedVenue?.id == venue.id)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.3)) {
                                    selectedVenue = selectedVenue?.id == venue.id ? nil : venue
                                }
                            }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .topTrailing) {
                if isSearching {
                    HStack(spacing: 6) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .texte)).scaleEffect(0.8)
                        Text("Recherche…").font(.caption).foregroundColor(.texte)
                    }
                    .padding(8).fondCarte().cornerRadius(10).padding(10)
                }
            }
        }
    }

    private var localisationDeniedView: some View {
        ZStack {
            Color.black.opacity(0.3)
            VStack(spacing: 10) {
                Image(systemName: "location.slash.fill").font(.system(size: 36)).foregroundColor(.texte.opacity(0.6))
                Text("Localisation désactivée").font(.headline).foregroundColor(.texte)
                Text("Activez-la dans Préférences Système\n→ Confidentialité → Localisation")
                    .font(.caption).foregroundColor(.texte.opacity(0.6)).multilineTextAlignment(.center)
            }
        }
    }

    private var localisationWaitingView: some View {
        ZStack {
            Color.black.opacity(0.2)
            VStack(spacing: 12) {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .texte)).scaleEffect(1.3)
                Text("Localisation en cours…").font(.subheadline).foregroundColor(.texte)
            }
        }
    }

    // MARK: - Venue list

    @ViewBuilder
    private var venueList: some View {
        if !filteredVenues.isEmpty || isSearching {
            Divider().background(Color.surface.opacity(0.2)).padding(.vertical, 6)

            if let v = selectedVenue {
                venueDetailRow(v)
                    .padding(.horizontal, 18)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .move(edge: .top)),
                        removal: .scale(scale: 0.96).combined(with: .opacity)
                    ))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredVenues) { venue in
                            venueChip(venue)
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
                                        selectedVenue = venue
                                        cameraPosition = .region(MKCoordinateRegion(
                                            center: venue.coordinate,
                                            latitudinalMeters: 600, longitudinalMeters: 600
                                        ))
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .frame(height: 80)
            }
        }
    }

    private func venueDetailRow(_ venue: SportVenue) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(adviceColor(venue.weatherAdvice).opacity(0.25)).frame(width: 44, height: 44)
                Image(systemName: venue.sportType.sfSymbol).font(.system(size: 20))
                    .foregroundColor(adviceColor(venue.weatherAdvice))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name).font(.subheadline.bold()).foregroundColor(.texte).lineLimit(1)
                Text(WeatherAdviceCalculator.reasonDetail(for: venue, condition: vm.state.condition,
                                                           temp: vm.state.temperature, wind: vm.state.windSpeed))
                    .font(.caption).foregroundColor(.texte.opacity(0.6))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(venue.weatherAdvice.emoji).font(.title3)
                Text(venue.weatherAdvice.label).font(.caption2.bold()).foregroundColor(adviceColor(venue.weatherAdvice))
            }
            Button { withAnimation(.spring(duration: 0.35, bounce: 0.2)) { selectedVenue = nil } } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.texte.opacity(0.4)).font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(14).background(Color.surface.opacity(0.08)).cornerRadius(16)
    }

    private func venueChip(_ venue: SportVenue) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(adviceColor(venue.weatherAdvice).opacity(0.2)).frame(width: 36, height: 36)
                Image(systemName: venue.sportType.sfSymbol).font(.system(size: 16))
                    .foregroundColor(adviceColor(venue.weatherAdvice))
            }
            Text(venue.sportType.rawValue).font(.system(size: 9, weight: .medium))
                .foregroundColor(.texte.opacity(0.7)).lineLimit(1)
            Text(venue.weatherAdvice.emoji).font(.system(size: 10))
        }
        .frame(width: 60).padding(.vertical, 8)
        .background(Color.surface.opacity(0.1)).cornerRadius(12)
    }

    // MARK: - Helpers

    private func adviceColor(_ advice: VenueWeatherAdvice) -> Color {
        switch advice {
        case .recommended:    return .green
        case .acceptable:     return .orange
        case .notRecommended: return .red
        case .unknown:        return .gray
        }
    }

    private func loadVenues(at coordinate: CLLocationCoordinate2D) {
        isSearching = true
        venues = []
        selectedVenue = nil
        Task {
            var found = await searchService.search(near: coordinate, radiusMeters: searchRadius)
            for i in found.indices {
                found[i].weatherAdvice = WeatherAdviceCalculator.advice(
                    for: found[i], condition: vm.state.condition,
                    temp: vm.state.temperature, wind: vm.state.windSpeed
                )
            }
            found.sort { advicePriority($0.weatherAdvice) > advicePriority($1.weatherAdvice) }
            venues = found
            isSearching = false
        }
    }

    private func advicePriority(_ advice: VenueWeatherAdvice) -> Int {
        switch advice {
        case .recommended: return 3; case .acceptable: return 2
        case .notRecommended: return 1; case .unknown: return 0
        }
    }
}

// MARK: - Map Pin View

struct VenueMapPin: View {
    let venue: SportVenue
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(pinColor)
                    .frame(width: isSelected ? 42 : 32, height: isSelected ? 42 : 32)
                    .shadow(color: pinColor.opacity(0.5), radius: isSelected ? 8 : 4)
                Image(systemName: venue.sportType.sfSymbol)
                    .font(.system(size: isSelected ? 18 : 14)).foregroundColor(.texte)
            }
            if isSelected {
                Text(venue.weatherAdvice.emoji).font(.system(size: 12))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .fondCarte().cornerRadius(8)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.35), value: isSelected)
    }

    private var pinColor: Color {
        switch venue.weatherAdvice {
        case .recommended: return .green; case .acceptable: return .orange
        case .notRecommended: return .red; case .unknown: return .gray
        }
    }
}
