//
//  ProfileView.swift
//  StreetStamps
//
//  Created by Claire Yang on 18/01/2026.
//

import Foundation
import SwiftUI
import UIKit
import CoreLocation
import AVFoundation
import PhotosUI

private struct NotifJourneyPush: Identifiable, Hashable {
    let id: String // journeyID
}

struct ProfileView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var notificationStore: SocialNotificationStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @ObservedObject private var languagePreference = LanguagePreference.shared
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var loadout: RobotLoadout
    @State private var showNameEditor = false
    @State private var nameDraft = ""
    @State private var nameError = ""
    @State private var isSavingName = false
    @State private var toastText = ""
    @State private var showToast = false
    @ObservedObject private var featureFlags = FeatureFlagStore.shared
    @State private var showNotificationsSheet = false
    @State private var showPostcardInboxFromNotification = false
    @State private var notifSheetJourneyPush: NotifJourneyPush? = nil
    @State private var postcardInboxIntent = PostcardInboxIntent(box: "received", messageID: nil)
    @State private var lastSyncedLoadout: RobotLoadout?
    @State private var pendingLocalLoadout: RobotLoadout?
    @State private var loadoutSyncTask: Task<Void, Never>?

    init() {
        self._loadout = State(initialValue: AvatarLoadoutStore.load())
    }

    
    // Computed stats
    private var totalJourneys: Int {
        store.journeys.count
    }
    
    private var citiesVisited: Int {
        cityCache.cachedCities.count
    }

    private var totalMemories: Int {
        store.journeys.reduce(0) { $0 + $1.memories.count }
    }

    private var levelProgress: UserLevelProgress {
        UserLevelProgress.from(journeys: store.journeys)
    }

    private var displayName: String {
        let value = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("explorer_fallback") : value
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                FigmaTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerView
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            avatarHeaderCard
                            topActionRow
                        }
                        .frame(maxWidth: 430)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 56)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                if showToast {
                    Text(toastText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onChange(of: loadout) { _, newValue in
            UserScopedProfileStateStore.saveCurrentLoadout(newValue, for: sessionStore.currentUserID)
            UserScopedProfileStateStore.markPendingLoadout(newValue, for: sessionStore.currentUserID)
            pendingLocalLoadout = UserScopedProfileStateStore.pendingLoadout(for: sessionStore.currentUserID)
            scheduleLoadoutSync(newValue)
        }
        .sheet(isPresented: $showNameEditor) {
            profileNameEditorSheet
        }
        .sheet(isPresented: $showNotificationsSheet) {
            if featureFlags.socialEnabled {
                socialNotificationsSheet
            }
        }
        .sheet(isPresented: $showPostcardInboxFromNotification) {
            if featureFlags.socialEnabled {
                let initialBox: PostcardInboxView.Box = postcardInboxIntent.box == "sent" ? .sent : .received
                NavigationStack {
                    PostcardInboxView(
                        initialBox: initialBox,
                        focusMessageID: postcardInboxIntent.messageID
                    )
                    .id(PostcardInboxView.viewIdentity(initialBox: initialBox, focusMessageID: postcardInboxIntent.messageID))
                }
            }
        }
        .task {
            pendingLocalLoadout = UserScopedProfileStateStore.pendingLoadout(for: sessionStore.currentUserID)
            if let pendingLocalLoadout {
                loadout = pendingLocalLoadout
                scheduleLoadoutSync(pendingLocalLoadout)
            }
            await refreshDisplayNameIfNeeded()
            if featureFlags.socialEnabled {
                await notificationStore.refresh(token: sessionStore.currentAccessToken, showToastCallback: { msg in showToastMessage(msg) })
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if featureFlags.socialEnabled {
                    await notificationStore.refresh(token: sessionStore.currentAccessToken, showToastCallback: { msg in showToastMessage(msg) })
                }
            }
        }
        .onChange(of: sessionStore.currentAccessToken) { _, _ in
            Task {
                pendingLocalLoadout = UserScopedProfileStateStore.pendingLoadout(for: sessionStore.currentUserID)
                if let pendingLocalLoadout {
                    loadout = pendingLocalLoadout
                    scheduleLoadoutSync(pendingLocalLoadout)
                }
                await refreshDisplayNameIfNeeded()
                if featureFlags.socialEnabled {
                    await notificationStore.refresh(token: sessionStore.currentAccessToken)
                }
            }
        }
        .onChange(of: sessionStore.currentUserID) { _, _ in
            loadout = AvatarLoadoutStore.load()
            lastSyncedLoadout = nil
            pendingLocalLoadout = UserScopedProfileStateStore.pendingLoadout(for: sessionStore.currentUserID)
            if let pendingLocalLoadout {
                loadout = pendingLocalLoadout
                scheduleLoadoutSync(pendingLocalLoadout)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialNotificationsDidMarkRead)) { notification in
            notificationStore.applyReadSync(notification)
        }
    }
    
    // MARK: - Header View
    
    // MARK: - Updated Profile Header to match UI script

    private var headerView: some View {
        HStack {
            Color.clear
                .frame(width: 42, height: 42)

            Spacer()

            Text(L10n.t("profile_title"))
                .navigationTitleStyle(level: .primary)
                .tracking(0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer()

            NavigationLink {
                SettingsView(showsBackButton: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .appMinTapTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var avatarHeaderCard: some View {
        let sceneState = ProfileSceneInteractionState.resolve(
            mode: .myProfile,
            isViewingOwnFriendProfile: false,
            isVisitorSeated: false,
            isInteractionInFlight: false
        )

        return VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ProfileHeroTopBackdrop(topCornerRadius: 28) {
                    VStack {
                        SofaProfileSceneView(
                            state: sceneState,
                            hostLoadout: loadout
                        )
                        .frame(maxWidth: 340)
                        .padding(.horizontal, 18)
                        .padding(.top, 22)
                        .padding(.bottom, 14)
                    }
                }
                .frame(height: 252)

                if featureFlags.socialEnabled,
                   ProfileHeaderPresentation.showsNotificationCloud(notificationCount: notificationStore.notifications.count) {
                    Button {
                        showNotificationsSheet = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(red: 0.22, green: 0.45, blue: 0.89))
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.95))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)

                            if notificationStore.unreadCount > 0 {
                                Text("\(min(notificationStore.unreadCount, 99))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 10, y: -8)
                            }
                        }
                        .appMinTapTarget()
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                NavigationLink {
                    EquipmentView(loadout: $loadout)
                } label: {
                    Image(systemName: "tshirt")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.primary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.95))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                        .appMinTapTarget()
                }
                .buttonStyle(.plain)
                .padding(6)
            }

            Button {
                nameDraft = displayName == L10n.t("explorer_fallback") ? "" : displayName
                nameError = ""
                showNameEditor = true
            } label: {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundColor(FigmaTheme.text)

                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.45))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.gray.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }

    private var topActionRow: some View {
        VStack(spacing: 20) {
            if featureFlags.socialEnabled {
                NavigationLink {
                    PostcardInboxView()
                } label: {
                    postcardTile
                }
                .buttonStyle(.plain)
            }

            CompactActivityRingCard(
                stats: ProfileStatsSnapshot(
                    totalJourneys: totalJourneys,
                    totalDistance: store.journeys.reduce(0) { $0 + $1.distance },
                    totalMemories: totalMemories,
                    totalUnlockedCities: citiesVisited
                ),
                levelProgress: levelProgress,
                journeyDates: store.journeys.compactMap { $0.endTime ?? $0.startTime },
                onCardsTap: {
                    flow.requestSelectCollectionPage(0)
                    flow.requestSelectTab(.cities)
                },
                onMemoriesTap: {
                    flow.requestSelectCollectionPage(1)
                    flow.requestSelectTab(.cities)
                }
            )
        }
    }

    private func profileMenuTile(icon: String, iconColor: Color, iconBg: Color, title: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(iconBg)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 136)
        .padding(.vertical, 8)
        .profileFeatureCardStyle()
    }

    private func embeddedStatItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(0.1)
                    .foregroundColor(FigmaTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(FigmaTheme.subtext)
        }
        .frame(maxWidth: .infinity)
    }

    private var postcardTile: some View {
        ProfilePostcardEntryCard(
            title: L10n.t("postcard_profile_title"),
            subtitle: L10n.t("postcard_profile_subtitle")
        )
    }

    @ViewBuilder
    private var socialNotificationsSheet: some View {
        NavigationStack {
            Group {
                if notificationStore.isLoading && notificationStore.notifications.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.t("profile_notifications_loading"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if notificationStore.notifications.isEmpty {
                    Text(L10n.t("profile_notifications_empty"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(notificationStore.notifications) { item in
                                socialNotificationRow(item)
                                    .scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { content, phase in
                                        content
                                            .opacity(phase.isIdentity ? 1 : 0.3)
                                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(FigmaTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                UnifiedNavigationHeader(
                    chrome: NavigationChrome(
                        title: L10n.t("profile_notifications_title"),
                        leadingAccessory: .back,
                        titleLevel: .secondary
                    ),
                    horizontalPadding: 16,
                    topPadding: 8,
                    bottomPadding: 12,
                    onLeadingTap: { showNotificationsSheet = false }
                ) {
                    Button {
                        Task {
                            await notificationStore.markAllRead(token: sessionStore.currentAccessToken)
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                            .appMinTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("friends_mark_all_read"))
                }
            }
            .navigationDestination(item: $notifSheetJourneyPush) { push in
                SelfJourneyDetailScreen(journeyID: push.id)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await notificationStore.refresh(token: sessionStore.currentAccessToken)
            }
        }
    }

    private func socialNotificationRow(_ item: BackendNotificationItem) -> some View {
        let isLike = item.type == "journey_like"
        let isPostcard = item.type == "postcard_received"
        let badgeTitle = SocialNotificationPresentation.badgeTitle(for: item)
        let badgeColor = isPostcard
            ? Color(red: 0.35, green: 0.40, blue: 0.88)
            : (isLike ? Color.red : Color(red: 0.22, green: 0.45, blue: 0.89))

        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.read ? Color.clear : Color(red: 0.22, green: 0.45, blue: 0.89))
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(badgeTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(
                            item.read
                            ? FigmaTheme.subtext
                            : badgeColor
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(item.read ? Color.black.opacity(0.03) : Color.black.opacity(0.06))
                        .clipShape(Capsule())

                    Text(relativeTimeText(item.createdAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                }

                Text(SocialNotificationPresentation.message(for: item))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(item.read ? FigmaTheme.subtext : FigmaTheme.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(item.read ? Color(white: 0.97) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
        .onTapGesture {
            guard featureFlags.socialEnabled else { return }
            Task {
                await notificationStore.markSingleRead(id: item.id, token: sessionStore.currentAccessToken)
                if item.type == "postcard_received" || item.type == "postcard_reaction" {
                    let box = item.type == "postcard_received" ? "received" : "sent"
                    postcardInboxIntent = PostcardInboxIntent(box: box, messageID: item.postcardMessageID)
                    showNotificationsSheet = false
                    showPostcardInboxFromNotification = true
                } else if item.type == "friend_request" {
                    showNotificationsSheet = false
                    AppFlowCoordinator.shared.requestSelectTab(.friends)
                } else if item.type == "journey_like",
                          let jid = item.journeyID?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !jid.isEmpty {
                    notifSheetJourneyPush = NotifJourneyPush(id: jid)
                }
            }
        }
    }

    @ViewBuilder
    private var profileNameEditorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("profile_edit_name_hint"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                TextField(L10n.t("profile_name_placeholder"), text: $nameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .semibold))

                Text(L10n.t("profile_name_rules"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)

                if !nameError.isEmpty {
                    Text(nameError)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red)
                }

                Spacer()
            }
            .padding(16)
            .safeAreaInset(edge: .top, spacing: 0) {
                UnifiedNavigationHeader(
                    chrome: NavigationChrome(
                        title: L10n.t("profile_edit_name_title"),
                        leadingAccessory: .back,
                        titleLevel: .secondary
                    ),
                    horizontalPadding: 16,
                    topPadding: 8,
                    bottomPadding: 12,
                    onLeadingTap: { showNameEditor = false }
                ) {
                    Button(isSavingName ? L10n.t("profile_name_saving") : L10n.t("save")) {
                        Task {
                            await saveDisplayName()
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .disabled(isSavingName)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func validateDisplayName(_ raw: String) -> String? {
        DisplayNameValidator.validate(raw)
    }

    @MainActor
    private func saveDisplayName() async {
        if let error = validateDisplayName(nameDraft) {
            nameError = error
            return
        }
        nameError = ""
        isSavingName = true
        defer { isSavingName = false }

        let normalized = DisplayNameValidator.normalize(nameDraft)

        if BackendConfig.isEnabled,
           let token = sessionStore.currentAccessToken,
           !token.isEmpty {
            do {
                let profile = try await BackendAPIClient.shared.updateDisplayName(
                    token: token,
                    displayName: normalized
                )
                profileName = profile.displayName
                showNameEditor = false
                showToastMessage(L10n.t("profile_name_updated"))
            } catch {
                showToastMessage(error.localizedDescription)
            }
        } else {
            profileName = normalized
            showNameEditor = false
            showToastMessage(L10n.t("profile_name_updated"))
        }
    }

    @MainActor
    private func refreshDisplayNameIfNeeded() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            return
        }
        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            pendingLocalLoadout = UserScopedProfileStateStore.pendingLoadout(for: sessionStore.currentUserID)
            if let remoteLoadout = me.loadout?.normalizedForCurrentAvatar() {
                let merge = ProfileLoadoutRemoteMerge.resolve(
                    remoteLoadout: remoteLoadout,
                    currentLocal: loadout,
                    lastSynced: lastSyncedLoadout,
                    pendingLocal: pendingLocalLoadout
                )
                lastSyncedLoadout = merge.lastSyncedLoadout
                pendingLocalLoadout = merge.pendingLocalLoadout
                if merge.pendingLocalLoadout == nil {
                    UserScopedProfileStateStore.clearPendingLoadout(for: sessionStore.currentUserID)
                }
                if let appliedLoadout = merge.appliedLoadout {
                    loadout = appliedLoadout
                }
            }
            if !me.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profileName = me.displayName
            }
        } catch {
            // Keep profile editable even if backend request fails.
        }
    }

    @MainActor
    private func scheduleLoadoutSync(_ target: RobotLoadout) {
        loadoutSyncTask?.cancel()
        loadoutSyncTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            await syncLoadoutIfNeeded(target)
        }
    }

    @MainActor
    private func syncLoadoutIfNeeded(_ target: RobotLoadout) async {
        let normalizedTarget = target.normalizedForCurrentAvatar()
        if let last = lastSyncedLoadout, last == normalizedTarget { return }
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else { return }
        do {
            let profile = try await BackendAPIClient.shared.updateLoadout(token: token, loadout: normalizedTarget)
            let resolvedRemote = (profile.loadout ?? normalizedTarget).normalizedForCurrentAvatar()
            lastSyncedLoadout = resolvedRemote
            if pendingLocalLoadout?.normalizedForCurrentAvatar() == normalizedTarget ||
                pendingLocalLoadout?.normalizedForCurrentAvatar() == resolvedRemote {
                pendingLocalLoadout = nil
                UserScopedProfileStateStore.clearPendingLoadout(for: sessionStore.currentUserID)
            }
            UserScopedProfileStateStore.saveCurrentLoadout(resolvedRemote, for: sessionStore.currentUserID)
        } catch {
            // Keep local loadout usable even when cloud sync fails temporarily.
        }
    }


    private func relativeTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @MainActor
    private func showToastMessage(_ text: String) {
        Haptics.success()
        toastText = text
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showToast = false
            }
        }
    }

}

struct InviteFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    let displayName: String
    let loadout: RobotLoadout
    let exclusiveID: String
    let inviteCode: String

    @State private var qrImage: UIImage?
    @State private var shareCardImage: UIImage?
    @State private var showShare = false
    @State private var copiedToast = ""
    @State private var showCopiedToast = false
    @State private var requestInput = ""
    @State private var sendingRequest = false
    @State private var requestMessage = ""
    @State private var showRequestMessage = false
    @State private var showScannerSheet = false

    private var presentation: InviteFriendPresentation {
        InviteFriendPresentation(
            displayName: displayName,
            exclusiveID: exclusiveID,
            inviteCode: inviteCode
        )
    }

    private var inviteDeepLink: String {
        var components = URLComponents()
        components.scheme = "streetstamps"
        components.host = "add-friend"
        components.queryItems = [
            URLQueryItem(name: "code", value: inviteCode),
            URLQueryItem(name: "handle", value: exclusiveID)
        ]
        return components.string ?? "streetstamps://add-friend?code=\(inviteCode)&handle=\(exclusiveID)"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            RobotRendererView(
                                size: 58,
                                face: .front,
                                loadout: loadout
                            )
                            .frame(width: 58, height: 58)
                            .background(Color.black.opacity(0.04))
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.t("app_name"))
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(FigmaTheme.text)
                                Text(L10n.t("profile_friend_invite_code"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(FigmaTheme.subtext)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        if let qrImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 210, height: 210)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(FigmaTheme.border, lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 220, height: 220)
                                .overlay {
                                    ProgressView()
                                }
                        }

                        Text(presentation.titleText)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        if let visibleExclusiveIDText = presentation.visibleExclusiveIDText {
                            Text(visibleExclusiveIDText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(FigmaTheme.subtext)
                        }

                        HStack(spacing: 10) {
                            Text(presentation.codeText)
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(FigmaTheme.text)
                                .tracking(1.6)
                            Button {
                                copyText(presentation.codeText, success: L10n.t("profile_invite_code_copied"))
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(FigmaTheme.subtext)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.06))
                                    .clipShape(Circle())
                                    .appMinTapTarget()
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            if shareCardImage == nil {
                                shareCardImage = InviteShareCardRenderer.render(
                                    displayName: displayName,
                                    exclusiveID: exclusiveID,
                                    inviteCode: inviteCode,
                                    loadout: loadout,
                                    qrImage: qrImage
                                )
                            }
                            showShare = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(L10n.t("profile_share_card"))
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(FigmaTheme.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(FigmaTheme.primary, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 6)

                    VStack(spacing: 10) {
                        Text(L10n.t("profile_send_friend_request"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(FigmaTheme.text)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)

                        TextField(L10n.t("profile_friend_request_input"), text: $requestInput)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, weight: .medium))

                        Button {
                            Task { await sendFriendRequestFromInput() }
                        } label: {
                            HStack(spacing: 8) {
                                if sendingRequest {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(sendingRequest ? L10n.t("profile_sending") : L10n.t("profile_send_friend_request_button"))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(FigmaTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(sendingRequest)

                        Button {
                            showScannerSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(L10n.t("profile_scan_qr_code"))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(FigmaTheme.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(FigmaTheme.primary, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 4)
                }
                .padding(16)
            }
            .background(FigmaTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                UnifiedNavigationHeader(
                    chrome: NavigationChrome(
                        title: L10n.upper("profile_invite_friends"),
                        leadingAccessory: .back,
                        titleLevel: .secondary
                    ),
                    horizontalPadding: 16,
                    topPadding: 8,
                    bottomPadding: 12,
                    onLeadingTap: { dismiss() }
                ) {
                    Color.clear
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Text(copiedToast)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .task {
                if qrImage == nil {
                    qrImage = InviteQRCodeGenerator.generate(from: inviteDeepLink)
                }
                if shareCardImage == nil {
                    shareCardImage = InviteShareCardRenderer.render(
                        displayName: displayName,
                        exclusiveID: exclusiveID,
                        inviteCode: inviteCode,
                        loadout: loadout,
                        qrImage: qrImage
                    )
                }
            }
            .sheet(isPresented: $showShare) {
                if let card = shareCardImage {
                    ShareSheet(activityItems: [card])
                } else if let qr = qrImage {
                    ShareSheet(activityItems: [qr])
                } else {
                    ShareSheet(activityItems: [inviteCode])
                }
            }
            .sheet(isPresented: $showScannerSheet) {
                ProfileInviteScannerSheet { code in
                    requestInput = code
                    Task { await sendFriendRequestFromInput() }
                }
            }
            .alert(L10n.t("prompt"), isPresented: $showRequestMessage) {
                Button(L10n.t("got_it"), role: .cancel) {}
            } message: {
                Text(requestMessage)
            }
        }
    }

    private func copyText(_ text: String, success: String) {
        Haptics.light()
        UIPasteboard.general.string = text
        copiedToast = success
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showCopiedToast = false
            }
        }
    }

    @MainActor
    private func sendFriendRequestFromInput() async {
        guard !sendingRequest else { return }
        let raw = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            requestMessage = L10n.t("profile_friend_request_input_required")
            showRequestMessage = true
            return
        }
        sendingRequest = true
        defer { sendingRequest = false }

        let parsed = AppDeepLinkStore.parseInvite(from: raw)
        let inviteCode = parsed?.inviteCode
        let handle = parsed?.handle
        let directHandle: String? = {
            guard parsed == nil else { return nil }
            let v = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
            return v.isEmpty ? nil : v
        }()

        do {
            try await socialStore.addFriendSmart(
                displayName: "",
                inviteCode: inviteCode,
                handle: handle ?? directHandle,
                accessToken: sessionStore.currentAccessToken
            )
            requestMessage = L10n.t("profile_friend_request_sent")
            showRequestMessage = true
            requestInput = ""
        } catch {
            requestMessage = String(format: L10n.t("send_request_failed"), error.localizedDescription)
            showRequestMessage = true
        }
    }
}

private enum InviteQRCodeGenerator {
    static func generate(from text: String) -> UIImage? {
        let data = Data(text.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = output.transformed(by: transform)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private enum InviteShareCardRenderer {
    @MainActor
    static func render(
        displayName: String,
        exclusiveID: String,
        inviteCode: String,
        loadout: RobotLoadout,
        qrImage: UIImage?
    ) -> UIImage? {
        guard let qrImage else { return nil }
        let view = InviteShareCardView(
            displayName: displayName,
            exclusiveID: exclusiveID,
            inviteCode: inviteCode,
            loadout: loadout,
            qrImage: qrImage
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

private struct InviteShareCardView: View {
    let displayName: String
    let exclusiveID: String
    let inviteCode: String
    let loadout: RobotLoadout
    let qrImage: UIImage

    private var presentation: InviteFriendPresentation {
        InviteFriendPresentation(
            displayName: displayName,
            exclusiveID: exclusiveID,
            inviteCode: inviteCode
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.95, blue: 0.99), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(L10n.t("app_name"))
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(FigmaTheme.text)

                HStack(spacing: 10) {
                    RobotRendererView(size: 62, face: .front, loadout: loadout)
                        .frame(width: 62, height: 62)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.titleText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        if let visibleExclusiveIDText = presentation.visibleExclusiveIDText {
                            Text(visibleExclusiveIDText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(FigmaTheme.subtext)
                        }
                    }
                    Spacer()
                }

                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(presentation.codeText)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(FigmaTheme.text)
                    .tracking(1.8)

                Text(L10n.t("profile_open_app_to_scan"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .padding(24)
        }
        .frame(width: 680, height: 1020)
    }
}

private struct ProfileInviteScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScanned: (String) -> Void

    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var isImportingFromAlbum = false
    @State private var didResolveCode = false
    @State private var scannerError: String?
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ProfileInviteScannerRepresentable(
                    onDetected: { code in
                        completeScan(with: code)
                    },
                    onFailure: { message in
                        guard !didResolveCode else { return }
                        scannerError = message
                    }
                )
                .ignoresSafeArea()

                Text(L10n.t("profile_place_qr_in_frame"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                UnifiedNavigationHeader(
                    chrome: NavigationChrome(
                        title: L10n.t("profile_scan_qr_code"),
                        leadingAccessory: .back,
                        titleLevel: .secondary
                    ),
                    horizontalPadding: 16,
                    topPadding: 8,
                    bottomPadding: 12,
                    onLeadingTap: { dismiss() }
                ) {
                    Button {
                        guard !isImportingFromAlbum && !didResolveCode else { return }
                        showPhotoPicker = true
                    } label: {
                        Image(systemName: isImportingFromAlbum ? "hourglass" : "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                            .appMinTapTarget()
                    }
                    .buttonStyle(.plain)
                    .disabled(isImportingFromAlbum || didResolveCode)
                    .accessibilityLabel(
                        isImportingFromAlbum
                            ? L10n.t("friends_qr_importing")
                            : L10n.t("friends_qr_import_from_album")
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(L10n.t("profile_scan_failed"), isPresented: Binding(
                get: { scannerError != nil },
                set: { if !$0 { scannerError = nil } }
            )) {
                Button(L10n.t("got_it"), role: .cancel) {}
            } message: {
                Text(scannerError ?? "")
            }
            .onChange(of: pickedPhotoItem) { _, item in
                guard let item else { return }
                Task { await importQRCodeFromPhoto(item) }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhotoItem, matching: .images)
        }
    }

    @MainActor
    private func importQRCodeFromPhoto(_ item: PhotosPickerItem) async {
        guard !didResolveCode else { return }
        isImportingFromAlbum = true
        defer {
            isImportingFromAlbum = false
            pickedPhotoItem = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            scannerError = L10n.t("friends_qr_read_failed")
            return
        }

        guard let code = QRCodeImageDecoder.decode(image: image) else {
            scannerError = L10n.t("friends_qr_not_detected")
            return
        }

        completeScan(with: code)
    }

    @MainActor
    private func completeScan(with code: String) {
        guard !didResolveCode else { return }
        didResolveCode = true
        onScanned(code)
        dismiss()
    }
}

private struct ProfileInviteScannerRepresentable: UIViewControllerRepresentable {
    let onDetected: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> ProfileInviteScannerViewController {
        let vc = ProfileInviteScannerViewController()
        vc.onDetected = onDetected
        vc.onFailure = onFailure
        return vc
    }

    func updateUIViewController(_ uiViewController: ProfileInviteScannerViewController, context: Context) {}
}

private final class ProfileInviteScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetected: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCapture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureCapture() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onFailure?(L10n.t("profile_scan_camera_unsupported"))
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                onFailure?(L10n.t("profile_scan_camera_input_unavailable"))
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onFailure?(L10n.t("profile_scan_output_unavailable"))
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            previewLayer = preview
        } catch {
            onFailure?(L10n.t("profile_scan_camera_permission_unavailable"))
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didFinish else { return }
        guard let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = first.stringValue,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        didFinish = true
        session.stopRunning()
        onDetected?(code)
    }
}

private extension View {
    func figmaAvatarCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }

    func profileFeatureCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }

}

// MARK: - Profile Action Button

struct ProfileActionButton: View {
    let icon: String
    let title: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(FigmaTheme.primary)
                
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(FigmaTheme.mutedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .appFullSurfaceTapTarget(.roundedRect(20))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expandable Section

struct ExpandableSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(FigmaTheme.text)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.text.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .appFullSurfaceTapTarget(.rectangle)
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - Section Link Row (non-expandable)

struct SectionLinkRow: View {
    let title: String
//    let subtitle: String
  //  let value: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(FigmaTheme.text)

            }

            Spacer()

//            Text(value)
//                .font(.system(size: 16, weight: .bold))
//                .foregroundColor(FigmaTheme.text)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.35))
                .padding(.leading, 2)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .appFullSurfaceTapTarget(.rectangle)
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(UITheme.accent)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.5)
                .foregroundColor(FigmaTheme.text.opacity(0.5))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(FigmaTheme.text)
        }
    }
}

// MARK: - Stat Navigation Row

struct StatNavRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(UITheme.accent)
                .frame(width: 24)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .tracking(0.5)
                .foregroundColor(FigmaTheme.text.opacity(0.5))

            Spacer()

            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.35))
                .padding(.leading, 4)
        }
        .appFullSurfaceTapTarget(.rectangle)
    }
}

// MARK: - Recent Journeys

struct RecentJourneysView: View {
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @ObservedObject private var languagePreference = LanguagePreference.shared
    @Environment(\.dismiss) private var dismiss
    @State private var localizedCityNameByKey: [String: String] = [:]

    private var cutoffDate: Date {
        // "过去一个月"：这里按最近 30 天计算
        Date().addingTimeInterval(-30 * 24 * 60 * 60)
    }

    private var recentJourneys: [JourneyRoute] {
        store.journeys
            .filter { j in
                guard let start = j.startTime, let end = j.endTime else { return false }
                guard end >= cutoffDate else { return false }
                guard !j.isTooShort else { return false }
                return end >= start
            }
            .sorted { (a, b) in
                (a.endTime ?? .distantPast) > (b.endTime ?? .distantPast)
            }
    }

    var body: some View {
        ZStack(alignment: .top) {
            UITheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if recentJourneys.isEmpty {
                            emptyState
                        } else {
                            ForEach(recentJourneys, id: \.id) { j in
                                RecentJourneyCard(journey: j, cityName: resolvedDisplayCityName(for: j))
                                    .scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { content, phase in
                                        content
                                            .opacity(phase.isIdentity ? 1 : 0.3)
                                            .scaleEffect(phase.isIdentity ? 1 : 0.96)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationBarHidden(true)
        .task(id: cityLocalizationTaskKey) {
            await refreshCityLocalizations()
        }
    }

    private var cityLocalizationTaskKey: String {
        let lang = languagePreference.currentLanguage ?? "sys"
        let journeyPart = recentJourneys
            .map { "\($0.id)|\($0.startCityKey ?? $0.cityKey)" }
            .joined(separator: ",")
        return "\(lang)|\(journeyPart)"
    }

    private var cachedCitiesByKey: [String: CachedCity] {
        cityCache.cachedCitiesByKey
    }

    private func refreshCityLocalizations() async {
        await MainActor.run { localizedCityNameByKey = [:] }
        var coordByKey: [String: CLLocationCoordinate2D] = [:]
        for journey in recentJourneys {
            let key = journey.stableCityKey ?? ""
            guard !key.isEmpty, key != "Unknown|", coordByKey[key] == nil else { continue }
            if let start = journey.startCoordinate, start.isValid {
                coordByKey[key] = start
            }
        }

        for (key, coord) in coordByKey {
            let displayLocale = LanguagePreference.shared.displayLocale

            if let cachedCity = cachedCitiesByKey[key] {
                let title = cachedCity.displayTitle
                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run { localizedCityNameByKey[key] = title }
                    continue
                }
            }

            let parentRegionKey = cachedCitiesByKey[key]?.parentScopeKey

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
        let fallbackTitle = JourneyCityNamePresentation.title(
            for: journey,
            localizedCityNameByKey: localizedCityNameByKey,
            cachedCitiesByKey: cachedCitiesByKey
        )
        let cityKey = (journey.startCityKey ?? journey.cityKey).trimmingCharacters(in: .whitespacesAndNewlines)
        return CityDisplayResolver.title(
            for: cityKey,
            fallbackTitle: fallbackTitle
        )
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                AppBackButton(foreground: FigmaTheme.text.opacity(0.6))

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("recent_journeys_title"))
                    .navigationTitleStyle(level: .secondary)
                    .foregroundColor(FigmaTheme.text)

                Text(String(format: L10n.t("recent_journeys_last_30_days"), locale: Locale.current, recentJourneys.count))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(FigmaTheme.text.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 10)
        }
        .background(UITheme.bg)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(L10n.key("recent_journeys_empty_title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.6))

            Text(L10n.key("recent_journeys_empty_desc"))
                .font(.system(size: 12))
                .foregroundColor(FigmaTheme.text.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 18)
    }
}

struct RecentJourneyCard: View {
    var journey: JourneyRoute
    var cityName: String

    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var store: JourneyStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @State private var image: UIImage? = nil
    @State private var isGenerating = false
    @State private var showSaveToast = false
    @State private var saveToastText = L10n.t("share_saved_to_photos")
    @State private var imageSaver: ImageSaver? = nil
    @State private var activeJourneyDetail: JourneyMemoryDetailDestination? = nil

    private var durationText: String {
        guard let start = journey.startTime else {
            return String(format: L10n.t("share_duration_min"), locale: Locale.current, 0)
        }
        let end = journey.endTime ?? Date()
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return String(format: L10n.t("share_duration_min"), locale: Locale.current, minutes)
    }

    private var dateText: String {
        guard let end = journey.endTime else { return "" }
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: end)
    }

    private var localizedCountryName: String {
        let iso = (journey.countryISO2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard iso.count == 2 else {
            return L10n.t("unknown_country")
        }
        return LanguagePreference.shared.displayLocale.localizedString(forRegionCode: iso) ?? iso
    }

    private var detailButtonText: String {
        L10n.t("view_journey_memories")
    }

    private var cachedCitiesByKey: [String: CachedCity] {
        cityCache.cachedCitiesByKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) {
                            saveToPhotos(img)
                        }
                        .contextMenu {
                            Button {
                                saveToPhotos(img)
                            } label: {
                                Label(L10n.t("save_image"), systemImage: "square.and.arrow.down")
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 320)
                        .overlay(
                            VStack(spacing: 10) {
                                ProgressView()
                                Text(L10n.key("share_generating"))
                                    .font(.system(size: 12))
                                    .foregroundColor(FigmaTheme.text.opacity(0.45))
                            }
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .top) {
                if showSaveToast {
                    Text(saveToastText)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(FigmaTheme.text.opacity(0.75))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(cityName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Text(dateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.text.opacity(0.5))

                HStack(spacing: 10) {
                    Text(String(format: "%.2f km", max(0, journey.distance / 1000.0)))
                    Text("·")
                    Text(durationText)
                    Text("·")
                    Text(String(format: L10n.t("mem_short"), locale: Locale.current, journey.memories.count))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FigmaTheme.text.opacity(0.45))
            }
            .padding(.horizontal, 2)

            Button {
                activeJourneyDetail = JourneyMemoryDetailDestination(
                    journey: journey,
                    memories: journey.memories.sorted(by: { $0.timestamp < $1.timestamp }),
                    cityName: cityName,
                    countryName: localizedCountryName,
                    readOnly: false,
                    friendLoadout: nil
                )
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 12, weight: .semibold))
                    Text(detailButtonText)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(FigmaTheme.text.opacity(0.78))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(18)
        .fullScreenCover(item: $activeJourneyDetail) { destination in
            JourneyMemoryDetailView(
                journey: destination.journey,
                memories: destination.memories,
                cityName: destination.cityName,
                countryName: destination.countryName,
                readOnly: destination.readOnly,
                friendLoadout: destination.friendLoadout
            )
            .environmentObject(store)
            .environmentObject(sessionStore)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            generateIfNeeded()
        }
    }

    private func generateIfNeeded() {
        guard image == nil, !isGenerating else { return }

        // too short / empty journey -> show placeholder card
        if journey.coordinates.count < 1 || journey.isTooShort {
            image = ShareCardGenerator.placeholderCard()
            return
        }

        isGenerating = true
        ShareCardGenerator.generate(
            journey: journey,
            cachedCitiesByKey: cachedCitiesByKey,
            privacy: .exact
        ) { img in
            self.image = img
            self.isGenerating = false
        }
    }

    private func saveToPhotos(_ img: UIImage) {
        Haptics.light()

        // Hold a strong reference until completion callback
        let saver = ImageSaver { err in
            DispatchQueue.main.async {
                self.imageSaver = nil
                self.saveToastText = (err == nil) ? L10n.t("share_saved_to_photos") : L10n.t("save_failed")
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    self.showSaveToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        self.showSaveToast = false
                    }
                }
            }
        }
        self.imageSaver = saver
        saver.writeToPhotoAlbum(img)
    }
}

private struct DeferredView<Content: View>: View {
    let content: () -> Content
    var body: some View { content() }
}

final class ImageSaver: NSObject {
    private let onComplete: (Error?) -> Void

    init(onComplete: @escaping (Error?) -> Void) {
        self.onComplete = onComplete
        super.init()
    }

    func writeToPhotoAlbum(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        onComplete(error)
    }
}

// MARK: - Equipment Library View (Updated)

struct EquipmentLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    
    let equipmentItems: [EquipmentItem] = [
        EquipmentItem(id: "worldmap", name: L10n.t("equipment_world_map"), icon: "map", rarity: .common, isCollected: true),
        EquipmentItem(id: "camera", name: L10n.t("equipment_camera"), icon: "camera", rarity: .common, isCollected: true),
        EquipmentItem(id: "backpack", name: L10n.t("equipment_leather_backpack"), icon: "backpack", rarity: .rare, isCollected: false),
        EquipmentItem(id: "boots", name: L10n.t("equipment_hiking_boots"), icon: "figure.walk", rarity: .rare, isCollected: false)
    ]
    
    var collectedCount: Int {
        equipmentItems.filter { $0.isCollected }.count
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            UITheme.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                ZStack {
                    Text(L10n.t("equipment_title_upper"))
                        .font(.system(size: 26, weight: .bold))
                        .tracking(1)
                        .foregroundColor(FigmaTheme.text)

                    HStack {
                        AppBackButton(foreground: FigmaTheme.text.opacity(0.6))

                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Text(String(format: L10n.t("equipment_collected_count"), locale: Locale.current, collectedCount, equipmentItems.count))
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1)
                    .foregroundColor(FigmaTheme.text.opacity(0.5))
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                
                // Equipment grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(equipmentItems) { item in
                            EquipmentCard(item: item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 360)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Equipment Item Model

struct EquipmentItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let rarity: EquipmentRarity
    let isCollected: Bool
}

enum EquipmentRarity {
    case common
    case rare
    
    var label: String {
        switch self {
        case .common: return L10n.t("rarity_common")
        case .rare: return L10n.t("rarity_rare")
        }
    }
    
    var color: Color {
        switch self {
        case .common: return UITheme.rarityCommon
        case .rare: return UITheme.rarityRare
        }
    }
}

// MARK: - Equipment Card

struct EquipmentCard: View {
    let item: EquipmentItem
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.isCollected ? Color.white : Color.black.opacity(0.05))
                    .frame(height: 62)
                
                if item.isCollected {
                    Image(systemName: item.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.7))
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(FigmaTheme.text.opacity(0.3))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(item.isCollected ? Color.black.opacity(0.1) : Color.clear, lineWidth: 1)
            )
            
            // Name and rarity
            VStack(spacing: 4) {
                Text(item.name)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.3)
                    .foregroundColor(item.isCollected ? .black : .black.opacity(0.4))
                    .lineLimit(1)
                
                Text(item.rarity.label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(item.isCollected ? item.rarity.color : .black.opacity(0.3))
            }
        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(item.rarity == .rare && item.isCollected ? UITheme.accent.opacity(0.3) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
