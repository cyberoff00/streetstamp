import SwiftUI
import MapKit
import UIKit

private struct LifelogShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct LifelogView: View {
    @Binding var showSidebar: Bool

    @EnvironmentObject private var lifelogStore: LifelogStore
    @EnvironmentObject private var locationHub: LocationHub
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var position: MapCameraPosition = .automatic
    @State private var showGlobe = false
    @State private var globeJourneysSnapshot: [JourneyRoute] = []
    @State private var showEnableHint = false
    @State private var showDisableConfirm = false
    @State private var shareItem: LifelogShareImageItem? = nil
    @State private var didCenterOnEnter = false
    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue

    private var mapAppearance: MapAppearanceStyle {
        MapAppearanceStyle(rawValue: mapAppearanceRaw) ?? .dark
    }
    private var isDarkAppearance: Bool { mapAppearance == .dark }
    private var panelBackground: Color { isDarkAppearance ? Color.black.opacity(0.80) : FigmaTheme.card.opacity(0.96) }
    private var panelText: Color { isDarkAppearance ? .white : .black }

    private var lineCoords: [CLLocationCoordinate2D] {
        lifelogStore.coordinates.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    private var allJourneysForGlobe: [JourneyRoute] {
        if lifelogStore.hasTrack {
            return [lifelogStore.syntheticJourney] + store.journeys
        }
        return store.journeys
    }

    var body: some View {
        ZStack {
            mapLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                permissionHint
                Spacer()
                bottomCard
                subtleToggle
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .preferredColorScheme(isDarkAppearance ? .dark : .light)
        .fullScreenCover(isPresented: $showGlobe) {
            GlobeViewScreen(showSidebar: .constant(false), externalJourneys: globeJourneysSnapshot)
                .environmentObject(store)
                .environmentObject(cityCache)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.image])
        }
        .alert("关闭 Lifelog 记录？", isPresented: $showDisableConfirm) {
            Button("继续记录", role: .cancel) {}
            Button("确认关闭", role: .destructive) {
                lifelogStore.setEnabled(false)
            }
        } message: {
            Text("关闭后将停止后台轨迹记录，Globe 和 Lifelog 地图将不再持续更新。")
        }
        .onAppear {
            didCenterOnEnter = false
            if locationHub.authorizationStatus != .authorizedAlways {
                showEnableHint = true
            }
            centerOnCurrent(force: true)
        }
        .onChange(of: lifelogStore.currentLocation?.coordinate.latitude) { _ in
            centerOnCurrent(force: false)
        }
        .onChange(of: lifelogStore.currentLocation?.coordinate.longitude) { _ in
            centerOnCurrent(force: false)
        }
        .onChange(of: locationHub.currentLocation?.coordinate.latitude) { _ in
            centerOnCurrent(force: false)
        }
        .onChange(of: locationHub.currentLocation?.coordinate.longitude) { _ in
            centerOnCurrent(force: false)
        }
    }

