import SwiftUI
import MapKit
import CoreLocation
import UIKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

private struct JourneyRouteSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ViewController { ViewController() }
    func updateUIViewController(_ uiViewController: ViewController, context: Context) {}

    final class ViewController: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}

struct MyJourneysView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var cityCache: CityCache
    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue
    let routeDetailReadOnly: Bool
    let routeDetailHeaderTitle: String?
    let showHeader: Bool
    let headerTitle: String?

    init(
        routeDetailReadOnly: Bool = false,
        routeDetailHeaderTitle: String? = nil,
        showHeader: Bool = true,
        headerTitle: String? = nil
    ) {
        self.routeDetailReadOnly = routeDetailReadOnly
        self.routeDetailHeaderTitle = routeDetailHeaderTitle
        self.showHeader = showHeader
        self.headerTitle = headerTitle
    }

    @State private var showFilterPopover = false
    @State private var monthCursor = Date()
    @State private var selectedStartDate: Date? = nil
    @State private var selectedEndDate: Date? = nil
    @State private var likesByJourney: [String: Int] = [:]
    @State private var visibilityUpdatingIDs: Set<String> = []
    @State private var localizedCityNameByKey: [String: String] = [:]
    @State private var permissionJourneyID: String? = nil
    @State private var likesJourneyID: String? = nil
    @State private var pendingVisibility: JourneyVisibility = .private
    @State private var journeyLikersByJourneyID: [String: [JourneyLiker]] = [:]
    @State private var likersLoadingJourneyID: String? = nil
    @State private var likersErrorByJourneyID: [String: String] = [:]
    @State private var showMessage = false
    @State private var messageText = ""

    private var allJourneys: [JourneyRoute] {
        store.journeys
            .filter { !$0.isTooShort && $0.endTime != nil && !$0.coordinates.isEmpty }
            .sorted { ($0.endTime ?? .distantPast) > ($1.endTime ?? .distantPast) }
    }

    private var filteredJourneys: [JourneyRoute] {
        guard let startDate = selectedStartDate else { return allJourneys }
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        let upperBase = selectedEndDate ?? startDate
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: upperBase)) ?? upperBase

        return allJourneys.filter { j in
            guard let date = j.endTime ?? j.startTime else { return false }
            return date >= start && date < endExclusive
        }
    }

    private var likesRequestKey: String {
        allJourneys.map(\.id).sorted().joined(separator: ",")
    }

    private var permissionJourney: JourneyRoute? {
        guard let permissionJourneyID else { return nil }
        return store.journeys.first(where: { $0.id == permissionJourneyID })
    }

    private var likesJourney: JourneyRoute? {
        guard let likesJourneyID else { return nil }
        return store.journeys.first(where: { $0.id == likesJourneyID })
    }

    private var likesSheetDetents: Set<PresentationDetent> {
        guard let likesJourney else { return [.height(276), .large] }
        let likerCount = journeyLikersByJourneyID[likesJourney.id]?.count ?? 0
        let compactHeight = min(520, max(276, 194 + CGFloat(max(likerCount, 1)) * 56))
        return [.height(compactHeight), .large]
    }

    private var filterChipTitle: String {
        let cal = Calendar.current
        guard let start = selectedStartDate else { return L10n.t("all_time") }
        let end = selectedEndDate ?? start
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d"
        if cal.isDate(start, inSameDayAs: end) {
            return df.string(from: start)
        }
        return "\(df.string(from: start)) - \(df.string(from: end))"
    }

    private var resolvedHeaderTitle: String {
        let trimmed = headerTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.t("my_journeys_title") : trimmed
    }

    var body: some View {
        ZStack {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                if showHeader {
                    header
                }
                listSection
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            refreshJourneyLikes()
        }
        .onChange(of: likesRequestKey) { _ in
            refreshJourneyLikes()
        }
        .task(id: preheatTaskKey) {
            await JourneyRouteSnapshotLoader.preheat(
                journeys: filteredJourneys,
                appearanceRaw: mapAppearanceRaw,
                limit: 8
            )
        }
        .task(id: cityLocalizationTaskKey) {
            await refreshCityLocalizations()
        }
        .sheet(
            isPresented: Binding(
                get: { permissionJourneyID != nil },
                set: { if !$0 { permissionJourneyID = nil } }
            )
        ) {
            if let permissionJourney {
                JourneyVisibilitySheet(
                    journey: permissionJourney,
                    pendingVisibility: $pendingVisibility,
                    isSubmitting: visibilityUpdatingIDs.contains(permissionJourney.id),
                    onApply: applyPendingVisibilityChange
                )
                .presentationBackground(FigmaTheme.background)
                .presentationCornerRadius(28)
                .presentationDetents([.height(352)])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { likesJourneyID != nil },
                set: { if !$0 { likesJourneyID = nil } }
            )
        ) {
            if let likesJourney {
                JourneyLikesSheet(
                    journey: likesJourney,
                    displayCityName: resolvedDisplayCityName(for: likesJourney),
                    likers: journeyLikersByJourneyID[likesJourney.id] ?? [],
                    isLoading: likersLoadingJourneyID == likesJourney.id,
                    errorMessage: likersErrorByJourneyID[likesJourney.id],
                    onRetry: { loadJourneyLikers(for: likesJourney) },
                    onEditVisibility: {
                        likesJourneyID = nil
                        presentVisibilitySheet(for: likesJourney)
                    }
                )
                .presentationBackground(FigmaTheme.background)
                .presentationCornerRadius(28)
                .presentationDetents(likesSheetDetents)
                .presentationDragIndicator(.visible)
            }
        }
        .alert(L10n.t("prompt"), isPresented: $showMessage) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(messageText)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(resolvedHeaderTitle)
                    .appHeaderStyle()

                Spacer()

                VStack(spacing: 2) {
                    Button {
                        showFilterPopover.toggle()
                    } label: {
                        Image(systemName: selectedStartDate == nil ? "calendar" : "calendar.badge.clock")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFilterPopover, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        JourneyCalendarRangePopover(
                            monthCursor: $monthCursor,
                            selectedStartDate: $selectedStartDate,
                            selectedEndDate: $selectedEndDate,
                            journeys: allJourneys,
                            onRangeCompleted: {
                                showFilterPopover = false
                            },
                            onApply: {
                                showFilterPopover = false
                            },
                            onClear: {
                                selectedStartDate = nil
                                selectedEndDate = nil
                                showFilterPopover = false
                            }
                        )
                        .presentationCompactAdaptation(.popover)
                    }

                    if selectedStartDate != nil {
                        Text(filterChipTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.black.opacity(0.58))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Text(String(format: L10n.t("journeys_count"), filteredJourneys.count))
                .appCaptionStyle()
                .padding(.bottom, 10)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }

    private var preheatTaskKey: String {
        let ids = filteredJourneys.prefix(8).map(\.id).joined(separator: ",")
        return "\(mapAppearanceRaw)|\(ids)"
    }

    private var cityLocalizationTaskKey: String {
        allJourneys
            .map { "\($0.id)|\($0.startCityKey ?? $0.cityKey)" }
            .joined(separator: ",")
    }

    private var cachedCitiesByKey: [String: CachedCity] {
        Dictionary(
            uniqueKeysWithValues: cityCache.cachedCities
                .filter { !($0.isTemporary ?? false) }
                .map { ($0.id, $0) }
        )
    }

    private func refreshCityLocalizations() async {
        var coordByKey: [String: CLLocationCoordinate2D] = [:]
        for journey in allJourneys {
            let key = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key != "Unknown|", coordByKey[key] == nil else { continue }
            if let start = journey.startCoordinate, start.isValid {
                coordByKey[key] = start
            }
        }

        for (key, coord) in coordByKey {
            if localizedCityNameByKey[key] != nil { continue }

            if let cachedCity = cachedCitiesByKey[key] {
                let title = CityPlacemarkResolver.displayTitle(
                    cityKey: cachedCity.id,
                    iso2: cachedCity.countryISO2,
                    fallbackTitle: cachedCity.name,
                    availableLevelNamesRaw: cachedCity.reservedAvailableLevelNames,
                    storedAvailableLevelNamesLocaleID: cachedCity.reservedAvailableLevelNamesLocaleID,
                    parentRegionKey: cachedCity.reservedParentRegionKey,
                    preferredLevel: cachedCity.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                    localizedDisplayNameByLocale: cachedCity.localizedDisplayNameByLocale,
                    locale: .current
                )
                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run { localizedCityNameByKey[key] = title }
                    continue
                }
            }

            let parentRegionKey = cachedCitiesByKey[key]?.reservedParentRegionKey

            if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: parentRegionKey),
               !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityNameByKey[key] = cached }
                continue
            }

            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: parentRegionKey),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityNameByKey[key] = title }
            }
        }
    }

    private func resolvedDisplayCityName(for journey: JourneyRoute) -> String {
        JourneyCityNamePresentation.title(
            for: journey,
            localizedCityNameByKey: localizedCityNameByKey,
            cachedCitiesByKey: cachedCitiesByKey
        )
    }

    private var listSection: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 24) {
                ForEach(filteredJourneys, id: \.id) { j in
                    NavigationLink {
                        JourneyRouteDetailView(
                            journeyID: j.id,
                            isReadOnly: routeDetailReadOnly,
                            headerTitle: routeDetailHeaderTitle
                        )
                    } label: {
                        JourneyCardRow(
                            journey: j,
                            displayCityName: resolvedDisplayCityName(for: j),
                            likeCount: likesByJourney[j.id] ?? 0,
                            isVisibilityUpdating: visibilityUpdatingIDs.contains(j.id),
                            isReadOnly: routeDetailReadOnly,
                            onActionTap: { tapped in
                                guard !routeDetailReadOnly else { return }
                                if tapped.visibility == .private {
                                    presentVisibilitySheet(for: tapped)
                                } else {
                                    presentLikesSheet(for: tapped)
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 52)
        }
    }

    private func refreshJourneyLikes() {
        let ids = allJourneys.map(\.id)
        guard !ids.isEmpty else {
            likesByJourney = [:]
            return
        }

        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            likesByJourney = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
            return
        }

        Task {
            do {
                let ownerUserID = sessionStore.accountUserID
                let remote = try await BackendAPIClient.shared.fetchJourneyLikeStats(
                    token: token,
                    journeyIDs: ids,
                    ownerUserID: ownerUserID
                )
                await MainActor.run {
                    var merged = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
                    for (id, value) in remote {
                        merged[id] = max(0, value.likes)
                    }
                    likesByJourney = merged
                }
            } catch {
                await MainActor.run {
                    likesByJourney = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
                }
            }
        }
    }

    @MainActor
    private func presentVisibilitySheet(for journey: JourneyRoute) {
        guard JourneyVisibilityPolicy.canEditVisibility(
            current: journey.visibility,
            target: journey.visibility,
            isLoggedIn: sessionStore.isLoggedIn
        ) else {
            showLoginRequiredMessage()
            return
        }
        permissionJourneyID = journey.id
        pendingVisibility = journey.visibility
    }

    @MainActor
    private func presentLikesSheet(for journey: JourneyRoute) {
        likesJourneyID = journey.id
        loadJourneyLikers(for: journey)
    }

    @MainActor
    private func applyPendingVisibilityChange() {
        guard let journey = permissionJourney else { return }
        guard !visibilityUpdatingIDs.contains(journey.id) else { return }

        let target = pendingVisibility
        let decision = JourneyVisibilityPolicy.evaluateChange(
            current: journey.visibility,
            target: target,
            isLoggedIn: sessionStore.isLoggedIn,
            journeyDistance: journey.distance,
            memoryCount: journey.memories.count
        )
        guard decision.isAllowed else {
            permissionJourneyID = nil
            showVisibilityDeniedMessage(reason: decision.reason)
            return
        }

        var updated = journey
        updated.visibility = target

        visibilityUpdatingIDs.insert(journey.id)
        store.applyBulkCompletedUpdates([updated])
        permissionJourneyID = nil

        Task {
            defer { visibilityUpdatingIDs.remove(journey.id) }
            guard BackendConfig.isEnabled,
                  sessionStore.currentAccessToken?.isEmpty == false else { return }

            do {
                try await JourneyCloudMigrationService.syncJourneyVisibilityChange(
                    journey: updated,
                    sessionStore: sessionStore,
                    cityCache: cityCache
                )
                refreshJourneyLikes()
            } catch {
                print("❌ visibility cloud sync failed:", error.localizedDescription)
            }
        }
    }

    @MainActor
    private func loadJourneyLikers(for journey: JourneyRoute) {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            journeyLikersByJourneyID[journey.id] = []
            likersErrorByJourneyID[journey.id] = nil
            return
        }

        likersLoadingJourneyID = journey.id
        likersErrorByJourneyID[journey.id] = nil
        Task {
            do {
                let all = try await BackendAPIClient.shared.fetchNotifications(token: token, unreadOnly: false)
                let journeyLikes = all
                    .filter { $0.type == "journey_like" && $0.journeyID == journey.id }
                    .sorted { $0.createdAt > $1.createdAt }

                var seen = Set<String>()
                var out: [JourneyLiker] = []
                for item in journeyLikes {
                    let key = item.fromUserID ?? item.fromDisplayName ?? item.id
                    if seen.contains(key) { continue }
                    seen.insert(key)
                    let name = (item.fromDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? (item.fromDisplayName ?? "")
                        : (item.fromUserID ?? L10n.t("unknown"))
                    out.append(JourneyLiker(id: key, name: name, likedAt: item.createdAt))
                }

                await MainActor.run {
                    journeyLikersByJourneyID[journey.id] = out
                    likersErrorByJourneyID[journey.id] = nil
                    if likersLoadingJourneyID == journey.id {
                        likersLoadingJourneyID = nil
                    }
                }
            } catch {
                await MainActor.run {
                    journeyLikersByJourneyID[journey.id] = []
                    likersErrorByJourneyID[journey.id] = error.localizedDescription
                    if likersLoadingJourneyID == journey.id {
                        likersLoadingJourneyID = nil
                    }
                }
            }
        }
    }

    @MainActor
    private func showLoginRequiredMessage() {
        messageText = "请先登录后再修改 Journey 权限"
        showMessage = true
    }

    @MainActor
    private func showVisibilityDeniedMessage(reason: JourneyVisibilityPolicy.DenialReason?) {
        if let reason {
            messageText = L10n.t(reason.localizationKey)
        } else {
            messageText = "无法修改 Journey 权限"
        }
        showMessage = true
    }
}

private struct JourneyLiker: Identifiable {
    let id: String
    let name: String
    let likedAt: Date
}

enum JourneyVisibilitySheetAccentStyle: Equatable {
    case neutral
    case accent
}

struct JourneyVisibilitySheetOptionPresentation: Equatable {
    let visibility: JourneyVisibility
    let symbolName: String
    let eyebrow: String
    let title: String
    let description: String
    let accentStyle: JourneyVisibilitySheetAccentStyle
}

enum JourneyVisibilitySheetPresentation {
    static let optionPresentations: [JourneyVisibilitySheetOptionPresentation] = [
        JourneyVisibilitySheetOptionPresentation(
            visibility: .private,
            symbolName: "lock.fill",
            eyebrow: "PRIVATE",
            title: L10n.t("visibility_private"),
            description: L10n.t("journey_visibility_private_description"),
            accentStyle: .neutral
        ),
        JourneyVisibilitySheetOptionPresentation(
            visibility: .friendsOnly,
            symbolName: "person.2.fill",
            eyebrow: "FRIENDS",
            title: L10n.t("visibility_friends_only"),
            description: L10n.t("journey_visibility_friends_description"),
            accentStyle: .accent
        )
    ]
}

private struct JourneyVisibilitySheet: View {
    let journey: JourneyRoute
    @Binding var pendingVisibility: JourneyVisibility
    let isSubmitting: Bool
    let onApply: () -> Void

    private var canApply: Bool {
        return !isSubmitting
    }

    private var selectedPresentation: JourneyVisibilitySheetOptionPresentation? {
        JourneyVisibilitySheetPresentation.optionPresentations.first { $0.visibility == pendingVisibility }
    }

    var body: some View {
        JourneySheetScaffold(
            title: L10n.t("journey_change_visibility"),
            subtitle: String(format: L10n.t("journey_current_visibility_format"), journey.visibility.localizedTitle)
        ) {
            lightweightVisibilityToggle

            if let selectedPresentation {
                Text(selectedPresentation.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
                    .lineSpacing(1.5)
                    .padding(.horizontal, 2)
            }

            Button(action: onApply) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(L10n.t("journey_confirm_change"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canApply ? UITheme.softBlack : Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!canApply)
            .buttonStyle(.plain)
        }
    }

    private var lightweightVisibilityToggle: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(pendingVisibility == .friendsOnly ? UITheme.accent.opacity(0.12) : Color.black.opacity(0.05))
                    .frame(width: 34, height: 34)

                Image(systemName: pendingVisibility == .friendsOnly ? "person.2.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(pendingVisibility == .friendsOnly ? UITheme.accent : UITheme.softBlack)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("journey_change_visibility"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(UITheme.softBlack)

                Text(pendingVisibility.localizedTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: friendsVisibilityBinding)
                .labelsHidden()
                .tint(UITheme.accent)
                .scaleEffect(0.88)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var friendsVisibilityBinding: Binding<Bool> {
        Binding(
            get: { pendingVisibility == .friendsOnly },
            set: { isOn in
                pendingVisibility = isOn ? .friendsOnly : .private
            }
        )
    }
}

private struct JourneySheetScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            FigmaTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(UITheme.softBlack)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                }

                content

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct JourneyLikesSheet: View {
    let journey: JourneyRoute
    let displayCityName: String
    let likers: [JourneyLiker]
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void
    let onEditVisibility: () -> Void

    private var title: String {
        journey.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (journey.customTitle ?? "")
            : displayCityName
    }

    var body: some View {
        JourneySheetScaffold(title: L10n.t("journey_likes_title"), subtitle: title) {
            Button(action: onEditVisibility) {
                HStack {
                    Text(L10n.t("journey_change_permission"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(UITheme.softBlack)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if isLoading {
                statusCard(icon: "clock", text: L10n.t("journey_likes_loading"))
            } else if let errorMessage, !errorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: L10n.t("journey_loading_failed_format"), errorMessage))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.red.opacity(0.82))
                    Button(L10n.t("retry"), action: onRetry)
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundColor(UITheme.softBlack)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.red.opacity(0.10), lineWidth: 1)
                )
            } else if likers.isEmpty {
                statusCard(icon: "heart", text: L10n.t("journey_no_likes_yet"))
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(likers) { liker in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.black.opacity(0.05))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        Text(String(liker.name.prefix(1)).uppercased())
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(UITheme.softBlack.opacity(0.75))
                                    }

                                Text(liker.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(UITheme.softBlack)
                                Spacer()
                                Text(Self.timeText(from: liker.likedAt))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FigmaTheme.subtext)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                            .background(Color.black.opacity(0.02))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func statusCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            if icon == "clock" {
                ProgressView()
                    .scaleEffect(0.9)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(FigmaTheme.subtext)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private static func timeText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct JourneyCalendarDay: Identifiable {
    let id = UUID()
    let date: Date?
    let number: Int
}

private struct JourneyCalendarRangePopover: View {
    @Binding var monthCursor: Date
    @Binding var selectedStartDate: Date?
    @Binding var selectedEndDate: Date?

    let journeys: [JourneyRoute]
    let onRangeCompleted: () -> Void
    let onApply: () -> Void
    let onClear: () -> Void

    private var panelMonthTitle: String {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMMM yyyy"
        return df.string(from: monthCursor).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("date_range"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)

            HStack(spacing: 18) {
                Button {
                    monthCursor = Calendar.current.date(byAdding: .month, value: -1, to: monthCursor) ?? monthCursor
                } label: {
                    circleChevron("chevron.left")
                }

                Text(panelMonthTitle)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)

                Button {
                    monthCursor = Calendar.current.date(byAdding: .month, value: 1, to: monthCursor) ?? monthCursor
                } label: {
                    circleChevron("chevron.right")
                }
            }

            monthGrid

            HStack(spacing: 8) {
                Button(L10n.t("clear")) {
                    onClear()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.78))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.black.opacity(0.08))
                .clipShape(Capsule())

                Button(L10n.t("apply")) {
                    onApply()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Color.black)
                .clipShape(Capsule())
                .disabled(selectedStartDate == nil)
                .opacity(selectedStartDate == nil ? 0.45 : 1.0)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 292)
        .background(Color.white)
    }

    private var monthGrid: some View {
        let cal = Calendar.current
        let days = calendarDays()
        let weekday = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

        return VStack(spacing: 8) {
            HStack {
                ForEach(weekday, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.black.opacity(0.3))
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.id) { day in
                    if let date = day.date {
                        let inRange = isInSelectedRange(date)
                        let isBoundary = isRangeBoundary(date)
                        let hasJourney = hasJourney(on: date)

                        Button {
                            selectDate(date)
                        } label: {
                            Text("\(day.number)")
                                .font(.system(size: 14, weight: isBoundary ? .bold : .medium))
                                .foregroundColor(dayTextColor(hasJourney: hasJourney, inRange: inRange, isBoundary: isBoundary))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(dayBackground(inRange: inRange, isBoundary: isBoundary))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 34)
                    }
                }
            }
        }
    }

    private func selectDate(_ date: Date) {
        let cal = Calendar.current
        let normalized = cal.startOfDay(for: date)

        if selectedStartDate == nil || selectedEndDate != nil {
            selectedStartDate = normalized
            selectedEndDate = nil
            return
        }

        guard let start = selectedStartDate else { return }
        if normalized < start {
            selectedEndDate = start
            selectedStartDate = normalized
        } else {
            selectedEndDate = normalized
        }
        onRangeCompleted()
    }

    private func isInSelectedRange(_ date: Date) -> Bool {
        let cal = Calendar.current
        guard let start = selectedStartDate else { return false }
        let end = selectedEndDate ?? start
        let day = cal.startOfDay(for: date)
        return day >= min(start, end) && day <= max(start, end)
    }

    private func isRangeBoundary(_ date: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        if let start = selectedStartDate, cal.isDate(day, inSameDayAs: start) { return true }
        if let end = selectedEndDate, cal.isDate(day, inSameDayAs: end) { return true }
        return false
    }

    private func hasJourney(on date: Date) -> Bool {
        let cal = Calendar.current
        return journeys.contains {
            guard let d = $0.endTime ?? $0.startTime else { return false }
            return cal.isDate(d, inSameDayAs: date)
        }
    }

    private func dayTextColor(hasJourney: Bool, inRange: Bool, isBoundary: Bool) -> Color {
        if inRange || isBoundary { return .black }
        return hasJourney ? .black : Color.black.opacity(0.18)
    }

    @ViewBuilder
    private func dayBackground(inRange: Bool, isBoundary: Bool) -> some View {
        if isBoundary {
            Color.black.opacity(0.15)
        } else if inRange {
            Color.black.opacity(0.08)
        } else {
            Color.clear
        }
    }

    private func circleChevron(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.black)
            .frame(width: 30, height: 30)
            .background(Color.black.opacity(0.06))
            .clipShape(Circle())
    }

    private func calendarDays() -> [JourneyCalendarDay] {
        let cal = Calendar.current
        guard
            let monthInterval = cal.dateInterval(of: .month, for: monthCursor),
            let monthFirstWeek = cal.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let monthLastWeek = cal.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1))
        else { return [] }

        var cursor = monthFirstWeek.start
        var out: [JourneyCalendarDay] = []
        while cursor < monthLastWeek.end {
            let isInMonth = cal.isDate(cursor, equalTo: monthCursor, toGranularity: .month)
            let n = cal.component(.day, from: cursor)
            out.append(JourneyCalendarDay(date: isInMonth ? cursor : nil, number: n))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }
}

