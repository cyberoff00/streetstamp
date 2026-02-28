import SwiftUI
import UIKit
import MapKit

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

private struct FriendFeedEvent: Identifiable {
    enum Kind {
        case journey
        case memory
        case city
    }

    let id: String
    let kind: Kind
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

    private var sortedFriends: [FriendProfileSnapshot] {
        socialStore.friends.sorted { lhs, rhs in
            lastActiveDate(of: lhs) > lastActiveDate(of: rhs)
        }
    }

    private var feedEvents: [FriendFeedEvent] {
        buildFeedEvents(from: sortedFriends)
    }

    private var feedLikeSignature: String {
        feedEvents
            .compactMap { event -> String? in
                guard let journeyID = event.journeyID else { return nil }
                return feedLikeKey(friendID: event.friendID, journeyID: journeyID)
            }
            .sorted()
            .joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabSwitcher

            Divider().overlay(Color.black.opacity(0.06))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if tab == .activity {
                        if feedEvents.isEmpty {
                            emptyState(L10n.t("friends_empty_activity"))
                        } else {
                            ForEach(feedEvents) { event in
                                if let friend = sortedFriends.first(where: { $0.id == event.friendID }) {
                                    FriendActivityCard(
                                        friend: friend,
                                        event: event,
                                        likeCount: likeCountForEvent(event),
                                        likedByMe: likedByMeForEvent(event),
                                        likeLoading: likeLoadingForEvent(event),
                                        canLike: true,
                                        onToggleLike: {
                                            guard let journeyID = event.journeyID else { return }
                                            Task {
                                                await toggleFeedLike(friendID: friend.id, journeyID: journeyID)
                                            }
                                        },
                                        onOpenProfile: {
                                            activeRoute = .profile(friend.id)
                                        },
                                        onOpenEvent: {
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

                        if !outgoingFriendRequests.isEmpty {
                            friendRequestSectionTitle("已发送申请")
                            ForEach(outgoingFriendRequests) { req in
                                friendRequestCard(request: req, isIncoming: false)
                            }
                        }

                        if sortedFriends.isEmpty {
                            if incomingFriendRequests.isEmpty && outgoingFriendRequests.isEmpty {
                                emptyState(L10n.t("friends_empty_all"))
                            }
                        } else {
                            friendRequestSectionTitle("我的好友")
                            ForEach(sortedFriends) { friend in
                                Button {
                                    activeRoute = .profile(friend.id)
                                } label: {
                                    AllFriendsCard(friend: friend, activeText: activeText(for: friend))
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
        }
        .background(FigmaTheme.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .navigationDestination(item: $activeRoute) { route in
            destination(for: route)
        }
        .sheet(isPresented: $showAddFriendSheet) {
            AddFriendSheet {
                await refreshRemoteFriends()
            }
            .environmentObject(socialStore)
            .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showSocialNotificationsSheet) {
            socialNotificationsSheet
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
            }
        }
        .task(id: feedLikeSignature) {
            await loadFeedLikeStatsIfNeeded()
        }
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
        UnifiedTabPageHeader(title: L10n.t("friends_title"), horizontalPadding: 16, topPadding: 14, bottomPadding: 12) {
            Color.clear
        } trailing: {
            if tab == .allFriends {
                Button {
                    showAddFriendSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showSocialNotificationsSheet = true
                    Task {
                        await markSocialNotificationsReadIfNeeded()
                    }
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
                RobotRendererView(size: 36, face: .front, loadout: profile.loadout ?? .defaultBoy)
                    .frame(width: 56, height: 56)
                    .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(FigmaTheme.text)
                    Text(String(format: L10n.t("friends_exclusive_id_format"), profile.handle ?? L10n.t("unknown_id")))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext)
                    Text(shortAgoText(from: request.createdAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(FigmaTheme.subtext.opacity(0.8))
                }
                Spacer(minLength: 8)
            }

            if isIncoming {
                HStack(spacing: 10) {
                    Button(loading ? "处理中..." : "通过") {
                        Task { await acceptFriendRequest(request.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading)

                    Button("忽略") {
                        Task { await rejectFriendRequest(request.id) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(loading)
                }
            } else {
                Text("等待对方通过")
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

    private func lastActiveDate(of friend: FriendProfileSnapshot) -> Date {
        friend.journeys
            .compactMap { $0.endTime ?? $0.startTime }
            .max() ?? friend.createdAt
    }

    private func activeText(for friend: FriendProfileSnapshot) -> String {
        let date = lastActiveDate(of: friend)
        return String(format: L10n.t("friends_active_ago"), shortAgoText(from: date).lowercased())
    }

    private func shortAgoText(from date: Date) -> String {
        let delta = max(1, Int(Date().timeIntervalSince(date)))
        if delta < 3600 { return "\(max(1, delta / 60))m ago" }
        if delta < 86400 { return "\(max(1, delta / 3600))h ago" }
        if delta < 7 * 86400 { return "\(max(1, delta / 86400))d ago" }
        return "\(max(1, delta / (7 * 86400)))w ago"
    }

    private func buildFeedEvents(from friends: [FriendProfileSnapshot]) -> [FriendFeedEvent] {
        var events: [FriendFeedEvent] = []

        for friend in friends {
            let visibleJourneys = friend.journeys
                .filter { $0.visibility == .public || $0.visibility == .friendsOnly }
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
                    let cityKey = normalizeCityKey(journey.title)
                    guard !cityKey.isEmpty, map[cityKey] == nil else { continue }
                    map[cityKey] = journey.id
                }
                return map
            }()

            for journey in visibleJourneys.prefix(12) {
                let eventDate = feedTimestamp(for: journey)
                let cityName = journey.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let cityKey = normalizeCityKey(cityName)
                let memoryCount = journey.memories.count
                let photoCount = journey.memories.reduce(0) { $0 + $1.imageURLs.count }
                let unlockedNewCity = !cityKey.isEmpty && firstJourneyByCity[cityKey] == journey.id

                let kind: FriendFeedEvent.Kind
                if unlockedNewCity {
                    kind = .city
                } else if memoryCount > 0 {
                    kind = .memory
                } else {
                    kind = .journey
                }

                let eventTitle: String
                let metaText: String
                switch kind {
                case .city:
                    eventTitle = String(format: L10n.t("friends_event_visited"), cityName.isEmpty ? L10n.t("unknown_city") : cityName)
                    metaText = ""
                case .memory:
                    eventTitle = String(format: L10n.t("friends_event_added_memories"), memoryCount)
                    metaText = "\(max(photoCount, memoryCount)) photos"
                case .journey:
                    eventTitle = String(format: L10n.t("friends_event_completed"), journey.title)
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

    private func normalizeCityKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func formatDistance(_ meters: Double) -> String {
        String(format: "%.1fkm", meters / 1000.0)
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
            showFeedToast("后端地址未配置，请先在 Account Center 配置 API_BASE_URL", duration: 2.0)
            return
        }
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else {
            showFeedToast("请先登录账号", duration: 2.0)
            return
        }

        let key = feedLikeKey(friendID: friendID, journeyID: journeyID)
        guard !feedLikeLoadingKeys.contains(key) else { return }
        feedLikeLoadingKeys.insert(key)
        defer { feedLikeLoadingKeys.remove(key) }

        let liked = feedLikeStats[key]?.likedByMe ?? false
        do {
            let resp: JourneyLikeActionResponse
            if liked {
                resp = try await BackendAPIClient.shared.unlikeJourney(
                    token: token,
                    ownerUserID: friendID,
                    journeyID: journeyID
                )
            } else {
                resp = try await BackendAPIClient.shared.likeJourney(
                    token: token,
                    ownerUserID: friendID,
                    journeyID: journeyID
                )
            }
            feedLikeStats[key] = (likes: max(0, resp.likes), likedByMe: resp.likedByMe)
        } catch {
            showFeedToast("点赞失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshRemoteFriends() async {
        guard !loadingRemote else { return }
        loadingRemote = true
        defer { loadingRemote = false }
        await socialStore.reloadFromBackendIfPossible(accessToken: sessionStore.currentAccessToken)
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
            let promptTypes: Set<String> = ["journey_like", "profile_stomp"]
            let socialItems = all
                .filter({ promptTypes.contains($0.type) })
                .sorted(by: { $0.createdAt > $1.createdAt })
            socialNotifications = socialItems

            let unread = socialItems.filter { !$0.read }
            unreadSocialCount = unread.count

            if showToastForLatestUnread,
               let latest = unread.first,
               latest.id != lastPromptNotificationID {
                showFeedToast(latest.message, duration: 2.2)
                lastPromptNotificationID = latest.id
            }
        } catch {
            // Keep social feed resilient even if reminder endpoint fails.
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
            showFeedToast("请先登录账号", duration: 2.0)
            return
        }
        guard !requestActionLoadingIDs.contains(requestID) else { return }
        requestActionLoadingIDs.insert(requestID)
        defer { requestActionLoadingIDs.remove(requestID) }

        do {
            let resp = try await BackendAPIClient.shared.acceptFriendRequest(token: token, requestID: requestID)
            await refreshRemoteFriends()
            showFeedToast(resp.message ?? "已通过好友申请")
        } catch {
            showFeedToast("通过失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func rejectFriendRequest(_ requestID: String) async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else {
            showFeedToast("请先登录账号", duration: 2.0)
            return
        }
        guard !requestActionLoadingIDs.contains(requestID) else { return }
        requestActionLoadingIDs.insert(requestID)
        defer { requestActionLoadingIDs.remove(requestID) }

        do {
            let resp = try await BackendAPIClient.shared.rejectFriendRequest(token: token, requestID: requestID)
            await refreshFriendRequests()
            showFeedToast(resp.message ?? "已拒绝好友申请")
        } catch {
            showFeedToast("拒绝失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func markSocialNotificationsReadIfNeeded() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else { return }
        let unreadIDs = socialNotifications.filter { !$0.read }.map(\.id)
        guard !unreadIDs.isEmpty else { return }

        do {
            try await BackendAPIClient.shared.markNotificationsRead(token: token, ids: unreadIDs)
            socialNotifications = socialNotifications.map { item in
                guard unreadIDs.contains(item.id) else { return item }
                var copy = item
                copy.read = true
                return copy
            }
            unreadSocialCount = 0
        } catch {
            // Keep feed page responsive even if read-mark fails.
        }
    }

    @ViewBuilder
    private var socialNotificationsSheet: some View {
        NavigationStack {
            Group {
                if notificationsLoading && socialNotifications.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("加载通知中...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(FigmaTheme.subtext)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if socialNotifications.isEmpty {
                    Text("暂时还没有互动通知")
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
            .navigationTitle("互动通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        showSocialNotificationsSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") {
                        Task {
                            await refreshSocialNotifications(showToastForLatestUnread: false)
                        }
                    }
                }
            }
            .task {
                await refreshSocialNotifications(showToastForLatestUnread: false)
            }
        }
    }

    private func socialNotificationRow(_ item: BackendNotificationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.read ? Color.clear : Color(red: 0.22, green: 0.45, blue: 0.89))
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.type == "journey_like" ? "收到点赞" : "主页被踩")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(item.type == "journey_like" ? Color.red : Color(red: 0.22, green: 0.45, blue: 0.89))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())

                    Text(relativeTimeText(item.createdAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FigmaTheme.subtext)
                }

                Text(item.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(FigmaTheme.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
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
            .contentShape(Rectangle())
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
    let activeText: String

    private var distanceLabel: String {
        "\(Int((friend.stats.totalDistance / 1000.0).rounded()))km"
    }

    private var cityLabel: String {
        "\(friend.stats.totalUnlockedCities) CITIES"
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
                Text(activeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
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

private struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    let onAdded: () async -> Void

    @State private var method: AddFriendMethod = .exclusiveID
    @State private var friendCode = ""
    @State private var friendNote = ""
    @State private var submitting = false
    @State private var message = ""
    @State private var showMessage = false

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
            .navigationTitle(L10n.t("friends_add_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("close")) { dismiss() }
                }
            }
            .alert(L10n.t("prompt"), isPresented: $showMessage) {
                Button(L10n.t("ok"), role: .cancel) {}
            } message: {
                Text(message)
            }
        }
    }

    private var inputPlaceholder: String {
        switch method {
        case .inviteCode: return "输入邀请码（A1B2C3D4）"
        case .exclusiveID: return "输入好友专属ID（支持带或不带 @）"
        case .qrToken: return "粘贴二维码 token 或链接"
        }
    }

    private var canSubmit: Bool {
        if submitting { return false }
        switch method {
        case .exclusiveID:
            return !normalizedHandleInput().isEmpty
        case .inviteCode, .qrToken:
            return normalizedInviteCode() != nil
        }
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
            try await socialStore.addFriendSmart(
                displayName: resolvedDisplayName(),
                inviteCode: normalizedInviteCode(),
                handle: method == .exclusiveID ? normalizedHandleInput() : nil,
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

private struct FriendProfileScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator

    let friendID: String

    @State private var friend: FriendProfileSnapshot?
    @State private var isSendingStomp = false
    @State private var stompToastText = ""
    @State private var showStompToast = false
    @State private var sidebarHideToken = UUID().uuidString

    private var canStomp: Bool {
        (sessionStore.accountUserID ?? "") != friendID
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

        ZStack(alignment: .top) {
            FigmaTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(FigmaTheme.text)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(f.displayName)
                        .appHeaderStyle()
                        .tracking(0.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer()

                    Color.clear
                        .frame(width: 42, height: 42)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(FigmaTheme.border)
                        .frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        VStack(spacing: 0) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .fill(FigmaTheme.primary.opacity(0.17))
                                    .blur(radius: 20)
                                    .frame(width: 132, height: 132)

                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                FigmaTheme.primary.opacity(0.10),
                                                FigmaTheme.accent.opacity(0.20)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 128, height: 128)
                                    .shadow(color: FigmaTheme.primary.opacity(0.12), radius: 24, x: 0, y: 4)

                                RobotRendererView(
                                    size: 96,
                                    face: .front,
                                    loadout: f.loadout
                                )
                            }
                            .padding(.top, 32)

                            HStack(spacing: 8) {
                                Text(f.displayName)
                                    .font(.system(size: 20, weight: .bold))
                                    .tracking(-0.3)
                                    .foregroundColor(FigmaTheme.text)
                                LevelBadgeView(level: levelProgress.level)
                            }
                            .padding(.top, 20)

                            Text(String(format: L10n.t("friends_exclusive_id_format"), f.handle))
                                .font(.system(size: 13, weight: .regular))
                                .tracking(0.2)
                                .foregroundColor(FigmaTheme.subtext)
                                .padding(.top, 8)

                            if canStomp {
                                Button {
                                    Task {
                                        await sendProfileStomp(to: f)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "shoeprints.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(isSendingStomp ? "发送中..." : "踩一踩主页")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(FigmaTheme.primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(isSendingStomp)
                                .padding(.top, 10)
                            }

                            if let displayBio = resolvedBioText(for: f) {
                                Text(displayBio)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FigmaTheme.text.opacity(0.72))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 22)
                                    .padding(.top, 8)
                            }

                            HStack(spacing: 8) {
                                Text(String(format: "%.1f km", max(0, f.stats.totalDistance / 1000.0)))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FigmaTheme.text.opacity(0.62))
                                Text("·")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(FigmaTheme.text.opacity(0.42))
                                Text(String(format: "Joined %@", dateText(f.createdAt)))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(FigmaTheme.text.opacity(0.72))
                            }
                            .padding(.top, 6)

                            Rectangle()
                                .fill(FigmaTheme.border)
                                .frame(height: 1)
                                .padding(.top, 22)

                            HStack(spacing: 0) {
                                friendEmbeddedStatItem(
                                    icon: "mappin.and.ellipse",
                                    value: "\(f.stats.totalJourneys)",
                                    label: "TRIPS"
                                )
                                Rectangle()
                                    .fill(FigmaTheme.border)
                                    .frame(width: 1, height: 52)
                                friendEmbeddedStatItem(
                                    icon: "heart",
                                    value: "\(f.stats.totalMemories)",
                                    label: "MEMORIES"
                                )
                                Rectangle()
                                    .fill(FigmaTheme.border)
                                    .frame(width: 1, height: 52)
                                friendEmbeddedStatItem(
                                    icon: "paperplane",
                                    value: "\(f.stats.totalUnlockedCities)",
                                    label: "CITIES"
                                )
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .friendAvatarCardStyle()

                        HStack(spacing: 14) {
                            NavigationLink {
                                FriendCitiesScreen(friendID: friendID)
                            } label: {
                                friendProfileMenuTile(
                                    icon: "books.vertical",
                                    iconColor: FigmaTheme.primary,
                                    iconBg: FigmaTheme.primary.opacity(0.14),
                                    title: "CITY LIBRARY"
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
                                    title: "JOURNEY MEMORY"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if sessionStore.isLoggedIn {
                            Button(role: .destructive) {
                                Task {
                                    try? await socialStore.removeFriendSmart(friendID, accessToken: sessionStore.currentAccessToken)
                                    dismiss()
                                }
                            } label: {
                                Text(L10n.t("friends_delete"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
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
            showStompToastMessage("请先登录账号")
            return
        }
        isSendingStomp = true
        defer { isSendingStomp = false }
        do {
            let resp = try await BackendAPIClient.shared.stompProfile(token: token, targetUserID: friend.id)
            showStompToastMessage(resp.message ?? "已踩一踩 \(friend.displayName) 的主页")
        } catch {
            showStompToastMessage("踩一踩失败：\(error.localizedDescription)")
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

    private var lastSignature: String = ""
    private var applyTask: Task<Void, Never>?

    init(friendID: String) {
        self.friendID = friendID
        let scopedID = "friend_preview_\(friendID)"
        self.paths = StoragePath(userID: scopedID)
        try? paths.ensureBaseDirectoriesExist()
        self.journeyStore = JourneyStore(paths: paths)
        self.cityCache = CityCache(paths: paths, journeyStore: journeyStore)
    }

    static func signature(for snapshot: FriendProfileSnapshot) -> String {
        let journeys = snapshot.journeys
            .map {
                "\($0.id)|\($0.title)|\($0.distance)|\($0.routeCoordinates.count)|\($0.memories.count)|\($0.endTime?.timeIntervalSince1970 ?? 0)"
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
        let cityID = resolveCityID(for: friendJourney, cards: cards)
        let cityCard = cards.first(where: { $0.id == cityID })
        let cityName = cityCard?.name ?? friendJourney.title

        let fallbackCoordinate: CoordinateCodable = routeCoords.first ?? CoordinateCodable(lat: 0, lon: 0)
        let memories: [JourneyMemory] = friendJourney.memories.enumerated().map { idx, memory in
            let coord = routeCoords.isEmpty ? fallbackCoordinate : routeCoords[min(idx, routeCoords.count - 1)]
            return JourneyMemory(
                id: memory.id,
                timestamp: memory.timestamp,
                title: memory.title,
                notes: memory.notes,
                imageData: nil,
                imagePaths: [],
                cityKey: cityID,
                cityName: cityName,
                coordinate: (coord.lat, coord.lon),
                type: .memory
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

    nonisolated private static func resolveCityID(for journey: FriendSharedJourney, cards: [FriendCityCard]) -> String {
        guard !cards.isEmpty else { return "Unknown|" }
        let normalizedTitle = normalizeKey(journey.title)
        if let hit = cards.first(where: { normalizeKey($0.name) == normalizedTitle }) {
            return hit.id
        }
        if let fuzzy = cards.first(where: {
            let k = normalizeKey($0.name)
            return !k.isEmpty && !normalizedTitle.isEmpty && (normalizedTitle.contains(k) || k.contains(normalizedTitle))
        }) {
            return fuzzy.id
        }
        return cards[0].id
    }

    nonisolated private static func normalizeKey(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}

private struct FriendJourneysScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @EnvironmentObject private var flow: AppFlowCoordinator

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
                    routeDetailHeaderTitle: "\(friend.displayName) · Journey",
                    headerTitle: "\(friend.displayName) · Journeys"
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
                    headerTitle: "\(friend.displayName) · City Library"
                )
                    .environmentObject(mirror.journeyStore)
                    .environmentObject(mirror.cityCache)
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
                            FriendEquipmentRow(title: "Suit", value: equippedName(categoryID: "suit", itemID: friend.loadout.suitId))
                            FriendEquipmentRow(title: "Upper", value: equippedName(categoryID: "upper", itemID: friend.loadout.upperId))
                            FriendEquipmentRow(title: "Under", value: equippedName(categoryID: "under", itemID: friend.loadout.underId))
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
                .navigationTitle("\(friend.displayName) Equipment")
            } else {
                Text(L10n.t("content_unavailable"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .friendChevronBackButton()
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
                    headerTitle: "\(friend.displayName) · Journey Memory"
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
                    headerTitle: "\(friend.displayName) · Journey"
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
