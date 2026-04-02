//
//  SharingCard.swift
//  StreetStamps
//
//  Created by Claire Yang on 13/01/2026.
//

import SwiftUI
import MapKit
import CoreLocation
import UIKit
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Privacy Mode
enum ShareMapPrivacyMode: Hashable {
    case exact
    case hidden
}

// MARK: - PopSharingCard
struct PopSharingCard: View {
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @Binding var isPresented: Bool
    var journey: JourneyRoute
    var fallbackCenter: CLLocationCoordinate2D?

    var onContinueJourney: () -> Void
    var onCompleteAndExit: (JourneyRoute) -> Void

    // ✅ NEW: 给 “去看看” 用的导航回调（外层决定怎么跳 City Library）
    var onGoToLibrary: (() -> Void)? = nil

    @State private var showShareSheet = false

    @State private var showSavedToast = false
    @State private var showDiscardConfirm = false
    @State private var showShareActions = false

    // unlock modal
    @State private var showUnlock = false
    @State private var unlockedCity: UnlockedPayload? = nil
    @State private var pendingExitAfterUnlock = false

    // privacy + image generation
    @State private var privacyMode: ShareMapPrivacyMode = .exact
    @State private var isGenerating = false
    @State private var finalCardImage: UIImage?

    // ✅ Title resolved for sharing (display, localized)
    @State private var resolvedTitle: String? = nil
    @State private var selectedVisibility: JourneyVisibility = .private
    @State private var customTitle: String = ""
    @State private var activityTag: String = ""
    @State private var overallMemory: String = ""
    @State private var overallMemoryImagePaths: [String] = []
    @State private var hideMapDetails = false
    @State private var privacyEnabled = false
    @State private var privacyTrimEndpoints = true
    @State private var privacyHideLandmarks = true
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var showPhotoEditor = false
    @State private var pendingEditorImages: [UIImage] = []
    @State private var showVisibilityRestrictionAlert = false
    @State private var visibilityRestrictionMessage = ""
    private var canRenderCard: Bool { journey.coordinates.count >= 1 && !journey.isTooShort }
    private let activityPresets: [String] = ["通勤", "跑步", "旅游", "散步", "骑行", "驾车", "地铁", "登山"]
    private var maxOverallMemoryPhotos: Int { MembershipStore.shared.maxPhotosPerMemory }

    private var cachedCitiesByKey: [String: CachedCity] {
        cityCache.cachedCitiesByKey
    }

    private var canAddOverallMemoryPhoto: Bool {
        overallMemoryImagePaths.count < maxOverallMemoryPhotos
    }

    private var remainingOverallMemoryPhotoSlots: Int {
        max(0, maxOverallMemoryPhotos - overallMemoryImagePaths.count)
    }

    var durationText: String {
        guard let start = journey.startTime else {
            return String(format: L10n.t("share_duration_min"), 0)
        }
        let end = journey.endTime ?? Date()
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return String(format: L10n.t("share_duration_min"), minutes)
    }