    private var mapLayer: some View {
        Map(position: $position) {
            if lineCoords.count >= 2 {
                MapPolyline(coordinates: lineCoords)
                    .stroke(Color(red: 0.05, green: 0.67, blue: 0.54), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let loc = lifelogStore.currentLocation {
                Annotation("", coordinate: loc.coordinate) {
                    ZStack {
                        Circle()
                            .fill(FigmaTheme.card.opacity(0.95))
                            .frame(width: 46, height: 46)
                        RobotRendererView(size: 36, face: .front, loadout: AvatarLoadoutStore.load())
                    }
                    .shadow(color: .black.opacity(0.24), radius: 8, y: 2)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
    }

    private var header: some View {
        HStack {
            SidebarHamburgerButton(showSidebar: $showSidebar, size: 42, iconSize: 20, iconWeight: .semibold, foreground: .black)

            Spacer()

            Text("LIFELOG")
                .appHeaderStyle()

            Spacer()

            Button {
                globeJourneysSnapshot = allJourneysForGlobe
                showGlobe = true
            } label: {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .frame(width: 42, height: 42)
                    .background(FigmaTheme.card.opacity(0.92))
                    .clipShape(Circle())
            }
        }
    }

    @ViewBuilder
    private var permissionHint: some View {
        if showEnableHint && locationHub.authorizationStatus != .authorizedAlways {
            VStack(alignment: .leading, spacing: 8) {
                Text("开启“始终允许”后，才能在后台持续记录你的轨迹。")
                    .appCaptionStyle()
                    .foregroundColor(panelText)
                Button("去开启") {
                    locationHub.requestPermissionIfNeeded()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isDarkAppearance ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isDarkAppearance ? Color.white : Color.black)
                .clipShape(Capsule())
            }
            .padding(12)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 10)
        }
    }

    private var bottomCard: some View {
        let journeys = allJourneysForGlobe
        let totalJourneys = journeys.count
        let totalMemories = journeys.reduce(0) { $0 + $1.memories.count }
        let totalDistanceMeters = journeys.reduce(0.0) { partial, journey in
            let d = journey.distance
            return partial + ((d.isFinite && d > 0) ? d : 0)
        }
        let totalDistanceKm = totalDistanceMeters / 1000.0
        let distanceKmDisplay = max(0, Int(totalDistanceKm.rounded(.down)))
        let cityCount = cityCache.cachedCities.filter { !($0.isTemporary ?? false) }.count
        let totalEP = max(0, Int(totalDistanceKm.rounded(.down)))

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 200.0 / 255.0, green: 232.0 / 255.0, blue: 221.0 / 255.0))
                    .frame(width: 68, height: 68)

                RobotRendererView(size: 56, face: .front, loadout: AvatarLoadoutStore.load())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(normalizedDisplayName(profileName))
                    .appBodyStrongStyle()
                    .foregroundColor(.black)
                    .lineLimit(1)

                Text("Lv.1  ·  \(totalEP) EP")
                    .appCaptionStyle()
                    .foregroundColor(.black.opacity(0.62))
                    .lineLimit(1)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(UITheme.accent)
                            .frame(width: max(8, proxy.size.width * 0.45), height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(cityCount) \(localizedLabel(zh: "城市", en: "Cities"))  ·  \(totalJourneys) \(localizedLabel(zh: "旅程", en: "Trips"))  ·  \(totalMemories) \(localizedLabel(zh: "记忆", en: "Memories"))  ·  \(distanceKmDisplay)km")
                    .appFootnoteStyle()
                    .foregroundColor(.black.opacity(0.56))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button {
                if let image = captureCurrentPageImage() {
                    shareItem = LifelogShareImageItem(image: image)
                }
            } label: {
                Label(localizedLabel(zh: "分享", en: "Share"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(UITheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
    }

    private var subtleToggle: some View {
        HStack {
            Spacer()
            Button {
                if lifelogStore.isEnabled {
                    showDisableConfirm = true
                } else {
                    lifelogStore.setEnabled(true)
                    if locationHub.authorizationStatus != .authorizedAlways {
                        showEnableHint = true
                        locationHub.requestPermissionIfNeeded()
                    }
                }
            } label: {
                Text(lifelogStore.isEnabled ? "Lifelog 已开启" : "开启 Lifelog")
                    .appCaptionStyle()
                    .foregroundColor(panelText.opacity(0.70))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((isDarkAppearance ? Color.black : Color.white).opacity(0.72))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.top, 10)
    }

    private func centerOnCurrent(force: Bool) {
        guard force || !didCenterOnEnter else { return }
        guard let current = currentCoordinateForCentering() else { return }
        didCenterOnEnter = true
        position = .region(MKCoordinateRegion(center: current, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    }

    private func currentCoordinateForCentering() -> CLLocationCoordinate2D? {
        if let current = lifelogStore.currentLocation?.coordinate {
            return current
        }
        if let current = locationHub.currentLocation?.coordinate {
            return current
        }
        return locationHub.lastKnownLocation?.coordinate
    }

    private func localizedLabel(zh: String, en: String) -> String {
        if Locale.preferredLanguages.first?.hasPrefix("zh") == true {
            return zh
        }
        return en
    }

    private func captureCurrentPageImage() -> UIImage? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: \.isKeyWindow)
        else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func normalizedDisplayName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "EXPLORER" : value
    }
}
