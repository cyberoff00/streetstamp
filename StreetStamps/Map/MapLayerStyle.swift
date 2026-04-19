import SwiftUI
import MapKit

// MARK: - Map Layer Style

/// Each case represents a visual map style the user can choose.
/// The engine (MapKit vs Mapbox) is an implementation detail, not a user choice.
enum MapLayerStyle: String, CaseIterable, Identifiable {
    // MapKit-based
    case standard       // Apple Maps light
    case mutedDark      // Apple Maps muted (dark mode)
    case satellite      // Apple Maps satellite
    case hybrid         // Apple Maps satellite + labels

    // Mapbox-based
    case mapboxStreets  // Mapbox Streets
    case mapboxDark     // Mapbox Dark
    case mapboxLight    // Mapbox Light
    case mapboxOutdoors // Mapbox Outdoors

    var id: String { rawValue }

    static let storageKey = "streetstamps.map.layerStyle"

    static var current: MapLayerStyle {
        MapLayerStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .mutedDark
    }

    static func apply(_ style: MapLayerStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: storageKey)
    }

    /// Which engine renders this style
    var engine: MapEngineSetting {
        switch self {
        case .standard, .mutedDark, .satellite, .hybrid:
            return .mapkit
        case .mapboxStreets, .mapboxDark, .mapboxLight, .mapboxOutdoors:
            return .mapbox
        }
    }

    /// Display name
    var title: String {
        switch self {
        case .standard:       return L10n.t("map_layer_standard")
        case .mutedDark:      return L10n.t("map_layer_dark")
        case .satellite:      return L10n.t("map_layer_satellite")
        case .hybrid:         return L10n.t("map_layer_hybrid")
        case .mapboxStreets:  return "Worldo"
        case .mapboxDark:     return "Dark"
        case .mapboxLight:    return "White"
        case .mapboxOutdoors: return "Outdoors"
        }
    }

    /// Group label
    var group: String {
        switch engine {
        case .mapkit: return "Apple Maps"
        case .mapbox: return "Mapbox"
        }
    }

    /// SF Symbol for fallback thumbnail
    var iconName: String {
        switch self {
        case .standard:       return "map"
        case .mutedDark:      return "moon.stars"
        case .satellite:      return "globe.americas"
        case .hybrid:         return "globe.americas.fill"
        case .mapboxStreets:  return "road.lanes"
        case .mapboxDark:     return "moon"
        case .mapboxLight:    return "sun.max"
        case .mapboxOutdoors: return "mountain.2"
        }
    }

    /// Preview color scheme for thumbnail background
    var previewColors: (bg: Color, road: Color, water: Color) {
        switch self {
        case .standard:       return (.init(white: 0.95), .white, .init(red: 0.65, green: 0.82, blue: 0.95))
        case .mutedDark:      return (.init(white: 0.15), .init(white: 0.25), .init(red: 0.15, green: 0.25, blue: 0.35))
        case .satellite:      return (.init(red: 0.15, green: 0.25, blue: 0.12), .init(white: 0.3), .init(red: 0.1, green: 0.2, blue: 0.35))
        case .hybrid:         return (.init(red: 0.15, green: 0.25, blue: 0.12), .init(white: 0.5), .init(red: 0.1, green: 0.2, blue: 0.35))
        case .mapboxStreets:  return (.init(white: 0.93), .init(white: 0.98), .init(red: 0.68, green: 0.85, blue: 0.92))
        case .mapboxDark:     return (.init(white: 0.12), .init(white: 0.22), .init(red: 0.12, green: 0.18, blue: 0.28))
        case .mapboxLight:    return (.init(white: 0.96), .white, .init(red: 0.72, green: 0.88, blue: 0.96))
        case .mapboxOutdoors: return (.init(red: 0.88, green: 0.92, blue: 0.85), .white, .init(red: 0.62, green: 0.80, blue: 0.90))
        }
    }

    // MARK: - MapKit configuration

    var mapKitType: MKMapType {
        switch self {
        case .standard:  return .standard
        case .mutedDark: return .mutedStandard
        case .satellite: return .satellite
        case .hybrid:    return .hybrid
        default:         return .standard
        }
    }

    var mapKitInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .mutedDark: return .dark
        default:         return .light
        }
    }

    // MARK: - Mapbox configuration

    var mapboxStyleURI: String {
        switch self {
        case .mapboxStreets:   return "mapbox://styles/cyberkkk/cmnm4g83300cq01s7dl87a277"
        case .mapboxDark:      return "mapbox://styles/mapbox/dark-v11"
        case .mapboxLight:     return "mapbox://styles/mapbox/light-v11"
        case .mapboxOutdoors:  return "mapbox://styles/mapbox/outdoors-v12"
        default:               return "mapbox://styles/mapbox/dark-v11"
        }
    }

    /// Route color: light maps = blue, dark maps = ice-white, satellite/hybrid = globe-style yellow-green
    var routeBaseColor: UIColor {
        if isSatelliteStyle {
            return UIColor(red: 221.0/255.0, green: 247.0/255.0, blue: 161.0/255.0, alpha: 1.0)
        } else if isDarkStyle {
            return UIColor(red: 220.0/255.0, green: 235.0/255.0, blue: 255.0/255.0, alpha: 1.0)
        } else {
            return UIColor(red: 30.0/255.0, green: 60.0/255.0, blue: 220.0/255.0, alpha: 1.0)
        }
    }

    var routeGlowColor: UIColor {
        if isSatelliteStyle {
            return UIColor(red: 180.0/255.0, green: 220.0/255.0, blue: 100.0/255.0, alpha: 1.0)
        } else if isDarkStyle {
            return UIColor(red: 80.0/255.0, green: 160.0/255.0, blue: 255.0/255.0, alpha: 1.0)
        } else {
            return UIColor(red: 20.0/255.0, green: 40.0/255.0, blue: 180.0/255.0, alpha: 1.0)
        }
    }

    var isDarkStyle: Bool {
        switch self {
        case .mutedDark, .mapboxDark:
            return true
        default:
            return false
        }
    }

    var isSatelliteStyle: Bool {
        switch self {
        case .satellite, .hybrid:
            return true
        default:
            return false
        }
    }

    /// Whether weather particles should use light (white) colors.
    /// True for dark maps AND satellite/hybrid (dark background), false for light-background maps.
    var useWhiteWeatherParticles: Bool {
        switch self {
        case .mutedDark, .mapboxDark, .satellite, .hybrid:
            return true
        default:
            return false
        }
    }

    /// Whether this style requires Mapbox engine (premium-gated with 24h trial).
    var isMapbox: Bool { engine == .mapbox }

    // MARK: - Mapbox 24-Hour Free Trial

    private static let trialStartKey = "streetstamps.map.mapboxTrialStart"

    /// Records the trial start timestamp (only if not already set).
    static func startMapboxTrialIfNeeded() {
        guard UserDefaults.standard.object(forKey: trialStartKey) == nil else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: trialStartKey)
    }

    /// Whether the 24-hour Mapbox trial has ever been activated.
    static var hasStartedMapboxTrial: Bool {
        UserDefaults.standard.object(forKey: trialStartKey) != nil
    }

    /// Whether the 24-hour free trial is still active.
    static var isMapboxTrialActive: Bool {
        guard let start = UserDefaults.standard.object(forKey: trialStartKey) as? Double else {
            return false
        }
        return Date().timeIntervalSince1970 - start < 24 * 3600
    }

    /// Remaining trial time as a human-readable string, or nil if expired/not started.
    static var trialRemainingText: String? {
        guard let start = UserDefaults.standard.object(forKey: trialStartKey) as? Double else {
            return nil
        }
        let elapsed = Date().timeIntervalSince1970 - start
        let remaining = 24 * 3600 - elapsed
        guard remaining > 0 else { return nil }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return String(format: L10n.t("mapbox_trial_remaining_hours"), hours, minutes)
        } else {
            return String(format: L10n.t("mapbox_trial_remaining_minutes"), minutes)
        }
    }

    /// Revert to default style if current Mapbox selection is no longer allowed.
    @MainActor static func revertToDefaultIfNeeded() {
        let current = MapLayerStyle.current
        guard current.isMapbox else { return }
        guard !MembershipStore.shared.isPremium, !isMapboxTrialActive else { return }
        apply(.mutedDark)
    }
}

