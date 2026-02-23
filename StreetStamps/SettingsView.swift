import SwiftUI
import Foundation
import CoreLocation
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var lifelogStore: LifelogStore

    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue
    @AppStorage(AppSettings.voiceBroadcastEnabledKey) private var voiceBroadcastEnabled = true
    @AppStorage(AppSettings.voiceBroadcastIntervalKMKey) private var voiceBroadcastIntervalKM = 1
    @AppStorage(AppSettings.longStationaryReminderEnabledKey) private var longStationaryReminderEnabled = true
    @AppStorage(AppSettings.avatarHeadlightEnabledKey) private var avatarHeadlightEnabled = true

    @State private var showComingSoon = false
    @State private var comingSoonTitle = ""
    @State private var showGPXImporter = false
    @State private var gpxImportError: String?
    @State private var gpxImportPreview: GPXImportPreview?
    @State private var selectedGPXFileName: String?
    @State private var selectedImportCityKey: String = ""
    @State private var gpxImportProgress: Double = 0
    @State private var gpxImportProgressText: String = L10n.t("gpx_import_progress_idle")
    @State private var isParsingGPX = false
    @State private var isImportingGPX = false

    private var appearance: MapAppearanceStyle {
        get { MapAppearanceStyle(rawValue: mapAppearanceRaw) ?? .dark }
        nonmutating set { mapAppearanceRaw = newValue.rawValue }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "V\(version)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    mapAppearanceSection
                    trackingAssistSection
                    generalSection
                    accountSection
                    infoSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
            .background(FigmaTheme.mutedBackground.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                settingsHeader
            }
            .alert("Coming Soon", isPresented: $showComingSoon) {
                Button(L10n.t("ok"), role: .cancel) {}
            } message: {
                Text(String(format: L10n.t("coming_soon_message"), comingSoonTitle))
            }
        }
    }

    private var settingsHeader: some View {
        HStack {
            Color.clear
                .frame(width: 42, height: 42)

            Spacer()

            Text(L10n.t("settings_title"))
                .appHeaderStyle()
                .foregroundColor(FigmaTheme.text)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.14))
                .frame(height: 0.8)
        }
    }

    private var mapAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("MAP APPEARANCE")

            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("settings_map_appearance_desc"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)

                segmentedContainer {
                    segmentButton(
                        title: "Dark",
                        isSelected: appearance == .dark,
                        action: {
                            appearance = .dark
                            MapAppearanceSettings.apply(.dark)
                        }
                    )
                    segmentButton(
                        title: "Day",
                        isSelected: appearance == .light,
                        action: {
                            appearance = .light
                            MapAppearanceSettings.apply(.light)
                        }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)
        }
    }

    private var trackingAssistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("TRACKING ASSIST")

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("settings_voice_broadcast_title"))
                            .font(.system(size: 30 / 2, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        Text(L10n.t("settings_voice_broadcast_desc"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    figmaToggle(isOn: $voiceBroadcastEnabled)
                }

                segmentedContainer {
                    segmentButton(title: "1 km", isSelected: voiceBroadcastIntervalKM == 1) {
                        voiceBroadcastIntervalKM = 1
                    }
                    segmentButton(title: "2 km", isSelected: voiceBroadcastIntervalKM == 2) {
                        voiceBroadcastIntervalKM = 2
                    }
                    segmentButton(title: "5 km", isSelected: voiceBroadcastIntervalKM == 5) {
                        voiceBroadcastIntervalKM = 5
                    }
                }
                .opacity(voiceBroadcastEnabled ? 1 : 0.45)
                .allowsHitTesting(voiceBroadcastEnabled)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("settings_stationary_reminder_title"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        Text(L10n.t("settings_stationary_reminder_desc"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    figmaToggle(isOn: $longStationaryReminderEnabled)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("settings_avatar_headlight_title"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        Text(L10n.t("settings_avatar_headlight_desc"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    figmaToggle(isOn: $avatarHeadlightEnabled)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .figmaSurfaceCard(radius: 30)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("GENERAL")

            VStack(spacing: 10) {
                NavigationLink {
                    gpxImportEntryView
                } label: {
                    settingsRowLabel(title: "IMPORT GPX", icon: "map", iconColor: FigmaTheme.primary)
                }
                .buttonStyle(.plain)

                settingsRow(title: "NOTIFICATIONS", icon: "bell", iconColor: FigmaTheme.secondary) {
                    showPlaceholder("Notifications")
                }

                NavigationLink {
                    DebugChinaTestModule()
                        .navigationTitle(L10n.t("debug_tools_title"))
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    settingsRowLabel(
                        title: "DEBUG TOOLS",
                        icon: "wrench.and.screwdriver",
                        iconColor: .black.opacity(0.68),
                        badgeText: "DEV",
                        rowHeight: 74
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ACCOUNT")

            VStack(spacing: 10) {
                NavigationLink {
                    AccountCenterView()
                } label: {
                    settingsRowLabel(title: "ACCOUNT CENTER", icon: "person.crop.circle", iconColor: FigmaTheme.primary)
                }
                .buttonStyle(.plain)

                settingsRow(title: "SUBSCRIPTION", icon: "creditcard", iconColor: FigmaTheme.primary) {
                    showPlaceholder("Subscription")
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("INFORMATION")

            VStack(spacing: 10) {
                settingsRow(
                    title: "CHECK FOR\nUPDATES",
                    icon: "sparkles",
                    iconColor: FigmaTheme.secondary,
                    badgeText: appVersionText,
                    rowHeight: 88
                ) {
                    showPlaceholder("Check for Updates")
                }

                settingsRow(title: "ABOUT US", icon: "info.circle", iconColor: .black.opacity(0.75)) {
                    showPlaceholder("About Us")
                }

                settingsRow(title: "PRIVACY POLICY", icon: "shield", iconColor: .black.opacity(0.75)) {
                    showPlaceholder("Privacy Policy")
                }
            }
        }
    }

    private var gpxImportEntryView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("gpx_import_entry_title"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(FigmaTheme.text)

                    Text(L10n.t("gpx_import_entry_desc"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                }
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("gpx_import_upload_block_title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.76))

                    if let selectedGPXFileName {
                        Text(String(format: L10n.t("gpx_import_selected_file"), selectedGPXFileName))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(FigmaTheme.subtext)
                            .lineLimit(2)
                    }

                    Button {
                        showGPXImporter = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text(L10n.t("gpx_import_select_file"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(FigmaTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .figmaSurfaceCard(radius: 22)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("gpx_import_conversion_progress"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.76))

                    Text(gpxImportProgressText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                        .lineLimit(2)

                    ProgressView(value: gpxImportProgress, total: 1)
                        .tint(FigmaTheme.primary)

                    Text("\(Int((gpxImportProgress * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.5))
                }
                .padding(16)
                .figmaSurfaceCard(radius: 22)
                .opacity(isParsingGPX || gpxImportProgress > 0 ? 1 : 0.72)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(FigmaTheme.mutedBackground.ignoresSafeArea())
        .navigationTitle(L10n.t("import_gpx_title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Import Failed", isPresented: Binding(
            get: { gpxImportError != nil },
            set: { if !$0 { gpxImportError = nil } }
        )) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(gpxImportError ?? "")
        }
        .fileImporter(
            isPresented: $showGPXImporter,
            allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml],
            allowsMultipleSelection: false
        ) { result in
            handleGPXFileSelection(result)
        }
        .sheet(item: $gpxImportPreview) { preview in
            gpxImportSheet(preview)
        }
    }

    @ViewBuilder
    private func segmentedContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(3)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(FigmaTheme.mutedBackground)
        )
    }

    private func segmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                )
                .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func figmaToggle(isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn.wrappedValue ? FigmaTheme.primary : Color.black.opacity(0.2))
                    .frame(width: 56, height: 32)

                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 4)
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(FigmaTheme.text.opacity(0.42))
            .padding(.horizontal, 4)
    }

    private func settingsRow(
        title: String,
        icon: String,
        iconColor: Color,
        badgeText: String? = nil,
        rowHeight: CGFloat = 68,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRowLabel(
                title: title,
                icon: icon,
                iconColor: iconColor,
                badgeText: badgeText,
                rowHeight: rowHeight
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsRowLabel(
        title: String,
        icon: String,
        iconColor: Color,
        badgeText: String? = nil,
        rowHeight: CGFloat = 68
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(FigmaTheme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(FigmaTheme.mutedBackground)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.46))
        }
        .padding(.horizontal, 20)
        .frame(minHeight: rowHeight)
        .figmaSurfaceCard(radius: 34)
    }

    private func showPlaceholder(_ title: String) {
        comingSoonTitle = title
        showComingSoon = true
    }

    private func handleGPXFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
                return
            }
            gpxImportError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await parseSelectedGPXFile(url)
            }
        }
    }

    @MainActor
    private func parseSelectedGPXFile(_ url: URL) async {
        selectedGPXFileName = url.lastPathComponent
        gpxImportPreview = nil
        selectedImportCityKey = ""
        isParsingGPX = true
        gpxImportProgress = 0.02
        gpxImportProgressText = L10n.t("gpx_import_progress_reading")

        var didAccess = false
        if url.startAccessingSecurityScopedResource() {
            didAccess = true
        }
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
            isParsingGPX = false
        }

        do {
            let data = try Data(contentsOf: url)
            gpxImportProgress = 0.1
            let preview = try await GPXImportService.buildPreview(
                data: data,
                fileName: url.deletingPathExtension().lastPathComponent
            ) { progress, text in
                gpxImportProgress = progress
                gpxImportProgressText = text
            }
            gpxImportPreview = preview
            selectedImportCityKey = preview.defaultCityKey ?? preview.detectedCityCandidates.first?.cityKey ?? ""
            gpxImportProgress = 1
            gpxImportProgressText = L10n.t("gpx_import_progress_done")
        } catch {
            gpxImportProgress = 0
            gpxImportProgressText = L10n.t("gpx_import_progress_idle")
            gpxImportError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func gpxImportSheet(_ preview: GPXImportPreview) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(preview.fileName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Text(String(format: L10n.t("gpx_import_points_distance"), preview.points.count, preview.distanceText))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(FigmaTheme.subtext)

                Text(L10n.t("gpx_import_choose_detected_city"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.text.opacity(0.72))

                if preview.detectedCityCandidates.isEmpty {
                    Text(L10n.t("gpx_import_no_detected_city"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(FigmaTheme.subtext)
                        .padding(.vertical, 4)
                } else {
                    List {
                        ForEach(preview.detectedCityCandidates, id: \.cityKey) { option in
                            Button {
                                selectedImportCityKey = option.cityKey
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(FigmaTheme.text)
                                        if let iso2 = option.iso2, !iso2.isEmpty {
                                            Text(iso2.uppercased())
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(FigmaTheme.subtext)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selectedImportCityKey == option.cityKey ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedImportCityKey == option.cityKey ? FigmaTheme.primary : .black.opacity(0.3))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }

                Button {
                    Task {
                        await confirmImportGPX(preview)
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isImportingGPX {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(L10n.t("import"))
                                .font(.system(size: 15, weight: .bold))
                        }
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(selectedImportCityKey.isEmpty ? Color.black.opacity(0.25) : FigmaTheme.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(selectedImportCityKey.isEmpty || isImportingGPX)
            }
            .padding(18)
            .background(FigmaTheme.mutedBackground.ignoresSafeArea())
            .navigationTitle(L10n.t("import_gpx_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("cancel")) {
                        gpxImportPreview = nil
                    }
                }
            }
        }
    }

    @MainActor
    private func confirmImportGPX(_ preview: GPXImportPreview) async {
        guard !selectedImportCityKey.isEmpty else { return }
        guard !isImportingGPX else { return }
        guard let selected = preview.detectedCityCandidates.first(where: { $0.cityKey == selectedImportCityKey }) else { return }

        isImportingGPX = true
        defer { isImportingGPX = false }

        var route = preview.route
        route.startCityKey = selected.cityKey
        route.endCityKey = selected.cityKey
        route.cityKey = selected.cityKey
        route.canonicalCity = selected.name
        route.currentCity = selected.name
        route.cityName = selected.name
        route.countryISO2 = selected.iso2
        route.exploreMode = .city
        route.ensureThumbnail(maxPoints: 280)

        journeyStore.addCompletedJourney(route)
        cityCache.rebuildFromJourneyStore()

        let lifelogTimeline = preview.points.enumerated().map { idx, point -> (coord: CoordinateCodable, timestamp: Date) in
            let ts = point.timestamp ?? GPXImportService.fallbackTimestamp(for: idx, total: preview.points.count, start: route.startTime, end: route.endTime)
            return (coord: point.coordinate, timestamp: ts)
        }
        lifelogStore.importExternalTrack(points: lifelogTimeline)

        gpxImportPreview = nil
    }
}

private struct GPXImportPoint: Identifiable {
    let id = UUID()
    let coordinate: CoordinateCodable
    let timestamp: Date?
}

private struct GPXImportCityCandidate: Identifiable {
    var id: String { cityKey }
    let cityKey: String
    let name: String
    let iso2: String?
}

private struct GPXImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let points: [GPXImportPoint]
    let route: JourneyRoute
    let distanceMeters: Double
    let detectedCityCandidates: [GPXImportCityCandidate]
    let defaultCityKey: String?

    var distanceText: String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceMeters / 1000)
        }
        return String(format: "%.0f m", distanceMeters)
    }
}

private enum GPXImportService {
    static func buildPreview(
        data: Data,
        fileName: String,
        progress: (@MainActor @Sendable (_ progress: Double, _ status: String) -> Void)? = nil
    ) async throws -> GPXImportPreview {
        await progress?(0.2, L10n.t("gpx_import_progress_parsing"))
        let parsed = try GPXXMLParser.parse(data: data)
        guard parsed.count >= 2 else {
            throw NSError(domain: "GPXImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "GPX 轨迹点不足（至少需要 2 个点）。"])
        }

        await progress?(0.45, L10n.t("gpx_import_progress_building"))
        let coords = parsed.map(\.coordinate)
        let points = parsed.map { GPXImportPoint(coordinate: $0.coordinate, timestamp: $0.timestamp) }
        let distance = totalDistanceMeters(coords: coords)
        let start = parsed.first?.timestamp ?? Date()
        let end = parsed.last?.timestamp ?? start
        await progress?(0.55, L10n.t("gpx_import_progress_detecting"))
        let cityCandidates = await detectCities(from: parsed) { done, total in
            guard total > 0 else { return }
            let fraction = Double(done) / Double(total)
            let currentProgress = min(0.95, 0.55 + fraction * 0.4)
            let text = String(format: L10n.t("gpx_import_progress_detecting_format"), done, total)
            await progress?(currentProgress, text)
        }
        let preferredCity = cityCandidates.first

        var route = JourneyRoute()
        route.id = UUID().uuidString
        route.startTime = start
        route.endTime = end
        route.distance = distance
        route.coordinates = coords
        route.thumbnailCoordinates = downsample(coords: coords, maxPoints: 280)
        route.trackingMode = .daily
        route.visibility = .private
        route.customTitle = fileName
        route.activityTag = "GPX Import"
        route.exploreMode = .city

        if let preferredCity {
            route.startCityKey = preferredCity.cityKey
            route.endCityKey = preferredCity.cityKey
            route.cityKey = preferredCity.cityKey
            route.canonicalCity = preferredCity.name
            route.currentCity = preferredCity.name
            route.cityName = preferredCity.name
            route.countryISO2 = preferredCity.iso2
        }

        await progress?(1, L10n.t("gpx_import_progress_done"))

        return GPXImportPreview(
            fileName: fileName,
            points: points,
            route: route,
            distanceMeters: distance,
            detectedCityCandidates: cityCandidates,
            defaultCityKey: preferredCity?.cityKey
        )
    }

    static func fallbackTimestamp(for index: Int, total: Int, start: Date?, end: Date?) -> Date {
        guard total > 1 else { return end ?? start ?? Date() }
        let startValue = start ?? end ?? Date()
        let endValue = end ?? startValue
        let span = max(0, endValue.timeIntervalSince(startValue))
        guard span > 0 else { return endValue }
        let t = Double(index) / Double(max(total - 1, 1))
        return startValue.addingTimeInterval(span * t)
    }

    private static func detectCities(
        from points: [GPXRawPoint],
        progress: (@Sendable (_ done: Int, _ total: Int) async -> Void)? = nil
    ) async -> [GPXImportCityCandidate] {
        let sample = sampledPoints(points, maxSamples: 5)
        var out: [GPXImportCityCandidate] = []
        var seen = Set<String>()

        if sample.isEmpty {
            await progress?(0, 0)
            return out
        }

        for (idx, point) in sample.enumerated() {
            let location = CLLocation(latitude: point.coordinate.lat, longitude: point.coordinate.lon)
            let result = await canonicalResultWithRetry(for: location, retryCount: 1)
            if let result, !seen.contains(result.cityKey) {
                seen.insert(result.cityKey)
                out.append(
                    GPXImportCityCandidate(
                        cityKey: result.cityKey,
                        name: result.cityName,
                        iso2: result.iso2
                    )
                )
            }
            await progress?(idx + 1, sample.count)
        }
        await progress?(sample.count, sample.count)
        return out
    }

    private static func canonicalResultWithRetry(for location: CLLocation, retryCount: Int) async -> ReverseGeocodeService.CanonicalResult? {
        if let value = await ReverseGeocodeService.shared.canonical(for: location) {
            return value
        }
        guard retryCount > 0 else { return nil }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        return await canonicalResultWithRetry(for: location, retryCount: retryCount - 1)
    }

    private static func sampledPoints(_ points: [GPXRawPoint], maxSamples: Int) -> [GPXRawPoint] {
        guard points.count > maxSamples else { return points }
        guard maxSamples > 1 else { return [points[0]] }

        var out: [GPXRawPoint] = []
        out.reserveCapacity(maxSamples)
        for idx in 0..<maxSamples {
            let t = Double(idx) / Double(maxSamples - 1)
            let raw = Int((t * Double(points.count - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(points[min(max(raw, 0), points.count - 1)])
        }
        return out
    }

    private static func downsample(coords: [CoordinateCodable], maxPoints: Int) -> [CoordinateCodable] {
        guard coords.count > maxPoints, maxPoints >= 2 else { return coords }
        let n = coords.count
        let m = maxPoints
        var out: [CoordinateCodable] = []
        out.reserveCapacity(m)
        for i in 0..<m {
            let t = Double(i) / Double(m - 1)
            let idx = Int((t * Double(n - 1)).rounded(.toNearestOrAwayFromZero))
            out.append(coords[min(max(idx, 0), n - 1)])
        }
        return out
    }

    private static func totalDistanceMeters(coords: [CoordinateCodable]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].lat, longitude: coords[i - 1].lon)
            let b = CLLocation(latitude: coords[i].lat, longitude: coords[i].lon)
            total += b.distance(from: a)
        }
        return total
    }
}

private struct GPXRawPoint {
    let coordinate: CoordinateCodable
    let timestamp: Date?
}

private enum GPXXMLParser {
    static func parse(data: Data) throws -> [GPXRawPoint] {
        let parser = XMLParser(data: data)
        let delegate = GPXXMLParserDelegate()
        parser.delegate = delegate
        let success = parser.parse()
        if success {
            return delegate.points
        }
        let message = parser.parserError?.localizedDescription ?? "Unknown parse error"
        throw NSError(domain: "GPXImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "GPX 解析失败：\(message)"])
    }
}

private final class GPXXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var points: [GPXRawPoint] = []

    private var currentLat: Double?
    private var currentLon: Double?
    private var currentTime: Date?
    private var currentText = ""
    private var readingTime = false

    private lazy var iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let lower = elementName.lowercased()
        if lower == "trkpt" || lower == "rtept" {
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentTime = nil
        } else if lower == "time" {
            currentText = ""
            readingTime = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingTime {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let lower = elementName.lowercased()
        if lower == "time" {
            let raw = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            currentTime = parseDate(raw)
            readingTime = false
            currentText = ""
            return
        }

        if lower == "trkpt" || lower == "rtept" {
            defer {
                currentLat = nil
                currentLon = nil
                currentTime = nil
            }
            guard let lat = currentLat, let lon = currentLon else { return }
            guard abs(lat) <= 90, abs(lon) <= 180 else { return }
            points.append(
                GPXRawPoint(
                    coordinate: CoordinateCodable(lat: lat, lon: lon),
                    timestamp: currentTime
                )
            )
        }
    }

    private func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        if let value = iso8601.date(from: raw) {
            return value
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }
}
