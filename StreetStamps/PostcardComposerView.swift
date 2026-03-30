import SwiftUI
import PhotosUI
import CoreLocation

struct PostcardRecipient: Equatable {
    let userID: String
    let displayName: String
}

enum PostcardComposerPresentation {
    static func initialRecipient(
        prefilledFriendID: String?,
        prefilledFriendName: String?
    ) -> PostcardRecipient? {
        let friendID = prefilledFriendID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let friendName = prefilledFriendName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !friendID.isEmpty, !friendName.isEmpty else { return nil }
        return PostcardRecipient(userID: friendID, displayName: friendName)
    }

    static func canPreview(
        recipient: PostcardRecipient?,
        selectedCityID: String,
        localImagePath: String,
        messageText: String
    ) -> Bool {
        recipient != nil &&
        !selectedCityID.isEmpty &&
        !localImagePath.isEmpty &&
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct PostcardComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var socialStore: SocialGraphStore

    let onSent: (() -> Void)?

    @State private var selectedCityID: String = ""
    @State private var selectedCityName: String = ""
    @State private var messageText: String = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var localImagePath: String = ""
    @State private var showPreview = false
    @State private var loadingPhoto = false
    @State private var photoErrorText: String?
    @ObservedObject private var languagePreference = LanguagePreference.shared
    @State private var localizedCityNamesByID: [String: String] = [:]
    @State private var sidebarHideToken = "\(PostcardSidebarVisibilityScope.composer.token)-\(UUID().uuidString)"
    @State private var selectedRecipient: PostcardRecipient?
    @State private var showRecipientPicker = false
    @State private var messageLimitHit = false

    init(
        friendID: String? = nil,
        friendName: String? = nil,
        onSent: (() -> Void)? = nil
    ) {
        self.onSent = onSent
        _selectedRecipient = State(
            initialValue: PostcardComposerPresentation.initialRecipient(
                prefilledFriendID: friendID,
                prefilledFriendName: friendName
            )
        )
    }

    private var cityOptions: [(id: String, name: String)] {
        PostcardCityOptionsPresentation.buildOptions(
            cachedCities: cityCache.cachedCities,
            journeyCandidates: currentCityCandidates
        )
    }

    private var selectedCityJourneyCount: Int {
        guard let city = cityCache.cachedCities.first(where: {
            $0.id == selectedCityID && !($0.isTemporary ?? false)
        }) else {
            return 1
        }
        let journeysByID = Dictionary(uniqueKeysWithValues: journeyStore.journeys.map { ($0.id, $0) })
        let validCount = city.journeyIds.count(where: { journeyID in
            guard let j = journeysByID[journeyID] else { return false }
            return j.distance >= 1000
        })
        return max(1, validCount)
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
        city.displayTitle
    }

    private func normalizedPrefetchedCityName(for city: CachedCity, candidateTitle: String?) -> String {
        // When we have a fresh geocode candidate, use it to produce a display title.
        // This result will be written back to CachedCity and refreshResolvedDisplayName will fire.
        CityPlacemarkResolver.displayTitle(
            for: city,
            locale: LanguagePreference.shared.displayLocale,
            localizedCandidate: candidateTitle
        )
    }

    private func localizedCityName(for journey: JourneyRoute) -> String {
        let key = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedCity = cityCache.cachedCities.first(where: { $0.id == key && !($0.isTemporary ?? false) }) {
            return cachedCity.displayTitle
        }
        return key.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? journey.displayCityName
    }

    private func resolvedLocalizedCityName(for city: CachedCity) -> String {
        localizedCityNamesByID[city.id] ?? city.displayTitle
    }

    private func resolvedLocalizedCityName(for journey: JourneyRoute) -> String {
        let key = journey.cityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return localizedCityNamesByID[key] ?? localizedCityName(for: journey)
    }

    private func refreshLocalizedCityNames() async {
        await MainActor.run { localizedCityNamesByID = [:] }
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

            if let cached = await ReverseGeocodeService.shared.cachedDisplayTitle(cityKey: key, parentRegionKey: city.parentScopeKey),
               !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let resolved = normalizedPrefetchedCityName(for: city, candidateTitle: cached)
                await MainActor.run { localizedCityNamesByID[key] = resolved }
                continue
            }

            let loc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            if let title = await ReverseGeocodeService.shared.displayTitle(for: loc, cityKey: key, parentRegionKey: city.parentScopeKey),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let resolved = normalizedPrefetchedCityName(for: city, candidateTitle: title)
                await MainActor.run { localizedCityNamesByID[key] = resolved }
            }
        }
    }

    private var canPreview: Bool {
        PostcardComposerPresentation.canPreview(
            recipient: selectedRecipient,
            selectedCityID: selectedCityID,
            localImagePath: localImagePath,
            messageText: messageText
        )
    }

    private var cityRefreshTaskID: String {
        let lang = languagePreference.currentLanguage ?? "sys"
        let citiesPart = cityCache.cachedCities.map { city in
            let localizedCount = city.localizedDisplayNameByLocale?.count ?? 0
            let levelCount = city.availableLevelNames?.count ?? 0
            return "\(city.id)|\(city.name)|\(city.selectedDisplayLevelRaw ?? "")|\(city.parentScopeKey ?? "")|\(city.availableLevelNamesLocaleID ?? "")|\(localizedCount)|\(levelCount)"
        }.joined(separator: ";")
        return "\(lang)|\(citiesPart)"
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
            socialStore.ensureLoaded()
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

                    let previewImage = try await Task.detached(priority: .userInitiated) {
                        guard let uiImage = UIImage(data: data) else {
                            throw NSError(domain: "PostcardError", code: -1)
                        }
                        return uiImage.downscaled(maxPixel: MediaUploadPreparation.postcardMaxPixel)
                    }.value

                    persistEditedPostcardImage(previewImage)
                } catch {
                    photoErrorText = L10n.t("postcard_send_failed")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { photoErrorText = nil }
                }
            }
        }
    }

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("postcard_send_to"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                    if let selectedRecipient {
                        Text(selectedRecipient.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(FigmaTheme.text)
                    } else {
                        Text(L10n.t("postcard_add_recipient"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                }

                Spacer(minLength: 12)

                if selectedRecipient != nil {
                    Button(L10n.t("postcard_change_recipient")) {
                        showRecipientPicker = true
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FigmaTheme.primary)
                    .buttonStyle(.plain)
                } else {
                    Button(L10n.t("postcard_add_button")) {
                        showRecipientPicker = true
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(FigmaTheme.primary)
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .postcardFeatureCardStyle()
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onTapGesture {
            showRecipientPicker = true
        }
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

            if let photoErrorText {
                Text(photoErrorText)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
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
                        messageLimitHit = true
                        Haptics.light()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            messageLimitHit = false
                        }
                    }
                }

            HStack {
                Spacer()
                Text("\(messageText.count)/80")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(messageLimitHit ? .red : FigmaTheme.subtext)
                    .animation(.easeInOut(duration: 0.3), value: messageLimitHit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .postcardFeatureCardStyle()
    }

    private var previewLink: some View {
        NavigationLink(isActive: $showPreview) {
            if let selectedRecipient {
                PostcardPreviewView(
                    friendID: selectedRecipient.userID,
                    friendName: selectedRecipient.displayName,
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
            }
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
        .sheet(isPresented: $showRecipientPicker) {
            RecipientPickerSheet(
                friends: socialStore.friends,
                selectedRecipient: selectedRecipient
            ) { recipient in
                selectedRecipient = recipient
            }
        }
    }
}

private extension PostcardComposerView {
    func persistEditedPostcardImage(_ image: UIImage) {
        guard let compressedData = image.jpegData(compressionQuality: MediaUploadPreparation.postcardCompressionQuality) else {
            photoErrorText = L10n.t("postcard_send_failed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { photoErrorText = nil }
            return
        }

        do {
            let filename = "postcard_\(UUID().uuidString).jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try compressedData.write(to: url, options: .atomic)
            selectedImage = image
            localImagePath = url.path
        } catch {
            photoErrorText = L10n.t("postcard_send_failed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { photoErrorText = nil }
        }
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

private struct RecipientPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let friends: [FriendProfileSnapshot]
    let selectedRecipient: PostcardRecipient?
    let onSelect: (PostcardRecipient) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(friends) { friend in
                        let isSelected = selectedRecipient?.userID == friend.id
                        Button {
                            onSelect(
                                PostcardRecipient(
                                    userID: friend.id,
                                    displayName: friend.displayName
                                )
                            )
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                RobotRendererView(size: 36, face: .front, loadout: friend.loadout)
                                    .frame(width: 52, height: 52)
                                    .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                                Text(friend.displayName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(FigmaTheme.text)

                                Spacer(minLength: 8)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(FigmaTheme.primary)
                                        .transition(.scale.combined(with: .opacity))
                                        .symbolEffect(.bounce, value: selectedRecipient?.userID)
                                }
                            }
                            .padding(14)
                            .figmaSurfaceCard(radius: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(isSelected ? FigmaTheme.primary : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(FigmaTheme.background)
            .navigationTitle(L10n.t("postcard_select_recipient_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