// MARK: - Layer Picker View

struct MapLayerPickerView: View {
    @Binding var isPresented: Bool
    @AppStorage(MapLayerStyle.storageKey) private var layerRaw = MapLayerStyle.current.rawValue
    @StateObject private var membership = MembershipStore.shared
    @State private var showMembershipGate: MembershipGatedFeature? = nil

    private var selected: MapLayerStyle {
        MapLayerStyle(rawValue: layerRaw) ?? .mutedDark
    }

    private let appleStyles: [MapLayerStyle] = [.standard, .mutedDark, .satellite, .hybrid]
    private let mapboxStyles: [MapLayerStyle] = [.mapboxStreets, .mapboxOutdoors, .mapboxLight, .mapboxDark]

    /// Whether a Mapbox style is accessible (premium or trial active).
    private var mapboxAccessible: Bool {
        membership.isPremium || MapLayerStyle.isMapboxTrialActive
    }

    /// Whether trial has been used but not yet expired, and user is not premium.
    private var showTrialBadge: Bool {
        !membership.isPremium && MapLayerStyle.isMapboxTrialActive
    }

    /// Whether to show "free trial available" hint (never started trial, not premium).
    private var showTrialHint: Bool {
        !membership.isPremium && !MapLayerStyle.hasStartedMapboxTrial
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text(L10n.t("map_layer_title"))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(FigmaTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            VStack(spacing: 12) {
                // Apple Maps row
                Text("Apple Maps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(appleStyles) { style in
                        layerCard(style)
                    }
                }
                .padding(.horizontal, 16)

                // Mapbox row with status badge
                HStack(spacing: 6) {
                    Text("Mapbox")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)

                    if membership.isPremium {
                        // No badge needed
                    } else if showTrialBadge, let remaining = MapLayerStyle.trialRemainingText {
                        Text(remaining)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    } else if showTrialHint {
                        Text(L10n.t("mapbox_trial_free_hint"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FigmaTheme.primary)
                            .clipShape(Capsule())
                    } else {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundColor(FigmaTheme.primary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(mapboxStyles) { style in
                        layerCard(style)
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer().frame(height: 8)
        }
        .sheet(item: $showMembershipGate) { _ in
            MembershipGateView(feature: .mapAppearance)
        }
    }

    private func layerCard(_ style: MapLayerStyle) -> some View {
        let isSelected = selected == style
        let isLocked = style.isMapbox && !mapboxAccessible
        return Button {
            if style.isMapbox && !membership.isPremium {
                if !MapLayerStyle.hasStartedMapboxTrial {
                    // Start trial on first Mapbox selection
                    MapLayerStyle.startMapboxTrialIfNeeded()
                }
                if MapLayerStyle.isMapboxTrialActive {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        layerRaw = style.rawValue
                        MapLayerStyle.apply(style)
                    }
                } else {
                    // Trial expired — show membership gate
                    showMembershipGate = .mapAppearance
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    layerRaw = style.rawValue
                    MapLayerStyle.apply(style)
                }
            }
        } label: {
            VStack(spacing: 6) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(style.previewColors.bg)
                        .frame(width: 72, height: 72)

                    // Simple abstract map preview
                    VStack(spacing: 0) {
                        // Water area at top
                        style.previewColors.water
                            .frame(height: 24)
                        // Land with "roads"
                        ZStack {
                            style.previewColors.bg
                            // Horizontal road
                            style.previewColors.road
                                .frame(height: 2)
                                .offset(y: -4)
                            // Vertical road
                            style.previewColors.road
                                .frame(width: 2)
                                .offset(x: 8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(width: 72, height: 72)

                    // Icon overlay
                    Image(systemName: style.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(style.isDarkStyle ? .white.opacity(0.6) : .black.opacity(0.4))

                    // Lock overlay for expired trial
                    if isLocked {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 72, height: 72)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.blue : Color.black.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
                )

                // Label
                Text(style.title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .blue : FigmaTheme.subtext)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating Layer Button

struct MapLayerButton: View {
    @Binding var showPicker: Bool

    var body: some View {
        Button { showPicker.toggle() } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