    var body: some View {
        ZStack {
            FigmaTheme.mutedBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        preview
                        actions
                    }
                    .padding(.bottom, 24)
                }
            }

            .sheet(isPresented: $showShareSheet) {
                if let img = finalCardImage {
                    ShareSheet(activityItems: [img])
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                SystemCameraPicker(
                    preferredDevice: .rear,
                    mirrorOnCapture: false,
                    onImage: { image in
                        pendingEditorImages = [image]
                    },
                    onCancel: {
                        showCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showPhotoLibrary) {
                PhotoLibraryPicker(
                    selectionLimit: max(1, remainingOverallMemoryPhotoSlots),
                    onImages: { images in
                        pendingEditorImages = images
                    },
                    onCancel: {
                        showPhotoLibrary = false
                    }
                )
                .ignoresSafeArea()
            }

            .sheet(isPresented: $showUnlock, onDismiss: {
                guard pendingExitAfterUnlock else { return }
                pendingExitAfterUnlock = false
                isPresented = false
                onCompleteAndExit(finalizedJourney())
            }) {
                if let payload = unlockedCity {
                    UnlockModal(
                        payload: payload,
                        journey: finalizedJourney(),
                        isPresented: $showUnlock,
                        onGoToLibrary: {
                            showUnlock = false
                            onGoToLibrary?()
                        }
                    )
                }
            }

            .onAppear {
                selectedVisibility = journey.visibility
                customTitle = (journey.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? (journey.customTitle ?? "")
                    : ""
                activityTag = journey.activityTag ?? ""
                overallMemory = journey.overallMemory ?? ""
                overallMemoryImagePaths = journey.overallMemoryImagePaths
                hideMapDetails = (privacyMode == .hidden)
                if finalCardImage == nil && canRenderCard {
                    finalCardImage = placeholderCard()
                    resolveTitleIfNeeded {
                        generateShareCard()
                    }
                }
            }
            .onChange(of: pendingEditorImages.count) { count in
                if count > 0 && !showCamera && !showPhotoEditor {
                    showPhotoEditor = true
                }
            }
            .fullScreenCover(isPresented: $showPhotoEditor) {
                PhotoEditorView(
                    images: pendingEditorImages,
                    onComplete: { edited in
                        showPhotoEditor = false
                        pendingEditorImages = []
                        appendOverallMemoryPhotos(edited, writesToPhotoLibrary: false)
                    },
                    onCancel: {
                        showPhotoEditor = false
                        pendingEditorImages = []
                    }
                )
            }

            .overlay(alignment: .top) {
                if showSavedToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolEffect(.bounce, value: showSavedToast)
                        Text(L10n.t("share_saved_to_photos"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert(L10n.t("discard_journey_title"), isPresented: $showDiscardConfirm) {
                Button(L10n.t("cancel"), role: .cancel) {}
                Button(L10n.t("discard"), role: .destructive) {
                    isPresented = false
                    store.deleteJourney(id: journey.id)
                }
            } message: {
                Text(L10n.t("share_discard_message"))
            }
            .alert(L10n.t("journey_change_visibility"), isPresented: $showVisibilityRestrictionAlert) {
                Button(L10n.t("done"), role: .cancel) {}
            } message: {
                Text(visibilityRestrictionMessage)
            }
        }
    }

    // MARK: - UI parts

    private var header: some View {
        ZStack {
            Text(L10n.t("share_save_journey_title"))
                .appTitleStyle()
                .foregroundColor(.black)

            HStack {
                Color.clear
                    .frame(width: 36, height: 36)

                Spacer()

                Button(role: .destructive) {
                    showDiscardConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .appMinTapTarget()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.12)).frame(height: 0.8)
        }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.t("share_journey_card"))
                    .font(.system(size: AppTypography.bodySize, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        showShareActions.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(L10n.t("share_or_save"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.black.opacity(0.45))
                        if showShareActions {
                            HStack(spacing: 6) {
                                Button {
                                    guard finalCardImage != nil else { return }
                                    showShareSheet = true
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.78))
                                        .appMinTapTarget()
                                }
                                .buttonStyle(.plain)

                                Button {
                                    guard let img = finalCardImage else { return }
                                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                                    showSavedToastNow()
                                } label: {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.78))
                                        .appMinTapTarget()
                                }
                                .buttonStyle(.plain)
                                .disabled(finalCardImage == nil)
                                .opacity(finalCardImage == nil ? 0.45 : 1)
                            }
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            if canRenderCard, let img = finalCardImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))

                    Button {
                        hideMapDetails.toggle()
                        privacyMode = hideMapDetails ? .hidden : .exact
                        guard canRenderCard else { return }
                        generateShareCard()
                    } label: {
                        Image(systemName: hideMapDetails ? "eye.slash" : "eye")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.28))
                            .clipShape(Circle())
                            .appMinTapTarget()
                    }
                    .padding(10)
                }
            } else if canRenderCard && isGenerating {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)))
                    .frame(height: 300)
                    .overlay(
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(L10n.t("share_generating"))
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    )
            } else {
                emptyJourneyPlaceholder
            }

        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }
    private var emptyJourneyPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(UIColor(white: 0.95, alpha: 1)))
            .frame(height: 160)
            .overlay(
                VStack(spacing: 12) {
                    Text(L10n.t("share_image_unavailable"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            )
    }

    private var actions: some View {
        VStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("share_journey_name_optional"))
                    .font(.system(size: AppTypography.bodySize, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                TextField(L10n.t("share_journey_name_placeholder"), text: $customTitle)
                    .font(.system(size: 14, weight: .regular))
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(Capsule(style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("share_activity_optional"))
                    .font(.system(size: AppTypography.bodySize, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                HStack(spacing: 8) {
                    TextField(L10n.t("share_activity_placeholder"), text: $activityTag)
                        .font(.system(size: 14, weight: .regular))
                        .textInputAutocapitalization(.never)

                    Menu {
                        ForEach(activityPresets, id: \.self) { item in
                            Button(item) {
                                activityTag = item
                            }
                        }
                        Divider()
                        Button(L10n.t("clear")) {
                            activityTag = ""
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.5))
                    }
                }
                .padding(.horizontal, 22)
                .frame(height: 52)
                .background(Color.white)
                .clipShape(Capsule(style: .continuous))
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("share_overall_memory_optional"))
                    .font(.system(size: AppTypography.bodySize, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $overallMemory)
                        .font(.system(size: 14))
                        .padding(10)
                        .frame(height: 118)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    HStack(spacing: 12) {
                        Button(action: { showCamera = true }) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.05))
                                .clipShape(Circle())
                                .appMinTapTarget()
                        }
                        .disabled(!canAddOverallMemoryPhoto)
                        .opacity(canAddOverallMemoryPhoto ? 1 : 0.35)

                        Button(action: { showPhotoLibrary = true }) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.04))
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.05))
                                .clipShape(Circle())
                                .appMinTapTarget()
                        }
                        .disabled(!canAddOverallMemoryPhoto)
                        .opacity(canAddOverallMemoryPhoto ? 1 : 0.35)

                        Text(String(format: L10n.t("photo_count"), overallMemoryImagePaths.count, maxOverallMemoryPhotos))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)

                        Spacer()
                    }

                    if !overallMemoryImagePaths.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(overallMemoryImagePaths.enumerated()), id: \.offset) { idx, path in
                                    ZStack(alignment: .topTrailing) {
                                        PhotoThumb(path: path, userID: sessionStore.currentUserID)

                                        Button {
                                            let removed = overallMemoryImagePaths.remove(at: idx)
                                            PhotoStore.delete(named: removed, userID: sessionStore.currentUserID)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(FigmaTheme.text.opacity(0.6))
                                                .background(Color.white.opacity(0.75).clipShape(Circle()))
                                                .appMinTapTarget()
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
            }

            if FeatureFlagStore.shared.socialEnabled {
                if onboardingGuide.shouldShowHint(.visibilityToggle) {
                    ContextualHintBar(
                        icon: "lock.shield",
                        message: L10n.t("hint_visibility_toggle"),
                        onDismiss: { onboardingGuide.dismissHint(.visibilityToggle) }
                    )
                }

                HStack(spacing: 10) {
                    Picker(L10n.t("visibility"), selection: visibilitySelection) {
                        ForEach(JourneyVisibility.frontendCases) { v in
                            Text(v.localizedTitle).tag(v)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // MARK: Privacy Options — only when sharing with friends
            if selectedVisibility != .private {
                privacyToggleSection
            }

            Button(action: completeJourneyAndMaybeUnlock) {
                Text(L10n.t("save"))
                    .font(.system(size: AppTypography.bodyStrongSize, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 280, height: 60)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 26)
    }

    // MARK: - Behaviors

    private func completeJourneyAndMaybeUnlock() {
        let decision = visibilityDecision(for: selectedVisibility)
        guard decision.isAllowed else {
            showVisibilityRestriction(reason: decision.reason)
            return
        }
        onboardingGuide.advance(.saveJourney)
        if let payload = cityCache.consumePendingUnlock() {
            unlockedCity = payload
            pendingExitAfterUnlock = true
            showUnlock = true
            return
        }

        isPresented = false
        onCompleteAndExit(finalizedJourney())
    }

    private func finalizedJourney() -> JourneyRoute {
        var out = journey
        out.visibility = selectedVisibility
        let trimmedTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = activityTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOverall = overallMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        out.customTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        out.activityTag = trimmedTag.isEmpty ? nil : trimmedTag
        out.overallMemory = trimmedOverall.isEmpty ? nil : trimmedOverall
        out.overallMemoryImagePaths = overallMemoryImagePaths
        out.privacyOptions = buildPrivacyOptions()
        return out
    }

    private func buildPrivacyOptions() -> Set<JourneyPrivacyOption> {
        guard privacyEnabled else { return [] }
        var opts = Set<JourneyPrivacyOption>()
        if privacyTrimEndpoints { opts.insert(.trimEndpoints) }
        if privacyHideLandmarks { opts.insert(.hideLandmarks) }
        return opts
    }

    // MARK: - Privacy Toggle Section
    private var privacyToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { privacyEnabled },
                set: { newValue in
                    privacyEnabled = newValue
                    if newValue {
                        privacyTrimEndpoints = true
                        privacyHideLandmarks = true
                    }
                }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.6))
                    Text(L10n.t("privacy_toggle_title"))
                        .font(.system(size: AppTypography.bodySize, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            .tint(.black)

            if privacyEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    privacyCheckRow(
                        title: L10n.t("privacy_trim_endpoints"),
                        isOn: $privacyTrimEndpoints
                    )
                    privacyCheckRow(
                        title: L10n.t("privacy_hide_landmarks"),
                        isOn: $privacyHideLandmarks
                    )
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: privacyEnabled)
    }

    private func privacyCheckRow(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            let willBe = !isOn.wrappedValue
            isOn.wrappedValue = willBe
            // If both unchecked, turn off the master toggle
            if !privacyTrimEndpoints && !privacyHideLandmarks {
                privacyEnabled = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(isOn.wrappedValue ? .black : .black.opacity(0.35))
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.75))
            }
        }
        .buttonStyle(.plain)
    }

    private var visibilitySelection: Binding<JourneyVisibility> {
        Binding(
            get: { selectedVisibility },
            set: { target in
                let decision = visibilityDecision(for: target)
                guard decision.isAllowed else {
                    showVisibilityRestriction(reason: decision.reason)
                    return
                }
                selectedVisibility = target
                onboardingGuide.dismissHint(.visibilityToggle)
            }
        )
    }

    private func visibilityDecision(for target: JourneyVisibility) -> JourneyVisibilityPolicy.Decision {
        JourneyVisibilityPolicy.evaluateChange(
            current: selectedVisibility,
            target: target,
            isLoggedIn: sessionStore.isLoggedIn,
            journeyDistance: journey.distance,
            memoryCount: journey.memories.count
        )
    }

    private func showVisibilityRestriction(reason: JourneyVisibilityPolicy.DenialReason?) {
        guard let reason else { return }
        visibilityRestrictionMessage = L10n.t(reason.localizationKey)
        showVisibilityRestrictionAlert = true
    }

    private func appendOverallMemoryPhotos(_ images: [UIImage], writesToPhotoLibrary: Bool) {
        let trimmed = Array(images.prefix(remainingOverallMemoryPhotoSlots))
        guard !trimmed.isEmpty else { return }
        guard canAddOverallMemoryPhoto else { return }
        for image in trimmed {
            if !canAddOverallMemoryPhoto { break }
            if let filename = try? PhotoStore.saveJPEG(image, userID: sessionStore.currentUserID) {
                overallMemoryImagePaths.append(filename)
            }
        }

        guard writesToPhotoLibrary else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            for image in trimmed {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: nil)
            }
        }
    }

    private func showSavedToastNow() {
        Haptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { showSavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { showSavedToast = false }
        }
    }

    // MARK: - Generate card

    private func generateShareCard() {
        guard !isGenerating else { return }
        isGenerating = true

        let raw = journey.displayRouteCoordinates.clCoords
        let safeCoords = raw.filter { CLLocationCoordinate2DIsValid($0) && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }

        let center = (safeCoords.last ?? fallbackCenter)
        let safeCenter: CLLocationCoordinate2D? = {
            guard let c = center, CLLocationCoordinate2DIsValid(c), abs(c.latitude) <= 90, abs(c.longitude) <= 180 else { return nil }
            return c
        }()

        let title = (resolvedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? {
                let fallbackTitle = JourneyCityNamePresentation.title(
                    for: journey,
                    localizedCityNameByKey: [:],
                    cachedCitiesByKey: cachedCitiesByKey
                )
                let cityKey = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
                return CityDisplayResolver.title(
                    for: cityKey,
                    fallbackTitle: fallbackTitle
                )
            }()

        let duration = durationText
        let distKm = max(0, journey.distance / 1000.0)
        let memCount = journey.memories.count
        let privacy = privacyMode

        makeShareCardImage(
            coords: safeCoords,
            fallbackCenter: safeCenter,
            title: title,
            durationText: duration,
            distanceKm: distKm,
            memoryCount: memCount,
            privacy: privacy
            , countryISO2: journey.countryISO2
            , cityKey: journey.cityKey
        ) { img in
            self.finalCardImage = img
            self.isGenerating = false
        }
    }

    private func resolveTitleIfNeeded(_ done: @escaping () -> Void) {
        let raw = journey.displayRouteCoordinates.clCoords
        let safe = raw.filter { CLLocationCoordinate2DIsValid($0) && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }

        guard !safe.isEmpty else { done(); return }

        // Use end location to resolve city name for title (localized)
        if let last = safe.last {
            let endLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let key = journey.cityKey
            let parentRegionKey = JourneyCityNamePresentation.parentRegionKey(
                for: journey,
                cachedCitiesByKey: cachedCitiesByKey
            )

            Task {
                if let title = await ReverseGeocodeService.shared.displayTitle(
                    for: endLoc,
                    cityKey: key,
                    parentRegionKey: parentRegionKey
                ) {
                    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        await MainActor.run { self.resolvedTitle = t }
                    }
                }
                await MainActor.run { done() }
            }
            return
        }

        done()
    }

    private func makeShareCardImage(
        coords: [CLLocationCoordinate2D],
        fallbackCenter: CLLocationCoordinate2D?,
        title: String,
        durationText: String,
        distanceKm: Double,
        memoryCount: Int,
        privacy: ShareMapPrivacyMode,
       countryISO2: String?,
      cityKey: String?,
        completion: @escaping (UIImage) -> Void
    ) {
        makeMapSnapshotWithRoute(
            coords: coords,
            fallbackCenter: fallbackCenter,
            privacy: privacy,
               countryISO2: countryISO2,
            cityKey: cityKey
        ) { mapImage in

            let canvasSize = CGSize(width: 900, height: 1200)

            let img = UIGraphicsImageRenderer(size: canvasSize).image { _ in
                let bgColor = UIColor.white
                let cardFill = UIColor(white: 0.985, alpha: 1)
                let textPrimary = UIColor.white.withAlphaComponent(0.98)
                let textSecondary = UIColor.white.withAlphaComponent(0.72)

                let outerMargin: CGFloat = 34
                let cardRadius: CGFloat = 34
                let statsHeight: CGFloat = 188
                let inset: CGFloat = 18
                let dividerWidth: CGFloat = 1.5

                bgColor.setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

                let cardRect = CGRect(
                    x: outerMargin,
                    y: outerMargin,
                    width: canvasSize.width - outerMargin * 2,
                    height: canvasSize.height - outerMargin * 2
                )

                let ctx = UIGraphicsGetCurrentContext()
                ctx?.saveGState()
                ctx?.setShadow(offset: .zero, blur: 18, color: UIColor.black.withAlphaComponent(0.12).cgColor)
                cardFill.setFill()
                UIBezierPath(roundedRect: cardRect, cornerRadius: cardRadius).fill()
                ctx?.restoreGState()

                UIBezierPath(roundedRect: cardRect, cornerRadius: cardRadius).addClip()
                cardFill.setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

                let mapRect = CGRect(
                    x: cardRect.minX + inset,
                    y: cardRect.minY + inset,
                    width: cardRect.width - inset * 2,
                    height: cardRect.height - inset * 2
                )
                let statsRect = CGRect(
                    x: mapRect.minX,
                    y: mapRect.maxY - statsHeight,
                    width: mapRect.width,
                    height: statsHeight
                )

                ctx?.saveGState()
                UIBezierPath(roundedRect: mapRect, cornerRadius: 26).addClip()
                mapImage.draw(in: mapRect)

                if let ctx {
                    let colors = [
                        UIColor.black.withAlphaComponent(0.00).cgColor,
                        UIColor.black.withAlphaComponent(0.36).cgColor,
                        UIColor.black.withAlphaComponent(0.62).cgColor
                    ] as CFArray
                    let locations: [CGFloat] = [0.48, 0.78, 1.0]
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                        ctx.drawLinearGradient(
                            gradient,
                            start: CGPoint(x: mapRect.midX, y: mapRect.minY),
                            end: CGPoint(x: mapRect.midX, y: mapRect.maxY),
                            options: []
                        )
                    }
                }
                ctx?.restoreGState()

                let safeTitle = title.isEmpty ? L10n.t("share_title_fallback") : title
                let pillAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.92)
                ]
                let pillTextSize = (safeTitle as NSString).size(withAttributes: pillAttr)
                let pillH: CGFloat = 52
                let pillW = min(mapRect.width - 24, pillTextSize.width + 36)

                let pillRect = CGRect(x: mapRect.minX + 16, y: mapRect.minY + 16, width: pillW, height: pillH)
                UIColor.black.withAlphaComponent(0.34).setFill()
                UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2).fill()
                (safeTitle as NSString).draw(
                    in: CGRect(x: pillRect.minX + 18, y: pillRect.minY + 10, width: pillRect.width - 36, height: 34),
                    withAttributes: pillAttr
                )

                UIColor.white.withAlphaComponent(0.18).setStroke()

                let colW = statsRect.width / 3.0
                for i in 1...2 {
                    let x = statsRect.minX + CGFloat(i) * colW
                    let v = UIBezierPath()
                    v.move(to: CGPoint(x: x, y: statsRect.minY + 42))
                    v.addLine(to: CGPoint(x: x, y: statsRect.maxY - 22))
                    v.lineWidth = dividerWidth
                    v.stroke()
                }

                let valueAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: textPrimary
                ]
                let labelAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    .foregroundColor: textSecondary
                ]

                func drawCentered(_ text: String, in rect: CGRect, attr: [NSAttributedString.Key: Any]) {
                    let ns = text as NSString
                    let s = ns.size(withAttributes: attr)
                    ns.draw(at: CGPoint(x: rect.midX - s.width/2, y: rect.midY - s.height/2), withAttributes: attr)
                }

                func drawValueAndLabel(value: String, label: String, cell: CGRect) {
                    let valueRect = CGRect(x: cell.minX, y: cell.minY + 24, width: cell.width, height: 72)
                    let labelRect = CGRect(x: cell.minX, y: cell.maxY - 52, width: cell.width, height: 28)
                    drawCentered(value, in: valueRect, attr: valueAttr)

                    // ✅ Only uppercase for English UI; keep other languages as-is.
                    let lang = Locale.current.languageCode ?? ""
                    let labelText = (lang == "en") ? label.uppercased() : label

                    drawCentered(labelText, in: labelRect, attr: labelAttr)
                }


                let leftCell  = CGRect(x: statsRect.minX, y: statsRect.minY, width: colW, height: statsRect.height)
                let midCell   = CGRect(x: statsRect.minX + colW, y: statsRect.minY, width: colW, height: statsRect.height)
                let rightCell = CGRect(x: statsRect.minX + colW * 2, y: statsRect.minY, width: colW, height: statsRect.height)

                drawValueAndLabel(value: String(format: "%.2f", max(0, distanceKm)), label: L10n.t("share_stat_distance"), cell: leftCell)
                drawValueAndLabel(value: durationText, label: L10n.t("share_stat_time"), cell: midCell)
                drawValueAndLabel(value: "\(memoryCount)", label: L10n.t("share_stat_memory"), cell: rightCell)

                UIColor.black.withAlphaComponent(0.06).setStroke()
                let innerStroke = UIBezierPath(roundedRect: cardRect.insetBy(dx: 1, dy: 1), cornerRadius: cardRadius)
                innerStroke.lineWidth = 2
                innerStroke.stroke()
            }

            DispatchQueue.main.async { completion(img) }
        }
    }

    // MARK: - Snapshot (with privacy + orange glow route + flight dashed)
    private func makeMapSnapshotWithRoute(
        coords: [CLLocationCoordinate2D],
        fallbackCenter: CLLocationCoordinate2D?,
        privacy: ShareMapPrivacyMode,
       countryISO2: String?,
      cityKey: String?,
        completion: @escaping (UIImage) -> Void
    ) {
        let snapshotSize = CGSize(width: 900, height: 1200)
        let scale: CGFloat = 2

        let stillSpan: Double = 0.0035
        let padding: Double = 1.25
        let minSpan: Double = 0.003
        let maxSpan: Double = 80.0

        // ✅ Use the same route segmentation + dash rules as MapView/City/InterCity/Thumbnails.
        let built = RouteRenderingPipeline.buildSegments(
            .init(coordsWGS84: coords, applyGCJForChina: false, gapDistanceMeters: 2_200,countryISO2: countryISO2,
                  cityKey: cityKey),
            surface: .mapKit
        )
        let drawSegments = built.segments
        let isFlightLike = built.isFlightLike
        let appearance = MapAppearanceSettings.current

        // Flatten for region calculation.
        let drawCoords = drawSegments.flatMap { $0.coords }
        let adaptedFallbackCenter = fallbackCenter.map { MapCoordAdapter.forMapKit($0, countryISO2: countryISO2, cityKey: cityKey) }

        func snapshot(region: MKCoordinateRegion, drawRoute: Bool) {
            let options = MKMapSnapshotter.Options()
            options.region = region
            options.mapType = MapAppearanceSettings.mapType(for: appearance)
            options.traitCollection = UITraitCollection(userInterfaceStyle: MapAppearanceSettings.interfaceStyle(for: appearance))
            options.size = snapshotSize
            options.scale = scale

            MKMapSnapshotter(options: options).start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, error in
                guard let snap = snapshot else {
                    if let error { print("Snapshot error:", error) }
                    DispatchQueue.main.async { completion(UIImage(systemName: "map") ?? UIImage()) }
                    return
                }

                let img = UIGraphicsImageRenderer(size: snapshotSize).image { renderer in
                    let base = snap.image

                    switch privacy {
                    case .exact:
                        base.draw(at: .zero)
                    case .hidden:
                        mapPrivacyBlurred(base, radius: 14).draw(at: .zero)
                    }

                    guard drawRoute, drawCoords.count > 1 else {
                        let centerCoord: CLLocationCoordinate2D? = drawCoords.last ?? adaptedFallbackCenter
                        guard let c = centerCoord else { return }

                        let p = snap.point(for: c)

                        // Face: if we only have 1 point, default to front
                        let face: RobotFaceSnap = .front

                        drawRobotMarker(
                            in: renderer.cgContext,
                            at: p,
                            face: face,
                            size: 112
                        )
                        return
                    }

                    // ✅ Shared segmented drawing (solid/dashed consistent across surfaces)
                    let isDarkSnap = appearance == .dark
                    RouteSnapshotDrawer.draw(
                        segments: drawSegments,
                        isFlightLike: isFlightLike,
                        snapshot: snap,
                        ctx: renderer.cgContext,
                        coreColor: MapAppearanceSettings.routeCoreColorForSnapshot(for: appearance),
                        stroke: .init(coreWidth: isFlightLike ? 8 : 7),
                        glowColor: MapAppearanceSettings.routeGlowColor(for: appearance),
                        isDarkMap: isDarkSnap
                    )
                    // ✅ Draw robot marker at the end of route
                    if let last = drawCoords.last {
                        let endPoint = snap.point(for: last)

                        let face: RobotFaceSnap = .front

                        drawRobotMarker(
                            in: renderer.cgContext,
                            at: endPoint,
                            face: face,
                            size: 112
                        )
                    }

                }

                DispatchQueue.main.async { completion(img) }
            }
        }

        if drawCoords.isEmpty {
            guard let center = adaptedFallbackCenter else {
                completion(UIImage(systemName: "map") ?? UIImage())
                return
            }
            let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: stillSpan, longitudeDelta: stillSpan))
            snapshot(region: region, drawRoute: false)
            return
        }

        if drawCoords.count == 1 {
            let region = MKCoordinateRegion(center: drawCoords[0], span: .init(latitudeDelta: stillSpan, longitudeDelta: stillSpan))
            snapshot(region: region, drawRoute: false)
            return
        }

        let lats = drawCoords.map { $0.latitude }
        let lons = drawCoords.map { $0.longitude }

        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            let center = drawCoords.last ?? fallbackCenter ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: stillSpan, longitudeDelta: stillSpan))
            snapshot(region: region, drawRoute: false)
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let rawLat = (maxLat - minLat) * padding
        let rawLon = (maxLon - minLon) * padding

        let latDelta = min(max(rawLat, minSpan), maxSpan)
        let lonDelta = min(max(rawLon, minSpan), maxSpan)

        let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: latDelta, longitudeDelta: lonDelta))
        snapshot(region: region, drawRoute: true)
    }

    private func placeholderCard() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { _ in
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 900, height: 1200)).fill()
            let icon = UIImage(systemName: "map") ?? UIImage()
            icon.draw(in: CGRect(x: 390, y: 560, width: 120, height: 120))
        }
    }
}