private struct JourneyCardRow: View {
    let journey: JourneyRoute
    let displayCityName: String
    let likeCount: Int
    let isVisibilityUpdating: Bool
    let isReadOnly: Bool
    let onActionTap: (JourneyRoute) -> Void

    @AppStorage(MapAppearanceSettings.storageKey) private var mapAppearanceRaw = MapAppearanceSettings.current.rawValue

    private var mergedTitle: String {
        displayCityName
    }

    private var datePillText: String {
        guard let d = journey.endTime ?? journey.startTime else { return "--" }
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d"
        return df.string(from: d).uppercased()
    }

    private var distanceText: String {
        String(format: "%.1fkm", max(0, journey.distance / 1000.0))
    }

    private var memoriesText: String {
        "\(journey.memories.count)"
    }

    private var durationText: String {
        guard let s = journey.startTime, let e = journey.endTime else { return "--" }
        let sec = max(0, Int(e.timeIntervalSince(s)))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                JourneyRouteSnapshotThumbnail(journey: journey, appearanceRaw: mapAppearanceRaw)
                    .frame(height: 170)
                    .background(Color.black.opacity(0.06))

                Text(datePillText)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.black.opacity(0.72))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.74))
                    .clipShape(Capsule())
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Text(mergedTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black.opacity(0.65))
                        .padding(.top, 2)
                }

                HStack(spacing: 12) {
                    statItem(icon: "clock", text: durationText)
                    statDivider
                    statItem(icon: "location.north.line", text: distanceText)
                    statDivider
                    statItem(icon: "photo.stack", text: memoriesText)

                    Spacer(minLength: 0)

                    if isReadOnly {
                        HStack(spacing: 6) {
                            Image(systemName: journey.visibility == .private ? "lock" : "globe")
                                .font(.system(size: 13, weight: .semibold))
                            Text(journey.visibility.localizedTitle)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(visibilityTextColor)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(visibilityBackgroundColor)
                        .clipShape(Capsule())
                    } else {
                        Button(action: { onActionTap(journey) }) {
                            HStack(spacing: 6) {
                                if isVisibilityUpdating {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(Color.black.opacity(0.58))
                                        .scaleEffect(0.8)
                                } else if journey.visibility == .private {
                                    Image(systemName: "lock")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(JourneyVisibility.private.localizedTitle)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                } else {
                                    Image(systemName: "heart")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("\(likeCount)")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                }
                            }
                            .foregroundColor(visibilityTextColor)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(visibilityBackgroundColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.borderless)
                        .disabled(isVisibilityUpdating)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(UITheme.cardStroke, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func statItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.black.opacity(0.55))

            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.12))
            .frame(width: 1, height: 18)
    }

    private var visibilityTextColor: Color {
        if journey.visibility == .private || isVisibilityUpdating {
            return Color.black.opacity(0.68)
        }
        return Color(red: 76.0 / 255.0, green: 175.0 / 255.0, blue: 124.0 / 255.0)
    }

    private var visibilityBackgroundColor: Color {
        if journey.visibility == .private || isVisibilityUpdating {
            return Color.black.opacity(0.08)
        }
        return Color(red: 230.0 / 255.0, green: 241.0 / 255.0, blue: 233.0 / 255.0)
    }
}

