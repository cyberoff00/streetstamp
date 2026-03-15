import SwiftUI
import PhotosUI
import CoreLocation

struct PostcardComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var journeyStore: JourneyStore

    let friendID: String
    let friendName: String
    let onSent: (() -> Void)? = nil

    @State private var selectedCityID: String = ""
    @State private var selectedCityName: String = ""
    @State private var messageText: String = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var localImagePath: String = ""
    @State private var showPreview = false
    @State private var loadingPhoto = false
    @State private var localizedCityNamesByID: [String: String] = [:]
    @State private var sidebarHideToken = "\(PostcardSidebarVisibilityScope.composer.token)-\(UUID().uuidString)"

    private var cityOptions: [(id: String, name: String)] {
        PostcardCityOptionsPresentation.buildOptions(
            cachedCities: cityCache.cachedCities,
            journeyCandidates: currentCityCandidates,
            localizedCityNamesByID: localizedCityNamesByID
        )
    }

    private var selectedCityJourneyCount: Int {
        guard let city = cityCache.cachedCities.first(where: {
            $0.id == selectedCityID && !($0.isTemporary ?? false)
        }) else {
            return 1
        }
        let validJourneys = city.journeyIds.compactMap { journeyID in
            journeyStore.journeys.first(where: { $0.id == journeyID })
        }.filter { $0.distance >= 1000 }
        return max(1, validJourneys.count)
    }

    private var currentCityCandidates: [JourneyRoute] {
        var candidates: [JourneyRoute] = []
        if let ongoing = journeyStore.latestOngoing {
            candidates.append(ongoing)
        }
        if let first = journeyStore.journeys.first {
            if !candidates.contains(where: { $0.id == first.id }) {
                candidates.append(first)
            }
        }
        return candidates
    }

    private func localizedCityName(for city: CachedCity) -> String {
        CityPlacemarkResolver.displayTitle(for: city, locale: .current)
    }

    private func normalizedPrefetchedCityName(for city: CachedCity, candidateTitle: String?) -> String {
        CityPlacemarkResolver.displayTitle(
            for: city,
            locale: .current,
            localizedCandidate: candidateTitle
        )
    }

    private func localizedCityName(for journey: JourneyRoute) -> String {
        let key = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedCity = cityCache.cachedCities.first(where: { $0.id == key && !($0.isTemporary ?? false) }) {
            return localizedCityName(for: cachedCity)
        }

        return CityPlacemarkResolver.displayTitle(
            cityKey: key,
            iso2: journey.countryISO2,
            fallbackTitle: journey.displayCityName,
            locale: .current
        )
    }

    private func resolvedLocalizedCityName(for city: CachedCity) -> String {
        localizedCityNamesByID[city.id] ?? localizedCityName(for: city)
    }

    private func resolvedLocalizedCityName(for journey: JourneyRoute) -> String {
        let key = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return localizedCityNamesByID[key] ?? localizedCityName(for: journey)
    }

    private func refreshLocalizedCityNames() async {
        for city in cityCache.cachedCities where !(city.isTemporary ?? false) {
            let key = city.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }

            let fallback = localizedCityName(for: city).trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                await MainActor.run { localizedCityNamesByID[key] = fallback }
            }

            let anchor = city.anchor?.cl ?? city.journeyIds.compactMap { id in
                journeyStore.journeys.first(where: { $0.id == id })?.startCoordinate
            }.first
            guard let anchor, anchor.isValid else { continue }

            if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: city.reservedParentRegionKey),
               !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let resolved = normalizedPrefetchedCityName(for: city, candidateTitle: cached)
                await MainActor.run { localizedCityNamesByID[key] = resolved }
                continue
            }

            let loc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            if let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.reservedParentRegionKey),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let resolved = normalizedPrefetchedCityName(for: city, candidateTitle: title)
                await MainActor.run { localizedCityNamesByID[key] = resolved }
            }
        }
    }

    private var canPreview: Bool {
        !selectedCityID.isEmpty && !localImagePath.isEmpty && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cityRefreshTaskID: String {
        cityCache.cachedCities.map { city in
            let localizedCount = city.localizedDisplayNameByLocale?.count ?? 0
            let levelCount = city.reservedAvailableLevelNames?.count ?? 0
            return "\(city.id)|\(city.name)|\(city.reservedLevelRaw ?? "")|\(city.reservedParentRegionKey ?? "")|\(city.reservedAvailableLevelNamesLocaleID ?? "")|\(localizedCount)|\(levelCount)"
        }.joined(separator: ";")
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                recipientCard
                cityPickerCard
                photoPickerCard
                messageCard
                previewLink
                previewButton
            }
            .padding(20)
        }
    }

    var body: some View {
        content
        .background(FigmaTheme.background.ignoresSafeArea())
        .onAppear {
            guard PostcardSidebarVisibilityScope.composer.hidesGlobalSidebarButton else { return }
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .onDisappear {
            guard PostcardSidebarVisibilityScope.composer.hidesGlobalSidebarButton else { return }
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            UnifiedNavigationHeader(
                chrome: NavigationChrome(
                    title: L10n.t("postcard_new_title"),
                    leadingAccessory: .back,
                    titleLevel: .secondary
                ),
                horizontalPadding: 18,
                topPadding: 8,
                bottomPadding: 12,
                onLeadingTap: { dismiss() }
            ) {
                Color.clear
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if selectedCityID.isEmpty, let first = cityOptions.first {
                selectedCityID = first.id
                selectedCityName = first.name
            }
        }
        .task(id: cityRefreshTaskID) {
            await refreshLocalizedCityNames()
            guard let first = cityOptions.first else {
                selectedCityID = ""
                selectedCityName = ""
                return
            }
            if selectedCityID.isEmpty || !cityOptions.contains(where: { $0.id == selectedCityID }) {
                selectedCityID = first.id
                selectedCityName = first.name
                return
            }
            if let selected = cityOptions.first(where: { $0.id == selectedCityID }) {
                selectedCityName = selected.name
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task {
                loadingPhoto = true
                defer { loadingPhoto = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }

                    let (previewImage, compressedData) = try await Task.detached(priority: .userInitiated) {
                        guard let uiImage = UIImage(data: data) else {
                            throw NSError(domain: "PostcardError", code: -1)
                        }
                        let prepared = uiImage.downscaled(maxPixel: MediaUploadPreparation.postcardMaxPixel)
                        guard let jpeg = prepared.jpegData(compressionQuality: MediaUploadPreparation.postcardCompressionQuality) else {
                            throw NSError(domain: "PostcardError", code: -2)
                        }
                        return (prepared, jpeg)
                    }.value

                    let filename = "postcard_\(UUID().uuidString).jpg"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    try compressedData.write(to: url, options: .atomic)
                    selectedImage = previewImage
                    localImagePath = url.path
                } catch {
                    // ignore picker failure, user can retry
                }
            }
        }
    }

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("postcard_send_to"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)
            Text(friendName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(FigmaTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .postcardFeatureCardStyle()
    }

    private var cityPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("postcard_city"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)

            Picker(L10n.t("postcard_city"), selection: $selectedCityID) {
                ForEach(cityOptions, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedCityID) { _, newID in
                selectedCityName = cityOptions.first(where: { $0.id == newID })?.name ?? ""
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .postcardFeatureCardStyle()
    }

    private var photoPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("postcard_photo_limit"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                Text(selectedImage == nil ? L10n.t("postcard_upload_local_photo") : L10n.t("postcard_replace_photo"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FigmaTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(loadingPhoto)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .postcardFeatureCardStyle()
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("postcard_message"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.subtext)

            TextEditor(text: $messageText)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: messageText) { _, newValue in
                    if newValue.count > 80 {
                        messageText = String(newValue.prefix(80))
                    }
                }

            HStack {
                Spacer()
                Text("\(messageText.count)/80")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .postcardFeatureCardStyle()
    }

    private var previewLink: some View {
        NavigationLink(isActive: $showPreview) {
            PostcardPreviewView(
                friendID: friendID,
                friendName: friendName,
                selectedCityID: selectedCityID,
                selectedCityName: selectedCityName,
                selectedCityJourneyCount: selectedCityJourneyCount,
                messageText: messageText,
                localImagePath: localImagePath,
                selectedImage: selectedImage,
                allowedCityIDs: cityOptions.map(\.id),
                onSent: {
                    onSent?()
                    dismiss()
                }
            )
        } label: {
            EmptyView()
        }
    }

    private var previewButton: some View {
        Button {
            showPreview = true
        } label: {
            Text(L10n.t("postcard_preview"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canPreview ? FigmaTheme.primary : FigmaTheme.primary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canPreview)
    }
}

private extension View {
    func postcardFeatureCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
    }
}
