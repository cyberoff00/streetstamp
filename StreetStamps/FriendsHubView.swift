import SwiftUI
import UIKit
import MapKit
import AVFoundation
import PhotosUI

private enum FriendsTopTab: String, CaseIterable, Identifiable {
    case activity
    case allFriends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return L10n.t("friends_tab_activity")
        case .allFriends: return L10n.t("friends_tab_all")
        }
    }
}

private enum AddFriendMethod: String, CaseIterable, Identifiable {
    case inviteCode
    case exclusiveID
    case qrToken

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inviteCode: return "邀请码"
        case .exclusiveID: return "专属ID"
        case .qrToken: return "二维码"
        }
    }
}

private enum FriendsRoute: Hashable, Identifiable {
    case profile(String)
    case journeys(String)
    case cities(String)
    case equipment(String)
    case publicMemories(String)
    case journey(friendID: String, journeyID: String)

    var id: String {
        switch self {
        case .profile(let friendID):
            return "profile_\(friendID)"
        case .journeys(let friendID):
            return "journeys_\(friendID)"
        case .cities(let friendID):
            return "cities_\(friendID)"
        case .equipment(let friendID):
            return "equipment_\(friendID)"
        case .publicMemories(let friendID):
            return "public_memories_\(friendID)"
        case .journey(let friendID, let journeyID):
            return "journey_\(friendID)_\(journeyID)"
        }
    }
}

enum FriendFeedKind {
    case journey
    case memory
    case city
}

enum FriendFeedLogic {
    static let minDistanceMeters: Double = 2_000

    static func isJourneyEligible(_ journey: FriendSharedJourney) -> Bool {
        let isVisible = journey.visibility == .public || journey.visibility == .friendsOnly
        guard isVisible else { return false }
        return journey.distance >= minDistanceMeters || !journey.memories.isEmpty
    }

    static func eventTitle(
        kind: FriendFeedKind,
        cityName: String,
        memoryCount: Int,
        journeyTitle: String,
        localize: (String) -> String = { L10n.t($0) }
    ) -> String {
        switch kind {
        case .city:
            return String(format: localize("friends_event_visited"), cityName.isEmpty ? localize("unknown_city") : cityName)
        case .memory:
            return String(format: localize("friends_event_added_memories"), memoryCount)
        case .journey:
            return localize("friends_event_completed_journey")
        }
    }
}

private struct FriendFeedEvent: Identifiable {
    let id: String
    let kind: FriendFeedKind
    let friendID: String
    let timestamp: Date
    let journeyID: String?
    let title: String
    let location: String
    let meta: String
}