private struct JourneyRouteSnapshotThumbnail: View {
    let journey: JourneyRoute
    let appearanceRaw: String

    @StateObject private var loader = JourneyRouteSnapshotLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "map")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(UITheme.accent.opacity(0.6))

                            Text(L10n.key("preparing_map"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.black.opacity(0.35))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.horizontal, 10)
                    )
            }
        }
        .clipped()
        .onAppear {
            loader.load(journey: journey, appearanceRaw: appearanceRaw)
        }
        .onChange(of: appearanceRaw) { _ in
            loader.load(journey: journey, appearanceRaw: appearanceRaw)
        }
        .onChange(of: journey.id) { _ in
            loader.load(journey: journey, appearanceRaw: appearanceRaw)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

@MainActor
private final class JourneyRouteSnapshotLoader: ObservableObject {
    @Published var image: UIImage?
    private var currentKey: String?
    private var loadTask: Task<Void, Never>?

    nonisolated static func preheat(journeys: [JourneyRoute], appearanceRaw: String, limit: Int) async {
        guard limit > 0 else { return }
        let candidates = Array(journeys.prefix(limit))
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for journey in candidates {
                group.addTask {
                    let key = snapshotKey(for: journey, appearanceRaw: appearanceRaw)
                    if CityImageMemoryCache.shared.image(forKey: key) != nil { return }
                    if let diskImage = await JourneySnapshotDiskCache.shared.image(forKey: key) {
                        CityImageMemoryCache.shared.set(diskImage, forKey: key)
                        return
                    }

                    let img = await JourneySnapshotInFlightStore.shared.image(for: key) {
                        await Task.detached(priority: .utility) {
                            return makeSnapshot(journey: journey, appearanceRaw: appearanceRaw)
                        }.value
                    }
                    guard let img else { return }
                    CityImageMemoryCache.shared.set(img, forKey: key)
                    await JourneySnapshotDiskCache.shared.store(img, forKey: key)
                }
            }
        }
    }

    func load(journey: JourneyRoute, appearanceRaw: String) {
        let key = Self.snapshotKey(for: journey, appearanceRaw: appearanceRaw)
        if currentKey == key, image != nil { return }
        currentKey = key
        loadTask?.cancel()
        loadTask = nil

        if let cached = CityImageMemoryCache.shared.image(forKey: key) {
            image = cached
            return
        }

        loadTask = Task { [key] in
            if let diskImage = await JourneySnapshotDiskCache.shared.image(forKey: key) {
                await MainActor.run {
                    guard self.currentKey == key else { return }
                    self.image = diskImage
                    CityImageMemoryCache.shared.set(diskImage, forKey: key)
                }
                return
            }

            let img = await JourneySnapshotInFlightStore.shared.image(for: key) {
                await Task.detached(priority: .utility) {
                    return Self.makeSnapshot(journey: journey, appearanceRaw: appearanceRaw)
                }.value
            }
            await MainActor.run {
                guard self.currentKey == key else { return }
                self.image = img
                if let img { CityImageMemoryCache.shared.set(img, forKey: key) }
            }
            if let img {
                await JourneySnapshotDiskCache.shared.store(img, forKey: key)
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        currentKey = nil
    }

    nonisolated private static func snapshotKey(for journey: JourneyRoute, appearanceRaw: String) -> String {
        let count = journey.coordinates.count
        let thumbCount = journey.thumbnailCoordinates.count
        let distanceRounded = Int((journey.distance / 10.0).rounded())
        let endedAt = Int((journey.endTime ?? .distantPast).timeIntervalSince1970)
        return "journey.snapshot|\(journey.id)|\(appearanceRaw)|\(count)|\(thumbCount)|\(distanceRounded)|\(endedAt)"
    }

    nonisolated private static func mapType(for appearanceRaw: String) -> MKMapType {
        MapAppearanceSettings.mapType(for: appearanceRaw)
    }

    nonisolated private static func interfaceStyle(for appearanceRaw: String) -> UIUserInterfaceStyle {
        MapAppearanceSettings.interfaceStyle(for: appearanceRaw)
    }

    nonisolated private static func clampedRegion(_ region: MKCoordinateRegion) -> MKCoordinateRegion? {
        guard CLLocationCoordinate2DIsValid(region.center),
              region.center.latitude.isFinite,
              region.center.longitude.isFinite,
              region.span.latitudeDelta.isFinite,
              region.span.longitudeDelta.isFinite
        else { return nil }

        var center = region.center
        var span = region.span
        center.latitude = min(max(center.latitude, -90.0), 90.0)
        center.longitude = min(max(center.longitude, -180.0), 180.0)
        if span.latitudeDelta <= 0 || span.longitudeDelta <= 0 { return nil }
        span.latitudeDelta = min(max(span.latitudeDelta, 0.0001), 180.0)
        span.longitudeDelta = min(max(span.longitudeDelta, 0.0001), 360.0)
        return MKCoordinateRegion(center: center, span: span)
    }

    nonisolated private static func makeSnapshot(journey: JourneyRoute, appearanceRaw: String) -> UIImage? {
        let renderCoords = journey.allCLCoords.isEmpty ? journey.allCLThumbnailCoords : journey.allCLCoords
        guard let rawRegion = JourneySnapshotFraming.region(
            for: renderCoords,
            countryISO2: journey.countryISO2,
            cityKey: journey.cityKey,
            targetAspectRatio: 1.5
        ),
        let region = clampedRegion(rawRegion) else {
            return nil
        }

        let styledSegments = CityDeepRenderEngine.styledSegments(
            journeys: [journey],
            countryISO2: journey.countryISO2,
            cityKey: journey.cityKey
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 480, height: 320)
        options.scale = 2
        options.mapType = mapType(for: appearanceRaw)
        options.traitCollection = UITraitCollection(userInterfaceStyle: interfaceStyle(for: appearanceRaw))
        options.showsBuildings = false
        options.showsPointsOfInterest = false

        let sem = DispatchSemaphore(value: 0)
        var out: UIImage?
        MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snapshot, _ in
            defer { sem.signal() }
            guard let snapshot else { return }
            out = UIGraphicsImageRenderer(size: options.size).image { renderer in
                snapshot.image.draw(at: .zero)
                CityDeepRenderEngine.drawStyledSegments(styledSegments, snapshot: snapshot, context: renderer.cgContext, appearanceRaw: appearanceRaw)
            }
        }
        _ = sem.wait(timeout: .now() + 15)
        return out
    }
}

private actor JourneySnapshotInFlightStore {
    static let shared = JourneySnapshotInFlightStore()
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func image(
        for key: String,
        producer: @escaping @Sendable () async -> UIImage?
    ) async -> UIImage? {
        if let existing = tasks[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            await producer()
        }
        tasks[key] = task
        let result = await task.value
        tasks[key] = nil
        return result
    }
}

private actor JourneySnapshotDiskCache {
    static let shared = JourneySnapshotDiskCache()

    private let fm = FileManager.default
    private let maxDiskBytes: Int64 = 120 * 1024 * 1024
    private let maxDiskFiles: Int = 700
    private let directoryURL: URL

    init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = base.appendingPathComponent("JourneySnapshots", isDirectory: true)
        try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func image(forKey key: String) -> UIImage? {
        let url = fileURL(for: key)
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        touch(url: url)
        return image
    }

    func store(_ image: UIImage, forKey key: String) {
        let url = fileURL(for: key)
        guard let data = encode(image) else { return }
        do {
            try data.write(to: url, options: .atomic)
            touch(url: url)
            trimIfNeeded()
        } catch {
            // Ignore cache write failures.
        }
    }

    private func encode(_ image: UIImage) -> Data? {
        if let cg = image.cgImage,
           let mutable = CFDataCreateMutable(nil, 0),
           let dest = CGImageDestinationCreateWithData(mutable, UTType.heic.identifier as CFString, 1, nil) {
            let options: CFDictionary = [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
            CGImageDestinationAddImage(dest, cg, options)
            if CGImageDestinationFinalize(dest) {
                return mutable as Data
            }
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent("\(sha256(key)).cache", isDirectory: false)
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func touch(url: URL) {
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func trimIfNeeded() {
        guard let files = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, modified: Date, size: Int64)] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate,
                  let size = values.fileSize else {
                return nil
            }
            return (url, modified, Int64(size))
        }

        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        if entries.count <= maxDiskFiles, total <= maxDiskBytes { return }

        entries.sort { $0.modified < $1.modified }
        var runningCount = entries.count
        var runningBytes = total
        for entry in entries where runningCount > maxDiskFiles || runningBytes > maxDiskBytes {
            try? fm.removeItem(at: entry.url)
            runningCount -= 1
            runningBytes -= entry.size
        }
    }
}

struct JourneyRouteDetailView: View {
    let journeyID: String
    let isReadOnly: Bool
    let headerTitle: String?
    let userID: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator

    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var fittedRegion: MKCoordinateRegion? = nil
    @State private var editingMemory: JourneyMemory? = nil
    @State private var viewingMemory: JourneyMemory? = nil
    @State private var sidebarHideToken = UUID().uuidString
    @State private var localizedCityTitle: String? = nil

    init(
        journeyID: String,
        isReadOnly: Bool = false,
        headerTitle: String? = nil,
        userID: String? = nil
    ) {
        self.journeyID = journeyID
        self.isReadOnly = isReadOnly
        self.headerTitle = headerTitle
        self.userID = userID
    }

    private var journey: JourneyRoute? {
        store.journeys.first(where: { $0.id == journeyID })
    }

    private var cachedCitiesByKey: [String: CachedCity] {
        Dictionary(
            uniqueKeysWithValues: cityCache.cachedCities
                .filter { !($0.isTemporary ?? false) }
                .map { ($0.id, $0) }
        )
    }

    private var cityTitle: String {
        if let localizedCityTitle, !localizedCityTitle.isEmpty {
            return localizedCityTitle
        }
        guard let journey else { return L10n.t("unknown") }
        return JourneyCityNamePresentation.title(
            for: journey,
            localizedCityNameByKey: [:],
            cachedCitiesByKey: cachedCitiesByKey
        )
    }

    private var countryTitle: String {
        let iso = (journey?.countryISO2 ?? "").uppercased()
        if iso.count == 2 {
            return Locale.current.localizedString(forRegionCode: iso) ?? iso
        }
        return L10n.t("unknown_country")
    }

    private var dateText: String {
        guard let d = journey?.endTime ?? journey?.startTime else { return "--" }
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: d)
    }

    private var durationText: String {
        guard let j = journey, let s = j.startTime, let e = j.endTime else { return "--" }
        let sec = max(0, Int(e.timeIntervalSince(s)))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    private var segments: [JourneyDetailMap.AnySegment] {
        guard let j = journey else { return [] }
        return CityDeepRenderEngine.styledSegments(
            journeys: [j],
            countryISO2: j.countryISO2,
            cityKey: j.cityKey
        ).map {
            JourneyDetailMap.AnySegment(coords: $0.coords, isGap: $0.isGap, repeatWeight: $0.repeatWeight)
        }
    }

    private var memoryGroups: [JourneyDetailMap.MemoryGroup] {
        guard let j = journey else { return [] }
        return j.memories.filter { $0.locationStatus != .pending }.map { memory in
            let mapped = JourneyMemoryMapCoordinateResolver.mapCoordinate(
                for: memory,
                fallbackCountryISO2: j.countryISO2,
                fallbackCityKey: j.cityKey
            )
            return JourneyDetailMap.MemoryGroup(id: memory.id, coordinate: mapped, memory: memory)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            JourneyDetailMap(
                segments: segments,
                memoryGroups: memoryGroups,
                initialRegion: fittedRegion,
                onTapMemory: { memory in
                    switch JourneyRouteDetailInteractionPolicy.destinationForMemoryTap(isReadOnly: isReadOnly) {
                    case .editMemory:
                        editingMemory = memory
                    case .viewMemory:
                        viewingMemory = memory
                    }
                }
            )
            .ignoresSafeArea()
            .onAppear {
                refreshRegion()
            }
            .onChange(of: journey?.id) { _ in
                refreshRegion()
            }

            VStack(spacing: 0) {
                routeHeader

                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(cityTitle) · \(countryTitle)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text("\(dateText) · \(durationText) · \(String(format: "%.1f km", max(0, (journey?.distance ?? 0) / 1000.0)))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .overlay {
            if let tappedMemory = viewingMemory {
                MemoryDetailPage(
                    memory: tappedMemory,
                    isPresented: Binding(
                        get: { viewingMemory != nil },
                        set: { if !$0 { viewingMemory = nil } }
                    ),
                    allowsEditing: false,
                    maxCardWidth: 300,
                    maxCardHeight: 440,
                    onUpdated: { _ in },
                    userID: userID
                )
                .environmentObject(sessionStore)
            } else if !isReadOnly, let tappedMemory = editingMemory {
                MemoryEditorSheet(
                    isPresented: Binding(
                        get: { editingMemory != nil },
                        set: { if !$0 { editingMemory = nil } }
                    ),
                    userID: sessionStore.currentUserID,
                    existing: tappedMemory,
                    onSave: { updated in
                        let targetId = tappedMemory.id
                        guard let jIdx = store.journeys.firstIndex(where: { $0.id == journeyID }) else { return }
                        var j = store.journeys[jIdx]
                        guard let mIdx = j.memories.firstIndex(where: { $0.id == targetId }) else { return }

                        if let updated {
                            var normalized = updated
                            normalized.id = tappedMemory.id
                            normalized.timestamp = tappedMemory.timestamp
                            normalized.coordinate = tappedMemory.coordinate
                            normalized.type = .memory
                            normalized.cityKey = tappedMemory.cityKey
                            normalized.cityName = tappedMemory.cityName
                            j.memories[mIdx] = normalized
                        } else {
                            j.memories.removeAll(where: { $0.id == targetId })
                        }

                        store.upsertSnapshotThrottled(j, coordCount: j.coordinates.count)
                        store.flushPersist(journey: j)
                    }
                )
                .environmentObject(sessionStore)
            }
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .task(id: journey?.id) {
            await refreshLocalizedCityTitle()
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(JourneyRouteSwipeBackEnabler())
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(L10n.t("delete_journey_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("delete"), role: .destructive) {
                store.deleteJourney(id: journeyID)
                dismiss()
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                ShareSheet(activityItems: [shareImage])
            }
        }
    }

    private var routeHeader: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .frame(width: 88, alignment: .leading)

                Spacer(minLength: 0)

                if !isReadOnly {
                    HStack(spacing: 10) {
                        Button {
                            shareCurrent()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.black)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.black)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Color.clear.frame(width: 68, height: 34)
                }
            }

            Text(headerTitle ?? L10n.t("journey_route_title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FigmaTheme.border)
                .frame(height: 1)
        }
    }

    private func refreshRegion() {
        guard let j = journey else {
            fittedRegion = nil
            return
        }

        fittedRegion = CityDeepRenderEngine.fittedRegion(
            cityKey: j.cityKey,
            countryISO2: j.countryISO2,
            journeys: [j],
            anchorWGS: j.allCLCoords.first,
            effectiveBoundaryWGS: nil,
            fetchedBoundaryWGS: nil
        )
    }

    private func refreshLocalizedCityTitle() async {
        guard let journey else { return }
        let key = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "Unknown|" else { return }

        if let cachedCity = cachedCitiesByKey[key] {
            let title = CityPlacemarkResolver.displayTitle(
                cityKey: cachedCity.id,
                iso2: cachedCity.countryISO2,
                fallbackTitle: cachedCity.name,
                availableLevelNamesRaw: cachedCity.reservedAvailableLevelNames,
                storedAvailableLevelNamesLocaleID: cachedCity.reservedAvailableLevelNamesLocaleID,
                parentRegionKey: cachedCity.reservedParentRegionKey,
                preferredLevel: cachedCity.reservedLevelRaw.flatMap { CityPlacemarkResolver.CardLevel(rawValue: $0) },
                localizedDisplayNameByLocale: cachedCity.localizedDisplayNameByLocale,
                locale: .current
            )
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run { localizedCityTitle = title }
                return
            }
        }

        let parentRegionKey = JourneyCityNamePresentation.parentRegionKey(for: journey, cachedCitiesByKey: cachedCitiesByKey)

        if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: parentRegionKey),
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run { localizedCityTitle = cached }
            return
        }

        guard let start = journey.startCoordinate, start.isValid else { return }
        let loc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        if let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: parentRegionKey),
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run { localizedCityTitle = title }
        }
    }

    private func shareCurrent() {
        guard let j = journey else { return }
        ShareCardGenerator.generate(
            journey: j,
            cachedCitiesByKey: cachedCitiesByKey,
            privacy: .exact
        ) { img in
            self.shareImage = img
            self.showShareSheet = true
        }
    }
}