// =======================================================
// MARK: - Share Card Generator (for Recent Journeys)
// =======================================================

/// Re-generate the same share card image from a `JourneyRoute`.
///
/// Note: This follows the "A" approach — it does *not* rely on previously saved images.
/// If the journey data still exists, we can always re-render the card.
struct ShareCardGenerator {
    static func placeholderCard() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { _ in
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 900, height: 1200)).fill()
            let icon = UIImage(systemName: "map") ?? UIImage()
            icon.draw(in: CGRect(x: 390, y: 560, width: 120, height: 120))
        }
    }

    static func generate(
        journey: JourneyRoute,
        privacy: ShareMapPrivacyMode = .exact,
        completion: @escaping (UIImage) -> Void
    ) {
        generate(
            journey: journey,
            cachedCitiesByKey: [:],
            privacy: privacy,
            completion: completion
        )
    }

    static func generate(
        journey: JourneyRoute,
        cachedCitiesByKey: [String: CachedCity] = [:],
        privacy: ShareMapPrivacyMode = .exact,
        applyJourneyPrivacy: Bool = false,
        completion: @escaping (UIImage) -> Void
    ) {
        let raw = journey.displayRouteCoordinates
        let privacyFiltered = applyJourneyPrivacy ? journey.privacyFilteredCoordinates(raw) : raw
        let safeCoords = privacyFiltered.clCoords.filter { CLLocationCoordinate2DIsValid($0) && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }

        let center = safeCoords.last
        let safeCenter: CLLocationCoordinate2D? = {
            guard let c = center, CLLocationCoordinate2DIsValid(c), abs(c.latitude) <= 90, abs(c.longitude) <= 180 else { return nil }
            return c
        }()

        let duration = durationText(for: journey)
        let distKm = max(0, journey.distance / 1000.0)
        let memCount = journey.memories.count

        resolveTitleIfNeeded(
            journey: journey,
            coords: safeCoords,
            cachedCitiesByKey: cachedCitiesByKey
        ) { resolvedTitle in
            let title = (resolvedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? {
                    let fallbackTitle = JourneyCityNamePresentation.title(
                        for: journey,
                        localizedCityNameByKey: [:],
                        cachedCitiesByKey: cachedCitiesByKey
                    )
                    let cityKey = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
                    return CityDisplayResolver.title(
                        for: cityKey,
                        fallbackTitle: fallbackTitle
                    )
                }()

            makeShareCardImage(
                coords: safeCoords,
                fallbackCenter: safeCenter,
                title: title,
                durationText: duration,
                distanceKm: distKm,
                memoryCount: memCount,
                privacy: privacy,
                countryISO2: journey.countryISO2,
                cityKey: journey.cityKey,
                hideLandmarks: applyJourneyPrivacy && journey.shouldHideLandmarks,
                completion: completion
            )
        }
    }

    /// Generate unlock preview image using the same map+route pipeline as share card,
    /// but without title/stats overlays and robot marker.
    static func generateUnlockMapPreview(
        journey: JourneyRoute,
        size: CGSize = CGSize(width: 1200, height: 660),
        completion: @escaping (UIImage) -> Void
    ) {
        let raw = journey.displayRouteCoordinates.clCoords
        let safeCoords = raw.filter { CLLocationCoordinate2DIsValid($0) && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }

        let center = safeCoords.last
        let safeCenter: CLLocationCoordinate2D? = {
            guard let c = center, CLLocationCoordinate2DIsValid(c), abs(c.latitude) <= 90, abs(c.longitude) <= 180 else { return nil }
            return c
        }()

        makeMapSnapshotWithRoute(
            coords: safeCoords,
            fallbackCenter: safeCenter,
            privacy: .exact,
            countryISO2: journey.countryISO2,
            cityKey: journey.cityKey,
            snapshotSize: size,
            drawRobot: false,
            completion: completion
        )
    }

    private static func durationText(for journey: JourneyRoute) -> String {
        guard let start = journey.startTime else {
            return String(format: L10n.t("share_duration_min"), 0)
        }
        let end = journey.endTime ?? Date()
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return String(format: L10n.t("share_duration_min"), minutes)
    }

    private static func resolveTitleIfNeeded(
        journey: JourneyRoute,
        coords: [CLLocationCoordinate2D],
        cachedCitiesByKey: [String: CachedCity],
        _ done: @escaping (String?) -> Void
    ) {
        guard !coords.isEmpty else { done(nil); return }

        if let last = coords.last {
            let endLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let key = journey.cityKey
            let parentRegionKey = JourneyCityNamePresentation.parentRegionKey(
                for: journey,
                cachedCitiesByKey: cachedCitiesByKey
            )

            Task {
                let title = await ReverseGeocodeService.shared.displayTitle(
                    for: endLoc,
                    cityKey: key,
                    parentRegionKey: parentRegionKey
                )
                let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run { done((t?.isEmpty ?? true) ? nil : t) }
            }
            return
        }

        done(nil)
    }

    private static func makeShareCardImage(
        coords: [CLLocationCoordinate2D],
        fallbackCenter: CLLocationCoordinate2D?,
        title: String,
        durationText: String,
        distanceKm: Double,
        memoryCount: Int,
        privacy: ShareMapPrivacyMode,
        countryISO2: String?,
        cityKey: String?,
        hideLandmarks: Bool = false,
        completion: @escaping (UIImage) -> Void
    ) {
        makeMapSnapshotWithRoute(
            coords: coords,
            fallbackCenter: fallbackCenter,
            privacy: privacy,
            countryISO2: countryISO2,
            cityKey: cityKey,
            hideLandmarks: hideLandmarks
        ) { mapImage in

            let canvasSize = CGSize(width: 900, height: 1200)

            let img = UIGraphicsImageRenderer(size: canvasSize).image { _ in
                let bgColor = UIColor.white
                let cardFill = UIColor(white: 0.985, alpha: 1)
                let textPrimary = UIColor.white.withAlphaComponent(0.98)
                let textSecondary = UIColor.white.withAlphaComponent(0.72)

                let outerMargin: CGFloat = 34
                let cardRadius: CGFloat = 34
                let statsHeight: CGFloat = 188
                let inset: CGFloat = 18
                let dividerWidth: CGFloat = 1.5

                bgColor.setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

                let cardRect = CGRect(
                    x: outerMargin,
                    y: outerMargin,
                    width: canvasSize.width - outerMargin * 2,
                    height: canvasSize.height - outerMargin * 2
                )

                let ctx = UIGraphicsGetCurrentContext()
                ctx?.saveGState()
                ctx?.setShadow(offset: .zero, blur: 18, color: UIColor.black.withAlphaComponent(0.12).cgColor)
                cardFill.setFill()
                UIBezierPath(roundedRect: cardRect, cornerRadius: cardRadius).fill()
                ctx?.restoreGState()

                UIBezierPath(roundedRect: cardRect, cornerRadius: cardRadius).addClip()
                cardFill.setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

                let mapRect = CGRect(
                    x: cardRect.minX + inset,
                    y: cardRect.minY + inset,
                    width: cardRect.width - inset * 2,
                    height: cardRect.height - inset * 2
                )
                let statsRect = CGRect(
                    x: mapRect.minX,
                    y: mapRect.maxY - statsHeight,
                    width: mapRect.width,
                    height: statsHeight
                )

                ctx?.saveGState()
                UIBezierPath(roundedRect: mapRect, cornerRadius: 26).addClip()
                mapImage.draw(in: mapRect)

                if let ctx {
                    let colors = [
                        UIColor.black.withAlphaComponent(0.00).cgColor,
                        UIColor.black.withAlphaComponent(0.36).cgColor,
                        UIColor.black.withAlphaComponent(0.62).cgColor
                    ] as CFArray
                    let locations: [CGFloat] = [0.48, 0.78, 1.0]
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                        ctx.drawLinearGradient(
                            gradient,
                            start: CGPoint(x: mapRect.midX, y: mapRect.minY),
                            end: CGPoint(x: mapRect.midX, y: mapRect.maxY),
                            options: []
                        )
                    }
                }
                ctx?.restoreGState()

                let safeTitle = title.isEmpty ? L10n.t("share_title_fallback") : title
                let pillAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.92)
                ]
                let pillTextSize = (safeTitle as NSString).size(withAttributes: pillAttr)
                let pillH: CGFloat = 52
                let pillW = min(mapRect.width - 24, pillTextSize.width + 36)

                let pillRect = CGRect(x: mapRect.minX + 16, y: mapRect.minY + 16, width: pillW, height: pillH)
                UIColor.black.withAlphaComponent(0.34).setFill()
                UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2).fill()
                (safeTitle as NSString).draw(
                    in: CGRect(x: pillRect.minX + 18, y: pillRect.minY + 10, width: pillRect.width - 36, height: 34),
                    withAttributes: pillAttr
                )

                UIColor.white.withAlphaComponent(0.18).setStroke()

                let colW = statsRect.width / 3.0
                for i in 1...2 {
                    let x = statsRect.minX + CGFloat(i) * colW
                    let v = UIBezierPath()
                    v.move(to: CGPoint(x: x, y: statsRect.minY + 42))
                    v.addLine(to: CGPoint(x: x, y: statsRect.maxY - 22))
                    v.lineWidth = dividerWidth
                    v.stroke()
                }

                let valueAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: textPrimary
                ]
                let labelAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    .foregroundColor: textSecondary
                ]

                func drawCentered(_ text: String, in rect: CGRect, attr: [NSAttributedString.Key: Any]) {
                    let ns = text as NSString
                    let s = ns.size(withAttributes: attr)
                    ns.draw(at: CGPoint(x: rect.midX - s.width/2, y: rect.midY - s.height/2), withAttributes: attr)
                }

                func drawValueAndLabel(value: String, label: String, cell: CGRect) {
                    let valueRect = CGRect(x: cell.minX, y: cell.minY + 24, width: cell.width, height: 72)
                    let labelRect = CGRect(x: cell.minX, y: cell.maxY - 52, width: cell.width, height: 28)
                    drawCentered(value, in: valueRect, attr: valueAttr)

                    let lang = Locale.current.languageCode ?? ""
                    let labelText = (lang == "en") ? label.uppercased() : label
                    drawCentered(labelText, in: labelRect, attr: labelAttr)
                }

                let leftCell  = CGRect(x: statsRect.minX, y: statsRect.minY, width: colW, height: statsRect.height)
                let midCell   = CGRect(x: statsRect.minX + colW, y: statsRect.minY, width: colW, height: statsRect.height)
                let rightCell = CGRect(x: statsRect.minX + colW * 2, y: statsRect.minY, width: colW, height: statsRect.height)

                drawValueAndLabel(value: String(format: "%.2f", max(0, distanceKm)), label: L10n.t("share_stat_distance"), cell: leftCell)
                drawValueAndLabel(value: durationText, label: L10n.t("share_stat_time"), cell: midCell)
                drawValueAndLabel(value: "\(memoryCount)", label: L10n.t("share_stat_memory"), cell: rightCell)

                UIColor.black.withAlphaComponent(0.06).setStroke()
                let innerStroke = UIBezierPath(roundedRect: cardRect.insetBy(dx: 1, dy: 1), cornerRadius: cardRadius)
                innerStroke.lineWidth = 2
                innerStroke.stroke()
            }

            DispatchQueue.main.async { completion(img) }
        }
    }

    // MARK: - Snapshot (with privacy + orange glow route + flight dashed)
    private static func makeMapSnapshotWithRoute(
        coords: [CLLocationCoordinate2D],
        fallbackCenter: CLLocationCoordinate2D?,
        privacy: ShareMapPrivacyMode,
        countryISO2: String?,
        cityKey: String?,
        snapshotSize: CGSize = CGSize(width: 900, height: 1200),
        drawRobot: Bool = true,
        hideLandmarks: Bool = false,
        completion: @escaping (UIImage) -> Void
    ) {
        let scale: CGFloat = 2

        let stillSpan: Double = 0.0035
        let padding: Double = 1.25
        let minSpan: Double = 0.003
        let maxSpan: Double = 80.0

        let built = RouteRenderingPipeline.buildSegments(
            .init(coordsWGS84: coords, applyGCJForChina: false, gapDistanceMeters: 2_200, countryISO2: countryISO2, cityKey: cityKey),
            surface: .mapKit
        )
        let drawSegments = built.segments
        let isFlightLike = built.isFlightLike
        let appearance = MapAppearanceSettings.current

        let drawCoords = drawSegments.flatMap { $0.coords }
        let adaptedFallbackCenter = fallbackCenter.map { MapCoordAdapter.forMapKit($0, countryISO2: countryISO2, cityKey: cityKey) }

        func snapshot(region: MKCoordinateRegion, drawRoute: Bool) {
            let options = MKMapSnapshotter.Options()
            options.region = region
            options.mapType = MapAppearanceSettings.mapType(for: appearance)
            options.traitCollection = UITraitCollection(userInterfaceStyle: MapAppearanceSettings.interfaceStyle(for: appearance))
            options.size = snapshotSize
            options.scale = scale
            if hideLandmarks {
                options.showsPointsOfInterest = false
            }

            MKMapSnapshotter(options: options).start(with: DispatchQueue.global(qos: .userInitiated)) { snapshot, error in
                guard let snap = snapshot else {
                    if let error { print("Snapshot error:", error) }
                    DispatchQueue.main.async { completion(UIImage(systemName: "map") ?? UIImage()) }
                    return
                }

                let img = UIGraphicsImageRenderer(size: snapshotSize).image { renderer in
                    let base = snap.image
                    let shouldBlur = (privacy == .hidden) || hideLandmarks

                    if shouldBlur {
                        mapPrivacyBlurred(base, radius: 14).draw(at: .zero)
                    } else {
                        base.draw(at: .zero)
                    }

                    guard drawRoute, drawCoords.count > 1 else {
                        guard drawRobot else { return }
                        let centerCoord: CLLocationCoordinate2D? = drawCoords.last ?? adaptedFallbackCenter
                        guard let c = centerCoord else { return }
                        let p = snap.point(for: c)
                        let face: RobotFaceSnap = .front
                        drawRobotMarker(
                            in: renderer.cgContext,
                            at: p,
                            face: face,
                            size: 112
                        )
                        return
                    }

                    let isDarkSnap2 = appearance == .dark
                    RouteSnapshotDrawer.draw(
                        segments: drawSegments,
                        isFlightLike: isFlightLike,
                        snapshot: snap,
                        ctx: renderer.cgContext,
                        coreColor: MapAppearanceSettings.routeCoreColorForSnapshot(for: appearance),
                        stroke: .init(coreWidth: isFlightLike ? 8 : 7),
                        glowColor: MapAppearanceSettings.routeGlowColor(for: appearance),
                        isDarkMap: isDarkSnap2
                    )

                    if drawRobot, let last = drawCoords.last {
                        let endPoint = snap.point(for: last)

                        let face: RobotFaceSnap = .front

                        drawRobotMarker(
                            in: renderer.cgContext,
                            at: endPoint,
                            face: face,
                            size: 112
                        )
                    }
                }

                DispatchQueue.main.async { completion(img) }
            }
        }

        if drawCoords.isEmpty {
            guard let center = adaptedFallbackCenter else {
                completion(UIImage(systemName: "map") ?? UIImage())
                return
            }
            let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: stillSpan, longitudeDelta: stillSpan))
            snapshot(region: region, drawRoute: false)
            return
        }

        if drawCoords.count == 1 {
            let region = MKCoordinateRegion(center: drawCoords[0], span: .init(latitudeDelta: stillSpan, longitudeDelta: stillSpan))
            snapshot(region: region, drawRoute: false)
            return
        }

        let lats = drawCoords.map { $0.latitude }
        let lons = drawCoords.map { $0.longitude }

        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            let center = drawCoords.last ?? fallbackCenter ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: stillSpan, longitudeDelta: stillSpan))
            snapshot(region: region, drawRoute: false)
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let rawLat = (maxLat - minLat) * padding
        let rawLon = (maxLon - minLon) * padding

        let latDelta = min(max(rawLat, minSpan), maxSpan)
        let lonDelta = min(max(rawLon, minSpan), maxSpan)

        let region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: latDelta, longitudeDelta: lonDelta))
        snapshot(region: region, drawRoute: true)
    }
}