struct FriendsHubView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var deepLinkStore: AppDeepLinkStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @EnvironmentObject private var journeyStore: JourneyStore
    @AppStorage("streetstamps.profile.displayName") private var profileName = "EXPLORER"

    @State private var tab: FriendsTopTab = .activity
    @State private var showAddFriendSheet = false
    @State private var loadingRemote = false
    @State private var activeRoute: FriendsRoute?
    @State private var toastText = ""
    @State private var showToast = false
    @State private var feedLikeStats: [String: (likes: Int, likedByMe: Bool)] = [:]
    @State private var feedLikeLoadingKeys: Set<String> = []
    @State private var socialNotifications: [BackendNotificationItem] = []
    @State private var unreadSocialCount = 0
    @State private var showSocialNotificationsSheet = false
    @State private var notificationsLoading = false
    @State private var lastPromptNotificationID: String?
    @State private var incomingFriendRequests: [BackendFriendRequestDTO] = []
    @State private var outgoingFriendRequests: [BackendFriendRequestDTO] = []
    @State private var requestActionLoadingIDs: Set<String> = []
    @State private var addFriendPrefillInviteCode: String?
    @State private var addFriendPrefillHandle: String?
    @State private var showInviteFriendSheet = false
    @State private var showPostcardInboxSheet = false
    @State private var postcardInboxIntent = PostcardInboxIntent(box: "received", messageID: nil)
    @State private var myExclusiveID = ""
    @State private var myInviteCode = ""
    @State private var myRemoteProfile: BackendProfileDTO?
    @State private var showAuthEntry = false

    private var sortedFriends: [FriendProfileSnapshot] {
        socialStore.friends.sorted { lhs, rhs in
            lastActiveDate(of: lhs) > lastActiveDate(of: rhs)
        }
    }

    private func lastActiveDate(of friend: FriendProfileSnapshot) -> Date {
        FriendListPresencePresentation.recentJourneyDate(for: friend) ?? friend.createdAt
    }

    private var currentUserID: String {
        sessionStore.accountUserID ?? sessionStore.currentUserID
    }

    private var selfSnapshotForFeed: FriendProfileSnapshot? {
        let uid = currentUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return nil }
        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackInvite = SocialGraphStore.generateInviteCode(source: uid)
        let invite = myInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let handle = myExclusiveID.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackHandle = SocialGraphStore.generateInviteCode(source: name).lowercased()
        return FriendsSelfProfileBuilder.makeSnapshot(
            remoteProfile: myRemoteProfile,
            fallbackUserID: uid,
            fallbackDisplayName: name.isEmpty ? L10n.t("explorer_fallback") : name,
            fallbackExclusiveID: handle.isEmpty ? fallbackHandle : handle,
            fallbackInviteCode: invite.isEmpty ? fallbackInvite : invite,
            fallbackLoadout: AvatarLoadoutStore.load()
        )
    }

    private var feedSourceProfiles: [FriendProfileSnapshot] {
        if let me = selfSnapshotForFeed {
            return [me] + sortedFriends.filter { $0.id != currentUserID }
        }
        return sortedFriends
    }

    private var feedProfileByID: [String: FriendProfileSnapshot] {
        Dictionary(feedSourceProfiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var feedEvents: [FriendFeedEvent] {
        buildFeedEvents(from: feedSourceProfiles)
    }

    private var feedLikeSignature: String {
        feedEvents
            .compactMap { event -> String? in
                guard let journeyID = event.journeyID else { return nil }
                guard event.friendID != currentUserID else { return nil }
                return feedLikeKey(friendID: event.friendID, journeyID: journeyID)
            }
            .sorted()
            .joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if sessionStore.isLoggedIn {
                tabSwitcher

                Divider().overlay(Color.black.opacity(0.06))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if tab == .activity {
                            if feedEvents.isEmpty {
                                emptyState(L10n.t("friends_empty_activity"))
                            } else {
                                ForEach(feedEvents) { event in
                                    if let friend = feedProfileByID[event.friendID] {
                                        FriendActivityCard(
                                            friend: friend,
                                            event: event,
                                            likeCount: likeCountForEvent(event),
                                            likedByMe: likedByMeForEvent(event),
                                            likeLoading: likeLoadingForEvent(event),
                                            canLike: event.friendID != currentUserID,
                                            onToggleLike: {
                                                guard let journeyID = event.journeyID else { return }
                                                Task {
                                                    await toggleFeedLike(friendID: friend.id, journeyID: journeyID)
                                                }
                                            },
                                            onOpenProfile: {
                                                ensureSelfSnapshotInSocialStoreIfNeeded(friendID: friend.id)
                                                activeRoute = .profile(friend.id)
                                            },
                                            onOpenEvent: {
                                                ensureSelfSnapshotInSocialStoreIfNeeded(friendID: friend.id)
                                                if let jid = event.journeyID {
                                                    activeRoute = .journey(friendID: friend.id, journeyID: jid)
                                                } else {
                                                    activeRoute = .profile(friend.id)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        } else {
                            if !incomingFriendRequests.isEmpty {
                                friendRequestSectionTitle("待你通过")
                                ForEach(incomingFriendRequests) { req in
                                    friendRequestCard(request: req, isIncoming: true)
                                }
                            }

                            if sortedFriends.isEmpty {
                                if incomingFriendRequests.isEmpty {
                                    emptyState(L10n.t("friends_empty_all"))
                                }
                            } else {
                                friendRequestSectionTitle("我的好友")
                                ForEach(sortedFriends) { friend in
                                    Button {
                                        activeRoute = .profile(friend.id)
                                    } label: {
                                        AllFriendsCard(
                                            friend: friend,
                                            subtitleText: FriendListPresencePresentation.subtitle(for: friend)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 54)
                }
                .refreshable {
                    await refreshRemoteFriends()
                }
                .background(FigmaTheme.background)
            } else {
                loggedOutState
            }
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .navigationDestination(item: $activeRoute) { route in
            destination(for: route)
        }
        .sheet(isPresented: $showAddFriendSheet) {
            AddFriendSheet(
                prefillInviteCode: addFriendPrefillInviteCode,
                prefillHandle: addFriendPrefillHandle
            ) {
                await refreshRemoteFriends()
            }
            .environmentObject(socialStore)
            .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showInviteFriendSheet) {
            InviteFriendSheet(
                displayName: resolvedDisplayNameForInvite(),
                loadout: AvatarLoadoutStore.load().normalizedForCurrentAvatar(),
                exclusiveID: resolvedExclusiveIDForInvite(),
                inviteCode: resolvedInviteCodeForInvite()
            )
            .environmentObject(socialStore)
            .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showSocialNotificationsSheet) {
            socialNotificationsSheet
        }
        .sheet(isPresented: $showPostcardInboxSheet) {
            let initialBox: PostcardInboxView.Box = postcardInboxIntent.box == "sent" ? .sent : .received
            NavigationStack {
                PostcardInboxView(
                    initialBox: initialBox,
                    focusMessageID: postcardInboxIntent.messageID
                )
                .id(PostcardInboxView.viewIdentity(initialBox: initialBox, focusMessageID: postcardInboxIntent.messageID))
            }
        }
        .fullScreenCover(isPresented: $showAuthEntry) {
            AuthEntryView(
                onContinueGuest: { showAuthEntry = false },
                onAuthenticated: { showAuthEntry = false }
            )
            .environmentObject(sessionStore)
        }
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
        .task {
            await refreshRemoteFriends()
            await refreshMyInviteIdentityIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
                await refreshRemoteFriends()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshRemoteFriends()
            }
        }
        .onChange(of: sessionStore.currentAccessToken) { _, _ in
            Task {
                await refreshSocialNotifications(showToastForLatestUnread: false)
                await refreshFriendRequests()
                await refreshMyInviteIdentityIfNeeded()
            }
        }
        .task(id: feedLikeSignature) {
            await loadFeedLikeStatsIfNeeded()
        }
        .onReceive(deepLinkStore.$pendingFriendInvite) { invite in
            guard let invite else { return }
            tab = .allFriends
            addFriendPrefillInviteCode = invite.inviteCode
            addFriendPrefillHandle = invite.handle
            showAddFriendSheet = true
            deepLinkStore.consumePendingFriendInvite()
        }
        .onReceive(deepLinkStore.$pendingPostcardInbox) { intent in
            guard let intent else { return }
            postcardInboxIntent = intent
            showPostcardInboxSheet = true
            deepLinkStore.consumePendingPostcardInbox()
        }
        .onReceive(NotificationCenter.default.publisher(for: .postcardSentGoToInbox)) { _ in
            postcardInboxIntent = PostcardInboxIntent(box: "sent", messageID: nil)
            showPostcardInboxSheet = true
        }
    }

    private var loggedOutState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 48)

            VStack(spacing: 12) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)

                Text(L10n.t("friends_logged_out_title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(FigmaTheme.text)

                Text(L10n.t("friends_logged_out_message"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)

            Button {
                showAuthEntry = true
            } label: {
                Text(L10n.t("friends_go_login"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FigmaTheme.background)
    }

    @ViewBuilder
    private func destination(for route: FriendsRoute) -> some View {
        switch route {
        case .profile(let friendID):
            FriendProfileScreen(friendID: friendID)
        case .journeys(let friendID):
            FriendJourneysScreen(friendID: friendID)
        case .cities(let friendID):
            FriendCitiesScreen(friendID: friendID)
        case .equipment(let friendID):
            FriendEquipmentScreen(friendID: friendID)
        case .publicMemories(let friendID):
            FriendPublicMemoriesScreen(friendID: friendID)
        case .journey(let friendID, let journeyID):
            FriendJourneyRouteScreen(friendID: friendID, journeyID: journeyID)
        }
    }

    private var header: some View {
        UnifiedTabPageHeader(title: L10n.t("friends_title"), titleLevel: .primary, horizontalPadding: 16, topPadding: 14, bottomPadding: 12) {
            Color.clear
        } trailing: {
            if !sessionStore.isLoggedIn {
                Button {
                    showAuthEntry = true
                } label: {
                    Text(L10n.t("friends_go_login"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                }
                .buttonStyle(.plain)
            } else if tab == .allFriends {
                Button {
                    showInviteFriendSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showSocialNotificationsSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(FigmaTheme.text)

                        if unreadSocialCount > 0 {
                            Text("\(min(unreadSocialCount, 99))")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 10, y: -8)
                        }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var tabSwitcher: some View {
        HStack {
            Picker("Friends", selection: $tab) {
                ForEach(FriendsTopTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func friendRequestSectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(FigmaTheme.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func friendRequestCard(request: BackendFriendRequestDTO, isIncoming: Bool) -> some View {
        let profile = isIncoming ? request.fromUser : request.toUser
        let loading = requestActionLoadingIDs.contains(request.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RobotRendererView(size: 36, face: .front, loadout: (profile.loadout ?? .defaultBoy).normalizedForCurrentAvatar())
                    .frame(width: 56, height: 56)
                    .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    let handleText: String = {
                        let raw = profile.handle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if raw.isEmpty { return L10n.t("unknown_id") }
                        return "@\(raw)"
                    }()
                    Text(profile.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                    Text(String(format: L10n.t("friends_exclusive_id_format"), handleText))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                    Text(FriendListPresencePresentation.shortAgoText(from: request.createdAt, now: Date(), localize: L10n.t))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext.opacity(0.8))
                }
                Spacer(minLength: 8)
            }

            if isIncoming {
                HStack(spacing: 10) {
                    Button(loading ? L10n.t("profile_sending") : L10n.t("friends_accept")) {
                        Task { await acceptFriendRequest(request.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading)

                    Button(L10n.t("friends_ignore")) {
                        Task { await rejectFriendRequest(request.id) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(loading)
                }
            } else {
                Text(L10n.t("friends_waiting_approval"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FigmaTheme.subtext)
            }
        }
        .padding(16)
        .figmaSurfaceCard(radius: 24)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 28)
    }

    private func resolvedDisplayNameForInvite() -> String {
        let value = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("explorer_fallback") : value
    }

    private func resolvedExclusiveIDForInvite() -> String {
        let id = myExclusiveID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return id }
        let source = sessionStore.accountUserID ?? sessionStore.currentUserID
        return SocialGraphStore.generateInviteCode(source: source)
    }

    private func resolvedInviteCodeForInvite() -> String {
        let code = myInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !code.isEmpty { return code }
        let source = sessionStore.accountUserID ?? resolvedExclusiveIDForInvite()
        return SocialGraphStore.generateInviteCode(source: source)
    }

    private func buildFeedEvents(from friends: [FriendProfileSnapshot]) -> [FriendFeedEvent] {
        var events: [FriendFeedEvent] = []

        for friend in friends {
            let visibleJourneys = friend.journeys
                .filter { FriendFeedLogic.isJourneyEligible($0) }
                .sorted {
                    feedTimestamp(for: $0) > feedTimestamp(for: $1)
                }

            guard !visibleJourneys.isEmpty else { continue }

            let firstJourneyByCity: [String: String] = {
                var map: [String: String] = [:]
                let ascending = visibleJourneys.sorted {
                    feedTimestamp(for: $0) < feedTimestamp(for: $1)
                }
                for journey in ascending {
                    let cityKey = resolvedFriendCityID(for: journey, cards: friend.unlockedCityCards)
                    guard !cityKey.isEmpty, map[cityKey] == nil else { continue }
                    map[cityKey] = journey.id
                }
                return map
            }()

            for journey in visibleJourneys.prefix(12) {
                let eventDate = feedTimestamp(for: journey)
                let cityKey = resolvedFriendCityID(for: journey, cards: friend.unlockedCityCards)
                let cityName = resolvedFriendCityTitle(for: journey, cards: friend.unlockedCityCards)
                let memoryCount = journey.memories.count
                let photoCount = journey.memories.reduce(0) { $0 + $1.imageURLs.count }
                let unlockedNewCity = !cityKey.isEmpty && firstJourneyByCity[cityKey] == journey.id

                let kind: FriendFeedKind
                if unlockedNewCity {
                    kind = .city
                } else if memoryCount > 0 {
                    kind = .memory
                } else {
                    kind = .journey
                }

                let eventTitle = FriendFeedLogic.eventTitle(
                    kind: kind,
                    cityName: cityName,
                    memoryCount: memoryCount,
                    journeyTitle: journey.title
                )
                let metaText: String
                switch kind {
                case .city:
                    metaText = ""
                case .memory:
                    metaText = String(format: L10n.t("friends_photos_count_format"), max(photoCount, memoryCount))
                case .journey:
                    metaText = "\(formatDistance(journey.distance))  \(formatDuration(start: journey.startTime, end: journey.endTime))"
                }

                events.append(
                    FriendFeedEvent(
                        id: "feed_\(friend.id)_\(journey.id)",
                        kind: kind,
                        friendID: friend.id,
                        timestamp: eventDate,
                        journeyID: journey.id,
                        title: eventTitle,
                        location: cityName,
                        meta: metaText
                    )
                )
            }
        }

        return events
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(60)
            .map { $0 }
    }

    private func feedTimestamp(for journey: FriendSharedJourney) -> Date {
        let memoryDate = journey.memories.map(\.timestamp).max() ?? .distantPast
        return max(memoryDate, journey.endTime ?? journey.startTime ?? .distantPast)
    }

    private func resolvedFriendCityID(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        FriendJourneyCityIdentity.resolveCityID(for: journey, cards: cards)
    }

    private func resolvedFriendCityTitle(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        let cityID = resolvedFriendCityID(for: journey, cards: cards)
        let cityCard = cards.first(where: { $0.id == cityID })
        return CityDisplayTitlePresentation.title(
            cityKey: cityCard?.id ?? cityID,
            iso2: cityCard?.countryISO2,
            fallbackTitle: cityCard?.name ?? journey.title
        )
    }

    private func formatDistance(_ meters: Double) -> String {
        String(format: L10n.t("friends_distance_compact_format"), meters / 1000.0)
    }

    private func formatDuration(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "--" }
        let sec = max(0, Int(end.timeIntervalSince(start)))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        return "\(h)h \(m)m"
    }

    private func feedLikeKey(friendID: String, journeyID: String) -> String {
        "\(friendID)|\(journeyID)"
    }

    /// When tapping on own post in the feed, ensure the self-snapshot is available
    /// in socialStore so that FriendProfileScreen / FriendJourneyRouteScreen can find it.
    private func ensureSelfSnapshotInSocialStoreIfNeeded(friendID: String) {
        let target = friendID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target == currentUserID else { return }
        if let snapshot = selfSnapshotForFeed {
            socialStore.importFriendSnapshot(snapshot)
        }
    }

    private func likeCountForEvent(_ event: FriendFeedEvent) -> Int {
        guard let journeyID = event.journeyID else { return 0 }
        return feedLikeStats[feedLikeKey(friendID: event.friendID, journeyID: journeyID)]?.likes ?? 0
    }

    private func likedByMeForEvent(_ event: FriendFeedEvent) -> Bool {
        guard let journeyID = event.journeyID else { return false }
        return feedLikeStats[feedLikeKey(friendID: event.friendID, journeyID: journeyID)]?.likedByMe ?? false
    }

    private func likeLoadingForEvent(_ event: FriendFeedEvent) -> Bool {
        guard let journeyID = event.journeyID else { return false }
        return feedLikeLoadingKeys.contains(feedLikeKey(friendID: event.friendID, journeyID: journeyID))
    }

    @MainActor
    private func loadFeedLikeStatsIfNeeded() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            feedLikeStats = [:]
            return
        }

        let pairs = feedEvents.compactMap { event -> (friendID: String, journeyID: String)? in
            guard let journeyID = event.journeyID else { return nil }
            guard event.friendID != currentUserID else { return nil }
            return (event.friendID, journeyID)
        }
        guard !pairs.isEmpty else {
            feedLikeStats = [:]
            return
        }

        let grouped = Dictionary(grouping: pairs, by: \.friendID)
        var next: [String: (likes: Int, likedByMe: Bool)] = [:]
        do {
            for (friendID, items) in grouped {
                let ids = Array(Set(items.map(\.journeyID)))
                let stats = try await BackendAPIClient.shared.fetchJourneyLikeStats(
                    token: token,
                    journeyIDs: ids,
                    ownerUserID: friendID
                )
                for (journeyID, value) in stats {
                    next[feedLikeKey(friendID: friendID, journeyID: journeyID)] = value
                }
            }
            feedLikeStats = next
        } catch {
            // Keep feed available even if like stats request fails.
        }
    }

    @MainActor
    private func toggleFeedLike(friendID: String, journeyID: String) async {
        guard BackendConfig.isEnabled else {
            showFeedToast(L10n.t("friends_backend_not_configured"), duration: 2.0)
            return
        }
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else {
            showFeedToast(L10n.t("please_sign_in_to_access_your_account"), duration: 2.0)
            return
        }

        let key = feedLikeKey(friendID: friendID, journeyID: journeyID)
        guard !feedLikeLoadingKeys.contains(key) else { return }

        let current = feedLikeStats[key] ?? (likes: 0, likedByMe: false)
        let liked = current.likedByMe

        feedLikeStats[key] = (likes: liked ? max(0, current.likes - 1) : current.likes + 1, likedByMe: !liked)

        feedLikeLoadingKeys.insert(key)
        defer { feedLikeLoadingKeys.remove(key) }

        do {
            let resp: JourneyLikeActionResponse
            if liked {
                resp = try await BackendAPIClient.shared.unlikeJourney(token: token, ownerUserID: friendID, journeyID: journeyID)
            } else {
                resp = try await BackendAPIClient.shared.likeJourney(token: token, ownerUserID: friendID, journeyID: journeyID)
            }
            feedLikeStats[key] = (likes: max(0, resp.likes), likedByMe: resp.likedByMe)
        } catch {
            feedLikeStats[key] = current
            showFeedToast(L10n.t("operation_failed"))
        }
    }

    @MainActor
    private func refreshRemoteFriends() async {
        guard !loadingRemote else { return }
        loadingRemote = true
        defer { loadingRemote = false }

        let previousFriends = socialStore.friends
        await socialStore.reloadFromBackendIfPossible(accessToken: sessionStore.currentAccessToken)

        if socialStore.friends.isEmpty && !previousFriends.isEmpty {
            socialStore.friends = previousFriends
        }

        await refreshSocialNotifications(showToastForLatestUnread: true)
        await refreshFriendRequests()
    }

    @MainActor
    private func refreshSocialNotifications(showToastForLatestUnread: Bool) async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            socialNotifications = []
            unreadSocialCount = 0
            return
        }
        notificationsLoading = true
        defer { notificationsLoading = false }

        do {
            let all = try await BackendAPIClient.shared.fetchNotifications(token: token, unreadOnly: false)
            PostcardNotificationBridge.shared.surfaceUnreadPostcardNotifications(all)
            let cutoff = Date().addingTimeInterval(-3 * 24 * 60 * 60)
            let fetched = all
                .filter({ SocialNotificationPolicy.supports(type: $0.type) })
                .filter({ $0.createdAt >= cutoff })
                .sorted(by: { $0.createdAt > $1.createdAt })
            var mergedByID: [String: BackendNotificationItem] = [:]
            for item in socialNotifications where item.createdAt >= cutoff {
                mergedByID[item.id] = item
            }
            for item in fetched {
                mergedByID[item.id] = item
            }
            let socialItems = mergedByID.values
                .filter { $0.createdAt >= cutoff }
                .sorted(by: { $0.createdAt > $1.createdAt })
            socialNotifications = socialItems

            let unread = socialItems.filter { !$0.read }
            unreadSocialCount = unread.count

            if showToastForLatestUnread,
               let latest = unread.first,
               latest.id != lastPromptNotificationID {
                showFeedToast(SocialNotificationPresentation.message(for: latest), duration: 2.2)
                lastPromptNotificationID = latest.id
            }
        } catch {
            // Keep social feed resilient even if reminder endpoint fails.
        }
    }

    @MainActor
    private func refreshMyInviteIdentityIfNeeded() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            myRemoteProfile = nil
            return
        }
        do {
            let me = try await BackendAPIClient.shared.fetchMyProfile(token: token)
            myRemoteProfile = me
            if let id = me.resolvedExclusiveID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !id.isEmpty {
                myExclusiveID = id
            }
            if let code = me.inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines),
               !code.isEmpty {
                myInviteCode = code.uppercased()
            } else {
                myInviteCode = SocialGraphStore.generateInviteCode(source: me.id)
            }
        } catch {
            myRemoteProfile = nil
            // Keep invite entry available with local fallback.
        }
    }

    @MainActor
    private func refreshFriendRequests() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            incomingFriendRequests = []
            outgoingFriendRequests = []
            return
        }

        do {
            let resp = try await BackendAPIClient.shared.fetchFriendRequests(token: token)
            incomingFriendRequests = resp.incoming
            outgoingFriendRequests = resp.outgoing
        } catch {
            // Keep friends page available even if request endpoint fails.
        }
    }

    @MainActor
    private func acceptFriendRequest(_ requestID: String) async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            showFeedToast(L10n.t("please_sign_in_to_access_your_account"), duration: 2.0)
            return
        }
        guard !requestActionLoadingIDs.contains(requestID) else { return }
        requestActionLoadingIDs.insert(requestID)
        defer { requestActionLoadingIDs.remove(requestID) }

        do {
            let resp = try await BackendAPIClient.shared.acceptFriendRequest(token: token, requestID: requestID)
            await refreshRemoteFriends()
            showFeedToast(resp.message ?? L10n.t("friends_request_accepted"))
        } catch {
            showFeedToast(String(format: L10n.t("friends_accept_failed_format"), error.localizedDescription))
        }
    }

    @MainActor
    private func rejectFriendRequest(_ requestID: String) async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            showFeedToast(L10n.t("please_sign_in_to_access_your_account"), duration: 2.0)
            return
        }
        guard !requestActionLoadingIDs.contains(requestID) else { return }
        requestActionLoadingIDs.insert(requestID)
        defer { requestActionLoadingIDs.remove(requestID) }

        do {
            let resp = try await BackendAPIClient.shared.rejectFriendRequest(token: token, requestID: requestID)
            await refreshFriendRequests()
            showFeedToast(resp.message ?? L10n.t("friends_request_rejected"))
        } catch {
            showFeedToast(String(format: L10n.t("friends_reject_failed_format"), error.localizedDescription))
        }
    }

    @MainActor
    private func markSocialNotificationsRead(ids: [String]) async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else { return }
        let targetIDs = Array(Set(ids))
        guard !targetIDs.isEmpty else { return }

        do {
            try await BackendAPIClient.shared.markNotificationsRead(token: token, ids: targetIDs)
            socialNotifications = socialNotifications.map { item in
                guard targetIDs.contains(item.id) else { return item }
                var copy = item
                copy.read = true
                return copy
            }
            unreadSocialCount = socialNotifications.filter { !$0.read }.count
        } catch {
            // Keep feed page responsive even if read-mark fails.
        }
    }

    @MainActor
    private func markSingleSocialNotificationRead(_ id: String) async {
        guard let item = socialNotifications.first(where: { $0.id == id }), !item.read else { return }
        await markSocialNotificationsRead(ids: [id])
    }

    @MainActor
    private func markAllSocialNotificationsRead() async {
        let unreadIDs = socialNotifications.filter { !$0.read }.map(\.id)
        await markSocialNotificationsRead(ids: unreadIDs)
    }

    @ViewBuilder
    private var socialNotificationsSheet: some View {
        NavigationStack {
            Group {
                if notificationsLoading && socialNotifications.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.t("profile_notifications_loading"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if socialNotifications.isEmpty {
                    Text(L10n.t("profile_notifications_empty"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(socialNotifications) { item in
                                socialNotificationRow(item)
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
                    onLeadingTap: { showSocialNotificationsSheet = false }
                ) {
                    Button {
                        Task {
                            await markAllSocialNotificationsRead()
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("friends_mark_all_read"))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await refreshSocialNotifications(showToastForLatestUnread: false)
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
            Task {
                await markSingleSocialNotificationRead(item.id)
                if item.type == "postcard_received" {
                    postcardInboxIntent = PostcardInboxIntent(box: "received", messageID: item.postcardMessageID)
                    showPostcardInboxSheet = true
                } else if let fromUserID = item.fromUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !fromUserID.isEmpty {
                    showSocialNotificationsSheet = false
                    activeRoute = .profile(fromUserID)
                }
            }
        }
    }

    private func relativeTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @MainActor
    private func showFeedToast(_ text: String, duration: Double = 2.2) {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return }
        toastText = compact
        withAnimation(.easeInOut(duration: 0.2)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
}

private struct FriendActivityCard: View {
    let friend: FriendProfileSnapshot
    let event: FriendFeedEvent
    let likeCount: Int
    let likedByMe: Bool
    let likeLoading: Bool
    let canLike: Bool
    let onToggleLike: () -> Void
    let onOpenProfile: () -> Void
    let onOpenEvent: () -> Void

    private var badgeColor: Color {
        switch event.kind {
        case .journey: return Color(red: 220.0 / 255.0, green: 244.0 / 255.0, blue: 232.0 / 255.0)
        case .memory: return Color(red: 224.0 / 255.0, green: 242.0 / 255.0, blue: 236.0 / 255.0)
        case .city: return Color(red: 244.0 / 255.0, green: 235.0 / 255.0, blue: 228.0 / 255.0)
        }
    }

    private var badgeTextColor: Color {
        switch event.kind {
        case .journey, .memory: return Color(red: 74.0 / 255.0, green: 177.0 / 255.0, blue: 133.0 / 255.0)
        case .city: return Color(red: 197.0 / 255.0, green: 145.0 / 255.0, blue: 102.0 / 255.0)
        }
    }

    private var badgeLabel: String {
        switch event.kind {
        case .journey: return L10n.t("friends_badge_journey")
        case .memory: return L10n.t("friends_badge_memory")
        case .city: return L10n.t("friends_badge_city")
        }
    }

    private var agoText: String {
        let delta = max(1, Int(Date().timeIntervalSince(event.timestamp)))
        if delta < 3600 { return "\(max(1, delta / 60))m ago" }
        if delta < 86400 { return "\(max(1, delta / 3600))h ago" }
        if delta < 7 * 86400 { return "\(max(1, delta / 86400))d ago" }
        return "\(max(1, delta / (7 * 86400)))w ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpenProfile) {
                    RobotRendererView(size: 36, face: .front, loadout: friend.loadout)
                        .frame(width: 56, height: 56)
                        .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(friend.displayName)
                            .font(.system(size: 15, weight: .bold))
                        Spacer(minLength: 4)
                        Text(agoText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                        .lineLimit(2)

                    if !event.location.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "location")
                                .font(.system(size: 11, weight: .semibold))
                            Text(event.location)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(FigmaTheme.subtext)
                    }
                }
            }
            .appFullSurfaceTapTarget(.rectangle)
            .onTapGesture(perform: onOpenEvent)

            HStack(spacing: 10) {
                Text(badgeLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(badgeTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(badgeColor)
                    .clipShape(Capsule())

                if !event.meta.isEmpty {
                    Text(event.meta)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                        .lineLimit(1)
                }

                Spacer()

                if event.journeyID != nil {
                    Button(action: onToggleLike) {
                        HStack(spacing: 5) {
                            Image(systemName: likedByMe ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(likedByMe ? .red : FigmaTheme.subtext)
                            Text("\(max(0, likeCount))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(FigmaTheme.subtext)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Capsule())
                        .appFullSurfaceTapTarget(.capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canLike || likeLoading)
                    .opacity(canLike ? 1 : 0.5)
                }
            }
        }
        .padding(16)
        .figmaSurfaceCard(radius: 32)
    }
}

private struct AllFriendsCard: View {
    let friend: FriendProfileSnapshot
    let subtitleText: String?

    private var distanceLabel: String {
        "\(Int((friend.stats.totalDistance / 1000.0).rounded()))km"
    }

    private var cityLabel: String {
        "\(friend.stats.totalUnlockedCities) \(L10n.t("friend_profile_stat_cities"))"
    }

    var body: some View {
        HStack(spacing: 14) {
            RobotRendererView(size: 36, face: .front, loadout: friend.loadout)
                .frame(width: 56, height: 56)
                .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                if let subtitleText {
                    Text(subtitleText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(distanceLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(FigmaTheme.text)
                Text(cityLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(FigmaTheme.subtext)
            }
        }
        .padding(16)
        .figmaSurfaceCard(radius: 28)
    }
}

enum FriendListPresencePresentation {
    static func subtitle(
        for friend: FriendProfileSnapshot,
        now: Date = Date(),
        localize: (String) -> String = L10n.t
    ) -> String? {
        guard let recentJourneyDate = recentJourneyDate(for: friend) else {
            return nil
        }

        return String(
            format: localize("friends_recent_journey_ago"),
            shortAgoText(from: recentJourneyDate, now: now, localize: localize).lowercased()
        )
    }

    fileprivate static func recentJourneyDate(for friend: FriendProfileSnapshot) -> Date? {
        friend.journeys
            .compactMap { $0.endTime ?? $0.startTime }
            .max()
    }

    fileprivate static func shortAgoText(
        from date: Date,
        now: Date,
        localize: (String) -> String
    ) -> String {
        let delta = max(1, Int(now.timeIntervalSince(date)))
        if delta < 3600 { return String(format: localize("friends_ago_minutes_format"), max(1, delta / 60)) }
        if delta < 86400 { return String(format: localize("friends_ago_hours_format"), max(1, delta / 3600)) }
        if delta < 7 * 86400 { return String(format: localize("friends_ago_days_format"), max(1, delta / 86400)) }
        return String(format: localize("friends_ago_weeks_format"), max(1, delta / (7 * 86400)))
    }
}

private struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    let prefillInviteCode: String?
    let prefillHandle: String?
    let onAdded: () async -> Void

    @State private var method: AddFriendMethod = .exclusiveID
    @State private var friendCode = ""
    @State private var friendNote = ""
    @State private var submitting = false
    @State private var message = ""
    @State private var showMessage = false
    @State private var showScannerSheet = false

    init(
        prefillInviteCode: String? = nil,
        prefillHandle: String? = nil,
        onAdded: @escaping () async -> Void
    ) {
        self.prefillInviteCode = prefillInviteCode
        self.prefillHandle = prefillHandle
        self.onAdded = onAdded
        if let code = prefillInviteCode, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _method = State(initialValue: .inviteCode)
            _friendCode = State(initialValue: code)
        } else if let handle = prefillHandle, !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _method = State(initialValue: .exclusiveID)
            _friendCode = State(initialValue: handle)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker(L10n.t("friends_add_method_picker"), selection: $method) {
                    ForEach(AddFriendMethod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField(inputPlaceholder, text: $friendCode)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField(L10n.t("friends_add_note_optional"), text: $friendNote)
                    .textFieldStyle(.roundedBorder)

                Button {
                    showScannerSheet = true
                } label: {
                    Label(L10n.t("profile_scan_qr_code"), systemImage: "qrcode.viewfinder")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.bordered)

                Button(submitting ? "发送中..." : "发送好友申请") {
                    Task {
                        await submit()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Spacer(minLength: 0)
            }
            .padding(16)
            .safeAreaInset(edge: .top, spacing: 0) {
                UnifiedNavigationHeader(
                    chrome: NavigationChrome(
                        title: L10n.t("friends_add_title"),
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
            .alert(L10n.t("prompt"), isPresented: $showMessage) {
                Button(L10n.t("ok"), role: .cancel) {}
            } message: {
                Text(message)
            }
            .sheet(isPresented: $showScannerSheet) {
                FriendInviteScannerSheet { text in
                    guard let parsed = AppDeepLinkStore.parseInvite(from: text), !parsed.isEmpty else {
                        message = "二维码内容无法识别，请确认对方分享的是 StreetStamps 邀请码/链接。"
                        showMessage = true
                        return
                    }
                    if let code = parsed.inviteCode, !code.isEmpty {
                        method = .inviteCode
                        friendCode = code
                    } else if let handle = parsed.handle, !handle.isEmpty {
                        method = .exclusiveID
                        friendCode = handle
                    }
                    showMessage = true
                    message = "已识别邀请信息，点击“发送好友申请”即可。"
                }
            }
        }
    }

    private var inputPlaceholder: String {
        switch method {
        case .inviteCode: return "输入邀请码（A1B2C3D4）"
        case .exclusiveID: return "输入好友专属ID（示例：@alice）"
        case .qrToken: return "粘贴二维码 token 或链接"
        }
    }

    private var canSubmit: Bool {
        if submitting { return false }
        let target = resolvedTargetInput()
        return target.inviteCode != nil || target.handle != nil
    }

    private func normalizedInviteCode() -> String? {
        let raw = friendCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        switch method {
        case .inviteCode:
            return raw.uppercased()
        case .exclusiveID:
            return nil
        case .qrToken:
            if raw.contains("code="), let parts = URLComponents(string: raw) {
                return parts.queryItems?.first(where: { $0.name == "code" })?.value?.uppercased()
            }
            return raw.uppercased()
        }
    }

    private func normalizedHandleInput() -> String {
        let raw = friendCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if raw.hasPrefix("@") { return String(raw.dropFirst()) }
        return raw
    }

    private func resolvedTargetInput() -> (inviteCode: String?, handle: String?) {
        let raw = friendCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return (nil, nil) }

        if let parsed = AppDeepLinkStore.parseInvite(from: raw), !parsed.isEmpty {
            let code = parsed.inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            let handle = parsed.handle?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                code?.isEmpty == false ? code : nil,
                handle?.isEmpty == false ? handle : nil
            )
        }

        let trimmedHandle = normalizedHandleInput()
        switch method {
        case .exclusiveID:
            return (nil, trimmedHandle.isEmpty ? nil : trimmedHandle)
        case .inviteCode:
            if looksLikeHandle(trimmedHandle) && !looksLikeInviteCode(raw) {
                return (nil, trimmedHandle)
            }
            return (raw.uppercased(), nil)
        case .qrToken:
            if looksLikeHandle(trimmedHandle) && !looksLikeInviteCode(raw) {
                return (nil, trimmedHandle)
            }
            return (normalizedInviteCode(), nil)
        }
    }

    private func looksLikeInviteCode(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .range(of: #"^[A-Z0-9]{8}$"#, options: .regularExpression) != nil
    }

    private func looksLikeHandle(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .range(of: #"^[a-z0-9_]{1,24}$"#, options: .regularExpression) != nil
    }

    private func resolvedDisplayName() -> String {
        let note = friendNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        return ""
    }

    @MainActor
    private func submit() async {
        submitting = true
        defer { submitting = false }
        do {
            let target = resolvedTargetInput()
            try await socialStore.addFriendSmart(
                displayName: resolvedDisplayName(),
                inviteCode: target.inviteCode,
                handle: target.handle,
                accessToken: sessionStore.currentAccessToken
            )
            await onAdded()
            dismiss()
        } catch {
            message = String(format: L10n.t("friends_add_failed"), error.localizedDescription)
            showMessage = true
        }
    }
}

enum FriendProfileLayout {
    static let topControlsTopPadding: CGFloat = 14
}

private struct FriendProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator

    let friendID: String

    @State private var friend: FriendProfileSnapshot?
    @State private var isSendingStomp = false
    @State private var isVisitorSeated = false
    @State private var stompToastText = ""
    @State private var showStompToast = false
    @State private var sidebarHideToken = UUID().uuidString
    @State private var showDeleteFriendConfirm = false
    @State private var showDeleteFriendError = false
    @State private var deleteFriendErrorText = ""
    @State private var isDeletingFriend = false
    @State private var showPostcardComposer = false

    private var viewerUserID: String {
        let current = sessionStore.accountUserID ?? sessionStore.currentUserID
        return current.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isViewingOwnFriendProfile: Bool {
        !viewerUserID.isEmpty && viewerUserID == friendID
    }

    private var visitorLoadout: RobotLoadout {
        AvatarLoadoutStore.load().normalizedForCurrentAvatar()
    }

    private var fallbackFriend: FriendProfileSnapshot {
        FriendProfileSnapshot(
            id: friendID,
            handle: L10n.t("unknown_id"),
            inviteCode: "",
            profileVisibility: .private,
            displayName: L10n.t("unknown"),
            bio: "",
            loadout: .defaultBoy,
            stats: .init(totalJourneys: 0, totalDistance: 0, totalMemories: 0, totalUnlockedCities: 0),
            journeys: [],
            unlockedCityCards: [],
            createdAt: Date()
        )
    }

    private var levelProgress: UserLevelProgress {
        UserLevelProgress.from(completedJourneyCount: max(0, (friend ?? fallbackFriend).stats.totalJourneys))
    }

    var body: some View {
        let f = friend ?? fallbackFriend
        let sceneState = ProfileSceneInteractionState.resolve(
            mode: .friendProfile,
            isViewingOwnFriendProfile: isViewingOwnFriendProfile,
            isVisitorSeated: isVisitorSeated,
            isInteractionInFlight: isSendingStomp
        )

        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    friendHeroSection(friend: f, sceneState: sceneState)

                    VStack(spacing: 14) {
                        if let displayBio = resolvedBioText(for: f) {
                            Text(displayBio)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(FigmaTheme.text.opacity(0.68))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        }

                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                NavigationLink {
                                    FriendCitiesScreen(friendID: friendID)
                                } label: {
                                    friendProfileMenuTile(
                                        icon: "books.vertical",
                                        iconColor: FigmaTheme.primary,
                                        iconBg: FigmaTheme.primary.opacity(0.14),
                                        title: L10n.t("friend_city_cards_title")
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    FriendPublicMemoriesScreen(friendID: friendID)
                                } label: {
                                    friendProfileMenuTile(
                                        icon: "book.pages",
                                        iconColor: Color(red: 184 / 255, green: 148 / 255, blue: 125 / 255),
                                        iconBg: Color(red: 184 / 255, green: 148 / 255, blue: 125 / 255).opacity(0.14),
                                        title: L10n.t("journey_memory")
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                        }
                    }
                    .frame(maxWidth: 430)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .overlay(alignment: .top) {
            friendTopControls
        }
        .overlay(alignment: .top) {
            if showStompToast {
                Text(stompToastText)
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
            friend = socialStore.friends.first(where: { $0.id == friendID })
            await socialStore.refreshFriendProfileIfPossible(friendID: friendID, accessToken: sessionStore.currentAccessToken)
            friend = socialStore.friends.first(where: { $0.id == friendID })
        }
        .onReceive(socialStore.$friends) { snapshots in
            friend = snapshots.first(where: { $0.id == friendID })
        }
        .confirmationDialog(
            L10n.t("friends_delete_confirm_title"),
            isPresented: $showDeleteFriendConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.t("friends_delete_friend"), role: .destructive) {
                Task {
                    await removeFriend()
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("friends_delete_confirm_message"))
        }
        .alert(L10n.t("friends_delete_failed"), isPresented: $showDeleteFriendError) {
            Button(L10n.t("got_it"), role: .cancel) {}
        } message: {
            Text(deleteFriendErrorText)
        }
        .navigationDestination(isPresented: $showPostcardComposer) {
            PostcardComposerView(
                friendID: friendID,
                friendName: (friend ?? fallbackFriend).displayName
            )
        }
    }

    private var friendTopControls: some View {
        GeometryReader { proxy in
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(FigmaTheme.text)
                        .frame(width: 42, height: 42)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                if sessionStore.isLoggedIn && (sessionStore.accountUserID ?? "") != friendID {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteFriendConfirm = true
                        } label: {
                            Label(L10n.t("friends_delete_friend"), systemImage: "person.crop.circle.badge.xmark")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                            .frame(width: 42, height: 42)
                            .contentShape(Circle())
                    }
                    .disabled(isDeletingFriend)
                } else {
                    Color.clear
                        .frame(width: 42, height: 42)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, FriendProfileLayout.topControlsTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 96)
    }

    private func friendHeroSection(friend: FriendProfileSnapshot, sceneState: ProfileSceneInteractionState) -> some View {
        VStack(spacing: 0) {
            ProfileHeroTopBackdrop {
                GeometryReader { _ in
                    VStack(spacing: 0) {
                        Spacer(minLength: 72)

                        SofaProfileSceneView(
                            state: sceneState,
                            hostLoadout: friend.loadout,
                            visitorLoadout: visitorLoadout,
                            welcomeText: L10n.t("friends_welcome"),
                            postcardPromptText: sceneState.postcardPromptText,
                            onPostcardPromptTap: sceneState.postcardPromptText == nil ? nil : {
                                showPostcardComposer = true
                            },
                            promptBubbleStyle: .chat
                        )
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 30)
                        .padding(.top, 0)
                        .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(height: 376)

            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(friend.displayName)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 39.0 / 255.0))

                            ProfileHeroLevelPill(level: levelProgress.level)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))

                            Text(String(format: "%.1f km", max(0, friend.stats.totalDistance / 1000.0)))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))

                            Text("•")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))

                            Text(String(format: L10n.t("friends_joined_format"), heroJoinedDateText(friend.createdAt)))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 156.0 / 255.0, green: 163.0 / 255.0, blue: 175.0 / 255.0))
                        }
                    }

                    Spacer(minLength: 10)

                    if sceneState.showsCTA, let ctaTitle = sceneState.ctaTitle {
                        Button {
                            Task {
                                await sendProfileStomp(to: friend)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isVisitorSeated ? "sofa.fill" : "sofa")
                                    .font(.system(size: 16, weight: .bold))
                                Text(ctaTitle)
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(height: 48)
                            .padding(.horizontal, 20)
                            .background(FigmaTheme.primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!sceneState.isCTAEnabled)
                        .opacity(sceneState.isCTAEnabled ? 1 : 0.72)
                    }
                }

                ProfileHeroStatsCard(
                    items: [
                        ProfileHeroStatItem(id: "trips", value: "\(friend.stats.totalJourneys)", title: L10n.t("friend_profile_stat_trips")),
                        ProfileHeroStatItem(id: "memories", value: "\(friend.stats.totalMemories)", title: L10n.t("friend_profile_stat_memories")),
                        ProfileHeroStatItem(id: "cities", value: "\(friend.stats.totalUnlockedCities)", title: L10n.t("friend_profile_stat_cities"))
                    ]
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .background(FigmaTheme.background)
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 40, bottomLeading: 0, bottomTrailing: 0, topTrailing: 40),
                    style: .continuous
                )
            )
            .offset(y: -30)
            .padding(.bottom, -30)
        }
    }

    private func heroJoinedDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
    }

    private func resolvedBioText(for friend: FriendProfileSnapshot) -> String? {
        let trimmed = friend.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = normalizeBio(trimmed)
        let placeholders = Set([
            L10n.t("profile_tagline_travel_enthusiastic"),
            "Travel Enthusiastic",
            "旅行爱好者",
            "旅行愛好者"
        ].map(normalizeBio))

        return placeholders.contains(normalized) ? nil : trimmed
    }

    private func normalizeBio(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private func friendProfileMenuTile(icon: String, iconColor: Color, iconBg: Color, title: String) -> some View {
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
        .friendFeatureCardStyle()
    }

    private func friendEmbeddedStatItem(icon: String, value: String, label: String) -> some View {
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

    private func dateText(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }

    @MainActor
    private func sendProfileStomp(to friend: FriendProfileSnapshot) async {
        guard !isSendingStomp else { return }
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else {
            showStompToastMessage(L10n.t("please_sign_in_to_access_your_account"))
            return
        }
        isSendingStomp = true
        defer { isSendingStomp = false }
        do {
            _ = try await BackendAPIClient.shared.stompProfile(token: token, targetUserID: friend.id)
            isVisitorSeated = true
            showStompToastMessage(String(format: L10n.t("friend_profile_stomp_success_format"), friend.displayName))
        } catch {
            showStompToastMessage(String(format: L10n.t("friend_profile_stomp_failed_format"), error.localizedDescription))
        }
    }

    @MainActor
    private func showStompToastMessage(_ text: String) {
        stompToastText = text
        withAnimation(.easeInOut(duration: 0.2)) {
            showStompToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showStompToast = false
            }
        }
    }

    @MainActor
    private func removeFriend() async {
        guard !isDeletingFriend else { return }
        isDeletingFriend = true
        defer { isDeletingFriend = false }

        do {
            try await socialStore.removeFriendSmart(friendID, accessToken: sessionStore.currentAccessToken)
            dismiss()
        } catch {
            deleteFriendErrorText = error.localizedDescription
            showDeleteFriendError = true
        }
    }
}

private struct FriendInviteScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScanned: (String) -> Void

    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var isImportingFromAlbum = false
    @State private var didResolveCode = false
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                FriendInviteScannerRepresentable(
                    onDetected: { code in
                        completeScan(with: code)
                    },
                    onFailure: { message in
                        guard !didResolveCode else { return }
                        scannerError = message
                    }
                )
                .ignoresSafeArea()

                VStack(spacing: 10) {
                    Text(L10n.t("profile_place_qr_in_frame"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())

                    PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Label(isImportingFromAlbum ? "识别中..." : "从相册导入", systemImage: "photo.on.rectangle")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.9))
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                    }
                    .disabled(isImportingFromAlbum || didResolveCode)
                }
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
                    Color.clear
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
            scannerError = "无法读取这张图片，请换一张再试。"
            return
        }

        guard let code = QRCodeImageDecoder.decode(image: image) else {
            scannerError = "未在该图片中识别到二维码。"
            return
        }

        completeScan(with: code)
    }

    @MainActor
    private func completeScan(with code: String) {
        guard !didResolveCode else { return }
        didResolveCode = true
        dismiss()
        onScanned(code)
    }
}

private struct FriendInviteScannerRepresentable: UIViewControllerRepresentable {
    let onDetected: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> FriendInviteScannerViewController {
        let vc = FriendInviteScannerViewController()
        vc.onDetected = onDetected
        vc.onFailure = onFailure
        return vc
    }

    func updateUIViewController(_ uiViewController: FriendInviteScannerViewController, context: Context) {}
}

private final class FriendInviteScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
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
            onFailure?("摄像头权限不可用，请在系统设置中允许访问。")
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
    func friendChevronBackButton() -> some View {
        modifier(FriendChevronBackButtonModifier())
    }

    func friendAvatarCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
    }

    func friendFeatureCardStyle() -> some View {
        self
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 8)
    }
}

private struct FriendChevronBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
    }
}

@MainActor
private final class FriendMirrorContext: ObservableObject {
    let friendID: String
    let paths: StoragePath
    let journeyStore: JourneyStore
    let cityCache: CityCache
    let renderCacheStore: CityRenderCacheStore

    private var lastSignature: String = ""
    private var applyTask: Task<Void, Never>?

    init(friendID: String) {
        self.friendID = friendID
        let scopedID = "friend_preview_\(friendID)"
        self.paths = StoragePath(userID: scopedID)
        try? paths.ensureBaseDirectoriesExist()
        self.journeyStore = JourneyStore(paths: paths)
        self.cityCache = CityCache(paths: paths, journeyStore: journeyStore)
        self.renderCacheStore = CityRenderCacheStore(rootDir: paths.thumbnailsDir)
    }

    static func signature(for snapshot: FriendProfileSnapshot) -> String {
        let journeys = snapshot.journeys
            .map {
                let memorySignature = $0.memories
                    .map {
                        [
                            $0.id,
                            $0.title,
                            $0.notes,
                            String($0.timestamp.timeIntervalSince1970),
                            $0.imageURLs.joined(separator: ","),
                            $0.latitude.map(String.init) ?? "",
                            $0.longitude.map(String.init) ?? "",
                            $0.locationStatus ?? ""
                        ].joined(separator: "|")
                    }
                    .joined(separator: ";")
                return "\($0.id)|\($0.title)|\($0.distance)|\($0.routeCoordinates.count)|\($0.memories.count)|\($0.endTime?.timeIntervalSince1970 ?? 0)|\(memorySignature)"
            }
            .joined(separator: ";")
        let cards = snapshot.unlockedCityCards
            .map { "\($0.id)|\($0.name)|\($0.countryISO2 ?? "")" }
            .joined(separator: ";")
        return "\(snapshot.id)||\(journeys)||\(cards)"
    }

    func apply(snapshot: FriendProfileSnapshot) {
        let sig = Self.signature(for: snapshot)
        guard sig != lastSignature else { return }
        lastSignature = sig

        applyTask?.cancel()
        let snapshotCopy = snapshot
        let targetPaths = paths
        applyTask = Task { [weak self] in
            await Task.detached(priority: .userInitiated) {
                FriendMirrorContext.mirrorSnapshot(snapshotCopy, to: targetPaths)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.journeyStore.rebind(paths: targetPaths)
            self.cityCache.rebind(paths: targetPaths)
            self.renderCacheStore.rebind(rootDir: targetPaths.thumbnailsDir)
            self.journeyStore.load()
        }
    }

    nonisolated private static func mirrorSnapshot(_ snapshot: FriendProfileSnapshot, to paths: StoragePath) {
        try? paths.ensureBaseDirectoriesExist()
        clearMirroredFiles(paths: paths)
        let routes = buildMirroredRoutes(from: snapshot)
        persistJourneys(routes, paths: paths)
        persistCities(from: snapshot, mirroredRoutes: routes, paths: paths)
    }

    nonisolated private static func clearMirroredFiles(paths: StoragePath) {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: paths.journeysDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for f in files {
                try? fm.removeItem(at: f)
            }
        }
        try? fm.removeItem(at: paths.cityCacheURL)
        try? fm.removeItem(at: paths.routeCacheURL)
    }

    nonisolated private static func persistJourneys(_ routes: [JourneyRoute], paths: StoragePath) {
        let fileStore = JourneysFileStore(baseURL: paths.journeysDir)
        let indexStore = JourneysIndexStore(baseURL: paths.journeysDir)
        for route in routes {
            try? fileStore.finalizeJourney(route)
        }
        try? indexStore.replaceIDs(routes.map(\.id))
    }

    nonisolated private static func persistCities(from snapshot: FriendProfileSnapshot, mirroredRoutes: [JourneyRoute], paths: StoragePath) {
        let routesByCityID = Dictionary(grouping: mirroredRoutes) { $0.startCityKey ?? $0.cityKey }
        let cities: [CachedCity] = snapshot.unlockedCityCards.map { card in
            let js = routesByCityID[card.id] ?? []
            let memories = js.reduce(0) { $0 + $1.memories.count }
            let anchorCoord = js.first?.allCLCoords.first
            return CachedCity(
                id: card.id,
                name: card.name,
                countryISO2: card.countryISO2,
                journeyIds: js.map(\.id),
                explorations: js.count,
                memories: memories,
                boundary: nil,
                anchor: anchorCoord.map(LatLon.init),
                thumbnailBasePath: nil,
                thumbnailRoutePath: nil,
                reservedLevelRaw: nil,
                reservedParentRegionKey: nil,
                reservedAvailableLevelNames: nil,
                isTemporary: false
            )
        }
        if let data = try? JSONEncoder().encode(cities) {
            try? data.write(to: paths.cityCacheURL, options: .atomic)
        }
    }

    nonisolated private static func buildMirroredRoutes(from snapshot: FriendProfileSnapshot) -> [JourneyRoute] {
        let cards = snapshot.unlockedCityCards
        return snapshot.journeys
            .sorted { ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast) }
            .map { toJourneyRoute(friendJourney: $0, cards: cards) }
    }

    nonisolated private static func toJourneyRoute(friendJourney: FriendSharedJourney, cards: [FriendCityCard]) -> JourneyRoute {
        let routeCoords = friendJourney.routeCoordinates
        let cityID = FriendJourneyCityIdentity.resolveCityID(for: friendJourney, cards: cards)
        let cityCard = cards.first(where: { $0.id == cityID })
        let cityName = CityDisplayTitlePresentation.title(
            cityKey: cityCard?.id ?? cityID,
            iso2: cityCard?.countryISO2,
            fallbackTitle: cityCard?.name ?? friendJourney.title
        )

        let fallbackCoordinate: CoordinateCodable = routeCoords.first ?? CoordinateCodable(lat: 0, lon: 0)
        let memories: [JourneyMemory] = friendJourney.memories.enumerated().map { idx, memory in
            let explicitCoordinate: CoordinateCodable? = {
                guard let latitude = memory.latitude, let longitude = memory.longitude else { return nil }
                return CoordinateCodable(lat: latitude, lon: longitude)
            }()
            let coord = explicitCoordinate ?? (routeCoords.isEmpty ? fallbackCoordinate : routeCoords[min(idx, routeCoords.count - 1)])
            let status = JourneyMemoryLocationStatus(rawValue: memory.locationStatus ?? "")
                ?? (explicitCoordinate == nil ? .resolved : .fallback)
            let source: JourneyMemoryLocationSource = {
                if status == .pending { return .pending }
                if explicitCoordinate != nil && status == .fallback { return .trackNearestByTime }
                return .legacyCoordinate
            }()
            return JourneyMemory(
                id: memory.id,
                timestamp: memory.timestamp,
                title: memory.title,
                notes: memory.notes,
                imageData: nil,
                imagePaths: [],
                remoteImageURLs: memory.imageURLs,
                cityKey: cityID,
                cityName: cityName,
                coordinate: (coord.lat, coord.lon),
                type: .memory,
                locationStatus: status,
                locationSource: source
            )
        }

        return JourneyRoute(
            id: friendJourney.id,
            startTime: friendJourney.startTime,
            endTime: friendJourney.endTime,
            distance: max(0, friendJourney.distance),
            elevationGain: 0,
            elevationLoss: 0,
            isTooShort: false,
            cityKey: cityID,
            canonicalCity: cityName,
            coordinates: routeCoords,
            memories: memories,
            thumbnailCoordinates: routeCoords,
            countryISO2: cityCard?.countryISO2,
            currentCity: cityName,
            cityName: cityName,
            startCityKey: cityID,
            endCityKey: cityID,
            exploreMode: .city,
            trackingMode: .daily,
            visibility: friendJourney.visibility,
            customTitle: friendJourney.title,
            activityTag: friendJourney.activityTag,
            overallMemory: friendJourney.overallMemory
        )
    }

}

private struct FriendJourneysScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @Environment(\.locale) private var locale

    let friendID: String

    @StateObject private var mirror: FriendMirrorContext
    @State private var sidebarHideToken = UUID().uuidString

    init(friendID: String) {
        self.friendID = friendID
        _mirror = StateObject(wrappedValue: FriendMirrorContext(friendID: friendID))
    }

    var body: some View {
        Group {
            if let friend = socialStore.friends.first(where: { $0.id == friendID }) {
                MyJourneysView(
                    routeDetailReadOnly: true,
                    routeDetailHeaderTitle: FriendSectionTitleFormatter.sectionTitle(for: .journeyDetail, friendName: friend.displayName, locale: locale),
                    headerTitle: FriendSectionTitleFormatter.sectionTitle(for: .journeys, friendName: friend.displayName, locale: locale)
                )
                    .environmentObject(mirror.journeyStore)
                    .environmentObject(sessionStore)
                    .task(id: FriendMirrorContext.signature(for: friend)) {
                        mirror.apply(snapshot: friend)
                    }
            } else {
                Text(L10n.t("content_unavailable"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .task {
            await socialStore.refreshFriendProfileIfPossible(
                friendID: friendID,
                accessToken: sessionStore.currentAccessToken
            )
        }
        .navigationBarHidden(true)
    }
}

private struct FriendCitiesScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @Environment(\.locale) private var locale
    let friendID: String

    @StateObject private var mirror: FriendMirrorContext
    @State private var sidebarHideToken = UUID().uuidString

    init(friendID: String) {
        self.friendID = friendID
        _mirror = StateObject(wrappedValue: FriendMirrorContext(friendID: friendID))
    }

    var body: some View {
        Group {
            if let friend = socialStore.friends.first(where: { $0.id == friendID }) {
                CityStampLibraryView(
                    showSidebar: .constant(false),
                    autoRebuildFromJourneyStore: false,
                    usesSidebarHeader: false,
                    allowCityDetailNavigation: false,
                    headerTitle: FriendSectionTitleFormatter.sectionTitle(for: .cityCards, friendName: friend.displayName, locale: locale),
                    emptyTitleKey: "friend_city_cards_empty_title",
                    emptySubtitleKey: "friend_city_cards_empty_subtitle"
                )
                    .environmentObject(mirror.journeyStore)
                    .environmentObject(mirror.cityCache)
                    .environmentObject(mirror.renderCacheStore)
                    .task(id: FriendMirrorContext.signature(for: friend)) {
                        mirror.apply(snapshot: friend)
                    }
            } else {
                Text(L10n.t("content_unavailable"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .task {
            await socialStore.refreshFriendProfileIfPossible(
                friendID: friendID,
                accessToken: sessionStore.currentAccessToken
            )
        }
        .navigationBarHidden(true)
    }
}

private struct FriendEquipmentScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: SocialGraphStore
    @ObservedObject private var catalogStore: AvatarCatalogStore = .shared

    let friendID: String

    private var friend: FriendProfileSnapshot? {
        socialStore.friends.first(where: { $0.id == friendID })
    }

    private func equippedName(categoryID: String, itemID: String?) -> String {
        guard let itemID, !itemID.isEmpty else { return "None" }
        let nameKey = catalogStore.item(categoryId: categoryID, itemId: itemID)?.nameKey ?? itemID
        return L10n.t(nameKey)
    }

    private func equippedAccessoryNames(_ itemIDs: [String]) -> String {
        let visible = itemIDs.filter { !$0.isEmpty && $0 != "none" }
        guard !visible.isEmpty else { return "None" }
        return visible.map { equippedName(categoryID: "accessory", itemID: $0) }.joined(separator: ", ")
    }

    var body: some View {
        Group {
            if let friend {
                ScrollView {
                    VStack(spacing: 12) {
                        RobotRendererView(size: 150, face: .front, loadout: friend.loadout)
                            .frame(width: 180, height: 180)
                            .background(Color(red: 227.0/255.0, green: 239.0/255.0, blue: 235.0/255.0))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            FriendEquipmentRow(title: "Hair", value: equippedName(categoryID: "hair", itemID: friend.loadout.hairId))
                            FriendEquipmentRow(title: "Upper", value: equippedName(categoryID: "upper", itemID: friend.loadout.upperId))
                            FriendEquipmentRow(title: "Under", value: equippedName(categoryID: "under", itemID: friend.loadout.underId))
                            FriendEquipmentRow(title: "Hat", value: equippedName(categoryID: "hat", itemID: friend.loadout.hatId))
                            FriendEquipmentRow(title: "Glasses", value: equippedName(categoryID: "glass", itemID: friend.loadout.glassId))
                            FriendEquipmentRow(title: "Accessory", value: equippedAccessoryNames(friend.loadout.accessoryIds))
                            FriendEquipmentRow(title: "Expression", value: equippedName(categoryID: "expression", itemID: friend.loadout.expressionId))
                        }
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(12)
                }
                .background(Color(red: 251.0/255.0, green: 251.0/255.0, blue: 249.0/255.0).ignoresSafeArea())
                .safeAreaInset(edge: .top, spacing: 0) {
                    UnifiedNavigationHeader(
                        chrome: NavigationChrome(
                            title: "\(friend.displayName) Equipment",
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
            } else {
                Text(L10n.t("content_unavailable"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct FriendEquipmentRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FigmaTheme.text.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FigmaTheme.text)
        }
        .padding(.vertical, 4)
    }
}

private struct FriendPublicMemoriesScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @Environment(\.locale) private var locale
    let friendID: String

    @StateObject private var mirror: FriendMirrorContext
    @State private var sidebarHideToken = UUID().uuidString

    init(friendID: String) {
        self.friendID = friendID
        _mirror = StateObject(wrappedValue: FriendMirrorContext(friendID: friendID))
    }

    var body: some View {
        Group {
            if let friend = socialStore.friends.first(where: { $0.id == friendID }) {
                JourneyMemoryMainView(
                    showSidebar: .constant(false),
                    usesSidebarHeader: false,
                    readOnly: true,
                    headerTitle: FriendSectionTitleFormatter.sectionTitle(for: .journeyMemories, friendName: friend.displayName, locale: locale),
                    emptyTitleKey: "friend_memories_empty_title",
                    emptySubtitleKey: "friend_memories_empty_subtitle"
                )
                    .environmentObject(mirror.journeyStore)
                    .environmentObject(sessionStore)
                    .task(id: FriendMirrorContext.signature(for: friend)) {
                        mirror.apply(snapshot: friend)
                    }
            } else {
                Text(L10n.t("content_unavailable"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .task {
            await socialStore.refreshFriendProfileIfPossible(
                friendID: friendID,
                accessToken: sessionStore.currentAccessToken
            )
        }
        .navigationBarHidden(true)
    }
}

private struct FriendJourneyRouteScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator
    @Environment(\.locale) private var locale

    let friendID: String
    let journeyID: String

    @StateObject private var mirror: FriendMirrorContext
    @State private var sidebarHideToken = UUID().uuidString

    init(friendID: String, journeyID: String) {
        self.friendID = friendID
        self.journeyID = journeyID
        _mirror = StateObject(wrappedValue: FriendMirrorContext(friendID: friendID))
    }

    var body: some View {
        Group {
            if let friend = socialStore.friends.first(where: { $0.id == friendID }) {
                JourneyRouteDetailView(
                    journeyID: journeyID,
                    isReadOnly: true,
                    headerTitle: FriendSectionTitleFormatter.sectionTitle(for: .journeyDetail, friendName: friend.displayName, locale: locale)
                )
                    .environmentObject(mirror.journeyStore)
                    .environmentObject(sessionStore)
                    .task(id: FriendMirrorContext.signature(for: friend)) {
                        mirror.apply(snapshot: friend)
                    }
            } else {
                Text(L10n.t("content_unavailable"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            flow.pushSidebarButtonHidden(token: sidebarHideToken)
        }
        .onDisappear {
            flow.popSidebarButtonHidden(token: sidebarHideToken)
        }
        .task {
            await socialStore.refreshFriendProfileIfPossible(
                friendID: friendID,
                accessToken: sessionStore.currentAccessToken
            )
        }
        .navigationBarHidden(true)
    }
}