private struct JourneyDetailMap: UIViewRepresentable {
    struct AnySegment {
        let coords: [CLLocationCoordinate2D]
        let isGap: Bool
        let repeatWeight: Double
    }

    struct MemoryGroup: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let memory: JourneyMemory
    }

    let segments: [AnySegment]
    let memoryGroups: [MemoryGroup]
    let initialRegion: MKCoordinateRegion?
    let onTapMemory: (JourneyMemory) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = MapAppearanceSettings.interfaceStyle
        map.showsCompass = false
        map.showsScale = false
        map.showsTraffic = false
        map.pointOfInterestFilter = .excludingAll
        map.mapType = MapAppearanceSettings.mapType
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        if let r = initialRegion {
            map.setRegion(r, animated: false)
            context.coordinator.didSetInitialRegion = true
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.overrideUserInterfaceStyle = MapAppearanceSettings.interfaceStyle
        map.mapType = MapAppearanceSettings.mapType

        if let r = initialRegion, !context.coordinator.didSetInitialRegion {
            context.coordinator.didSetInitialRegion = true
            map.setRegion(r, animated: false)
        }

        map.removeOverlays(map.overlays)
        for seg in segments where seg.coords.count >= 2 {
            let poly = JourneyStyledPolyline(coordinates: seg.coords, count: seg.coords.count)
            poly.isGap = seg.isGap
            poly.repeatWeight = max(0, min(1, seg.repeatWeight))
            map.addOverlay(poly)
        }

        map.removeAnnotations(map.annotations)
        for g in memoryGroups {
            map.addAnnotation(JourneyMemoryAnnotation(group: g))
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: JourneyDetailMap
        var didSetInitialRegion = false

        init(_ parent: JourneyDetailMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? JourneyStyledPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let base = MapAppearanceSettings.routeBaseColor
            let gapDash = RouteRenderStyleTokens.dashLengths.map { NSNumber(value: Double($0)) }
            let weight = CGFloat(max(0, min(1, poly.repeatWeight)))
            let isGap = poly.isGap

            let glow = MKPolylineRenderer(polyline: poly)
            glow.lineWidth = isGap ? 2.0 : (3.0 + weight * 1.2)
            glow.lineCap = .round
            glow.lineJoin = .round
            glow.strokeColor = base.withAlphaComponent(isGap ? 0.08 : 0.12)
            if isGap { glow.lineDashPattern = gapDash }

            let core = MKPolylineRenderer(polyline: poly)
            core.lineWidth = isGap ? 1.1 : (1.6 + weight * 0.8)
            core.lineCap = .round
            core.lineJoin = .round
            core.strokeColor = base.withAlphaComponent(isGap ? 0.30 : 0.84)
            if isGap { core.lineDashPattern = gapDash }

            let freq = MKPolylineRenderer(polyline: poly)
            freq.lineWidth = isGap ? 0 : (2.2 + weight * 1.2)
            freq.lineCap = .round
            freq.lineJoin = .round
            freq.strokeColor = base.withAlphaComponent(isGap ? 0 : (0.05 + 0.15 * weight))

            return JourneyLayeredPolylineRenderer(renderers: [glow, freq, core])
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? JourneyMemoryAnnotation else { return nil }
            let id = "journeyMem"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: ann, reuseIdentifier: id)

            view.annotation = ann
            view.canShowCallout = false
            view.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
            view.backgroundColor = .clear
            view.displayPriority = .required
            if #available(iOS 14.0, *) {
                view.zPriority = .max
            }

            let hosting = UIHostingController(rootView: MemoryPin(cluster: [ann.group.memory]))
            hosting.view.backgroundColor = .clear
            hosting.view.frame = view.bounds
            hosting.view.isUserInteractionEnabled = false
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(hosting.view)

            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation as? JourneyMemoryAnnotation else { return }
            parent.onTapMemory(ann.group.memory)
            mapView.deselectAnnotation(ann, animated: false)
        }
    }
}

private final class JourneyMemoryAnnotation: NSObject, MKAnnotation {
    let group: JourneyDetailMap.MemoryGroup
    var coordinate: CLLocationCoordinate2D { group.coordinate }

    init(group: JourneyDetailMap.MemoryGroup) {
        self.group = group
    }
}

private final class JourneyStyledPolyline: MKPolyline {
    var isGap: Bool = false
    var repeatWeight: Double = 0
}

private final class JourneyLayeredPolylineRenderer: MKOverlayRenderer {
    private let renderers: [MKPolylineRenderer]

    init(renderers: [MKPolylineRenderer]) {
        precondition(!renderers.isEmpty)
        self.renderers = renderers
        super.init(overlay: renderers[0].overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        for renderer in renderers {
            renderer.draw(mapRect, zoomScale: zoomScale, in: context)
        }
    }
}