// =======================================================
// MARK: - Unlock Modal (City / InterCity)
// =======================================================

struct UnlockModal: View {
    @EnvironmentObject private var onboardingGuide: OnboardingGuideStore
    let payload: UnlockedPayload
    let journey: JourneyRoute
    @Binding var isPresented: Bool
    var onGoToLibrary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 8)

            Text(payload.kind == .city ? L10n.t("unlock_new_city") : L10n.t("unlock_new_route"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray)

            UnlockRouteMapPreview(journey: journey)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)

            VStack(spacing: 6) {
                Text(payload.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let sub = payload.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button {
                    isPresented = false
                } label: {
                    Text(L10n.t("close"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))))
                }

                Button {
                    isPresented = false
                    onGoToLibrary?()
                    onboardingGuide.advance(.openCityCards)
                } label: {
                    Text(L10n.t("go_to_library"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
                        .overlay {
                            if onboardingGuide.isCurrent(.openCityCards) {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white, lineWidth: 2)
                            }
                        }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .overlay(alignment: .bottom) {
            if onboardingGuide.isCurrent(.openCityCards) {
                OnboardingCoachCard(
                    message: OnboardingGuideStore.Step.openCityCards.message,
                    actionTitle: OnboardingGuideStore.Step.openCityCards.actionTitle,
                    onAction: {
                        isPresented = false
                        onGoToLibrary?()
                        onboardingGuide.advance(.openCityCards)
                    },
                    onLater: { onboardingGuide.pauseForLater() },
                    onSkip: { onboardingGuide.skipAll() }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct UnlockRouteMapPreview: View {
    let journey: JourneyRoute
    @State private var image: UIImage?
    @State private var isGenerating = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(UIColor.systemGray6))
                    .overlay {
                        VStack(spacing: 8) {
                            if isGenerating {
                                ProgressView()
                            }
                            Text(L10n.key("loading_map"))
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
            }
        }
        .onAppear {
            guard !isGenerating, image == nil else { return }
            isGenerating = true
            ShareCardGenerator.generateUnlockMapPreview(journey: journey) { generated in
                image = generated
                isGenerating = false
            }
        }
    }
}

// MARK: - Blur helper (CoreImage)
/// Gaussian blur utility for map privacy rendering. Accessible from other files.
func mapPrivacyBlurred(_ image: UIImage, radius: Double = 14) -> UIImage {
    guard let cg = image.cgImage else { return image }
    let ciImage = CIImage(cgImage: cg)

    let context = CIContext(options: nil)
    let filter = CIFilter.gaussianBlur()
    filter.inputImage = ciImage
    filter.radius = Float(radius)

    guard let output = filter.outputImage else { return image }

    let cropped = output.cropped(to: ciImage.extent)
    guard let cgOut = context.createCGImage(cropped, from: ciImage.extent) else { return image }
    return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
}

private func drawPrivacyLandmarkShadow(in ctx: CGContext, rect: CGRect) {
    ctx.saveGState()

    UIColor.black.withAlphaComponent(0.12).setFill()
    UIRectFillUsingBlendMode(rect, .multiply)

    let colors = [
        UIColor.black.withAlphaComponent(0.06).cgColor,
        UIColor.black.withAlphaComponent(0.16).cgColor,
        UIColor.black.withAlphaComponent(0.26).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.58, 1.0]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
    }

    ctx.restoreGState()
}

// MARK: - ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.permittedArrowDirections = []
            pop.sourceView = UIView()
            pop.sourceRect = .zero
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Robot Marker Helpers (Sharing snapshot)

private enum RobotFaceSnap: String {
    case front, right, back, left
}

private func robotFaceFromHeadingSnap(_ headingDegrees: Double) -> RobotFaceSnap {
    let h = (headingDegrees.truncatingRemainder(dividingBy: 360) + 360)
        .truncatingRemainder(dividingBy: 360)

    switch h {
    case 45..<135:  return .right
    case 135..<225: return .back
    case 225..<315: return .left
    default:        return .front
    }
}

private func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
    // Bearing in degrees [0, 360), where 0 = North, 90 = East
    let lat1 = a.latitude * .pi / 180
    let lat2 = b.latitude * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180

    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    var brng = atan2(y, x) * 180 / .pi
    brng = (brng + 360).truncatingRemainder(dividingBy: 360)
    return brng
}

private func toRobotFace(_ face: RobotFaceSnap) -> RobotFace {
    switch face {
    case .front: return .front
    case .right: return .right
    case .back: return .back
    case .left: return .left
    }
}

private func avatarImageForFace(_ face: RobotFaceSnap, size: CGFloat) -> UIImage? {
    let render: () -> UIImage? = {
        let view = RobotRendererView(
            size: size,
            face: toRobotFace(face),
            loadout: AvatarLoadoutStore.load()
        )
        let host = UIHostingController(rootView: view)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        host.view.frame = rect
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: rect.size, format: format).image { renderer in
            // Prefer drawHierarchy for SwiftUI-backed views; fallback to layer.render.
            let drewHierarchy = host.view.drawHierarchy(in: rect, afterScreenUpdates: true)
            if !drewHierarchy {
                host.view.layer.render(in: renderer.cgContext)
            }
        }
    }

    // UIKit/SwiftUI view tree rendering must run on main thread.
    if Thread.isMainThread {
        return render()
    }

    var output: UIImage?
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
        output = render()
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 3.0)
    return output
}

private func drawRobotMarker(
    in ctx: CGContext,
    at point: CGPoint,
    face: RobotFaceSnap,
    size: CGFloat
) {
    guard let img = avatarImageForFace(face, size: size) else { return }

    // Keep the same transparent avatar rendering style as RobotRendererView in MapView.
    let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
    img.draw(in: rect)
}
