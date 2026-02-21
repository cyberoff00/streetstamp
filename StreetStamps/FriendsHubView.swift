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
    case handle
    case qrToken

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inviteCode: return L10n.t("friends_add_method_invite")
        case .handle: return L10n.t("friends_add_method_handle")
        case .qrToken: return L10n.t("friends_add_method_qr")
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    @State private var tab: FriendsTopTab = .activity
    @State private var showAddFriendSheet = false
    @State private var loadingRemote = false
    @State private var activeRoute: FriendsRoute?
    @State private var toastText = ""
    @State private var showToast = false

    private var sortedFriends: [FriendProfileSnapshot] {
        socialStore.friends.sorted { lhs, rhs in
            lastActiveDate(of: lhs) > lastActiveDate(of: rhs)
        }
    }

    private var feedEvents: [FriendFeedEvent] {
        buildFeedEvents(from: sortedFriends)
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
                        if sortedFriends.isEmpty {
                            emptyState(L10n.t("friends_empty_all"))
                        } else {
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
                .padding(.bottom, 30)
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
        .sheet(isPresented: $showAddFriendSheet) {
            AddFriendSheet {
                await refreshRemoteFriends()
            }
            .environmentObject(socialStore)
            .environmentObject(sessionStore)
        }
        .overlay(alignment: .top) {
            if showToast {
                Text(toastText)
                    .font(.system(size: 12, weight: .bold))
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                    Text("BACK")
                        .font(.system(size: 14, weight: .black))
                        .tracking(0.3)
                }
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.t("friends_title"))
                .font(.system(size: 32, weight: .black))
                .tracking(-0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            if tab == .allFriends {
                Button {
                    showAddFriendSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.white.opacity(0.92))
    }

    private var tabSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(FriendsTopTab.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        tab = item
                    }
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(tab == item ? .white : FigmaTheme.subtext)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule()
                                .fill(tab == item ? FigmaTheme.primary : Color.clear)
                                .shadow(
                                    color: tab == item ? FigmaTheme.primary.opacity(0.22) : .clear,
                                    radius: 10,
                                    x: 0,
                                    y: 6
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.white.opacity(0.92))
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
            let publicJourneys = friend.journeys
                .filter { $0.visibility == .public }
                .sorted {
                    feedTimestamp(for: $0) > feedTimestamp(for: $1)
                }

            guard !publicJourneys.isEmpty else { continue }

            let firstJourneyByCity: [String: String] = {
                var map: [String: String] = [:]
                let ascending = publicJourneys.sorted {
                    feedTimestamp(for: $0) < feedTimestamp(for: $1)
                }
                for journey in ascending {
                    let cityKey = normalizeCityKey(journey.title)
                    guard !cityKey.isEmpty, map[cityKey] == nil else { continue }
                    map[cityKey] = journey.id
                }
                return map
            }

            for journey in publicJourneys.prefix(12) {
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
                    eventTitle = String(format: L10n.t("friends_event_visited"), cityName.isEmpty ? "Unknown City" : cityName)
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

    @MainActor
    private func refreshRemoteFriends() async {
        guard !loadingRemote else { return }
        loadingRemote = true
        defer { loadingRemote = false }
        await socialStore.reloadFromBackendIfPossible(accessToken: sessionStore.currentAccessToken)
        await pollUnreadNotifications()
    }

    @MainActor
    private func pollUnreadNotifications() async {
        guard BackendConfig.isEnabled,
              let token = sessionStore.currentAccessToken,
              !token.isEmpty else { return }
        do {
            let unread = try await BackendAPIClient.shared.fetchNotifications(token: token, unreadOnly: true)
            guard !unread.isEmpty else { return }

            let likeItems = unread.filter { $0.type == "journey_like" }
            if let latest = likeItems.sorted(by: { $0.createdAt > $1.createdAt }).first {
                toastText = latest.message
                withAnimation(.easeInOut(duration: 0.2)) {
                    showToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showToast = false
                    }
                }
            }

            try? await BackendAPIClient.shared.markNotificationsRead(
                token: token,
                ids: unread.map(\.id)
            )
        } catch {
            // Keep social feed resilient even if reminder endpoint fails.
        }
    }
}

private struct FriendActivityCard: View {
    let friend: FriendProfileSnapshot
    let event: FriendFeedEvent
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
        if delta < 3600 { return "\(max(1, delta / 60))m ago".uppercased() }
        if delta < 86400 { return "\(max(1, delta / 3600))h ago".uppercased() }
        if delta < 7 * 86400 { return "\(max(1, delta / 86400))d ago".uppercased() }
        return "\(max(1, delta / (7 * 86400)))w ago".uppercased()
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
                            .font(.system(size: 15, weight: .black))
                        Spacer(minLength: 4)
                        Text(agoText)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
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

            HStack(spacing: 10) {
                Text(badgeLabel)
                    .font(.system(size: 12, weight: .black))
                    .tracking(0.6)
                    .foregroundColor(badgeTextColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(badgeColor)
                    .clipShape(Capsule())

                if !event.meta.isEmpty {
                    Text(event.meta)
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(FigmaTheme.subtext)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .padding(18)
        .figmaSurfaceCard(radius: 32)
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onTapGesture(perform: onOpenEvent)
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
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.black)
                Text(activeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(FigmaTheme.subtext)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(distanceLabel)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.black)
                Text(cityLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
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

    @State private var method: AddFriendMethod = .handle
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

                Button(submitting ? L10n.t("friends_add_submitting") : L10n.t("friends_add_submit")) {
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
        case .handle: return "输入好友 handle（支持带或不带 @）"
        case .qrToken: return "粘贴二维码 token 或链接"
        }
    }

    private var canSubmit: Bool {
        if submitting { return false }
        switch method {
        case .handle:
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
        case .handle:
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
        if raw.hasPrefix("@") { return raw }
        return "@\(raw)"
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
                handle: method == .handle ? normalizedHandleInput() : nil,
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

    let friendID: String

    @State private var friend: FriendProfileSnapshot?

    private var fallbackFriend: FriendProfileSnapshot {
        FriendProfileSnapshot(
            id: friendID,
            handle: "@unknown",
            inviteCode: "",
            profileVisibility: .private,
            displayName: "Unknown",
            bio: "",
            loadout: .defaultBoy,
            stats: .init(totalJourneys: 0, totalDistance: 0, totalMemories: 0, totalUnlockedCities: 0),
            journeys: [],
            unlockedCityCards: [],
            createdAt: Date()
        )
    }

    var body: some View {
        let f = friend ?? fallbackFriend

        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(f.displayName)
                    .font(.system(size: 20, weight: .bold))

                Spacer()

                Color.clear.frame(width: 44)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            RobotRendererView(size: 92, face: .front, loadout: f.loadout)
                                .frame(width: 130, height: 130)
                                .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                            NavigationLink(value: FriendsRoute.equipment(friendID)) {
                                Image(systemName: "tshirt.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .offset(x: 8, y: -8)
                        }

                        Text(f.displayName)
                            .font(.system(size: 18, weight: .bold))
                        Text(f.handle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.black.opacity(0.55))
                        if !f.bio.isEmpty {
                            Text(f.bio)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black.opacity(0.65))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    HStack(spacing: 10) {
                        ProfileStatChip(title: "Journeys", value: "\(f.stats.totalJourneys)")
                        ProfileStatChip(title: "Distance", value: "\(Int((f.stats.totalDistance / 1000.0).rounded()))km")
                        ProfileStatChip(title: "Cities", value: "\(f.stats.totalUnlockedCities)")
                    }

                    HStack(spacing: 10) {
                        NavigationLink(value: FriendsRoute.cities(friendID)) {
                            FriendEntryCard(
                                icon: "map",
                                title: "CITY LIBRARY",
                                subtitle: "好友城市卡片（只读）"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: FriendsRoute.journeys(friendID)) {
                            FriendEntryCard(
                                icon: "point.topleft.down.curvedto.point.bottomright.up",
                                title: "JOURNEY ROUTES",
                                subtitle: "筛选公开/好友可见线路"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink(value: FriendsRoute.publicMemories(friendID)) {
                        FriendSectionLink(title: "Public Journey Memories", subtitle: "仅查看公开旅程的 memory 内容")
                    }
                    .buttonStyle(.plain)

                    if sessionStore.isLoggedIn {
                        Button(role: .destructive) {
                            Task {
                                try? await socialStore.removeFriendSmart(friendID, accessToken: sessionStore.currentAccessToken)
                                dismiss()
                            }
                        } label: {
                            Text(L10n.t("friends_delete"))
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Color(red: 251.0/255.0, green: 251.0/255.0, blue: 249.0/255.0).ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            friend = socialStore.friends.first(where: { $0.id == friendID })
            await socialStore.refreshFriendProfileIfPossible(friendID: friendID, accessToken: sessionStore.currentAccessToken)
            friend = socialStore.friends.first(where: { $0.id == friendID })
        }
        .onReceive(socialStore.$friends) { snapshots in
            friend = snapshots.first(where: { $0.id == friendID })
        }
    }
}

private struct ProfileStatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .black))
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FriendSectionLink: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .black))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.55))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black.opacity(0.35))
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FriendEntryCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.black.opacity(0.82))
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundColor(.black)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.55))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FriendJourneysScreen: View {
    private enum VisibilityFilter: String, CaseIterable, Identifiable {
        case all
        case `public`
        case friendsOnly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "全部"
            case .public: return "公开"
            case .friendsOnly: return "好友可见"
            }
        }
    }

    @EnvironmentObject private var socialStore: SocialGraphStore
    let friendID: String
    @State private var filter: VisibilityFilter = .all

    var body: some View {
        let friend = socialStore.friends.first(where: { $0.id == friendID })
        let allJourneys = friend?.journeys.sorted {
            ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast)
        } ?? []
        let journeys: [FriendSharedJourney]
        switch filter {
        case .all:
            journeys = allJourneys
        case .public:
            journeys = allJourneys.filter { $0.visibility == .public }
        case .friendsOnly:
            journeys = allJourneys.filter { $0.visibility == .friendsOnly }
        }

        VStack(spacing: 0) {
            Picker("可见度", selection: $filter) {
                ForEach(VisibilityFilter.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 10) {
                    if journeys.isEmpty {
                        Text("这个筛选下暂无可见线路")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    }

                    ForEach(journeys) { journey in
                        NavigationLink(value: FriendsRoute.journey(friendID: friendID, journeyID: journey.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(journey.title)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.black)
                                    Text(journey.visibility.titleCN)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.55))
                                }
                                Spacer()
                                Text(String(format: "%.1fkm", journey.distance / 1000.0))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .background(Color(red: 251.0/255.0, green: 251.0/255.0, blue: 249.0/255.0).ignoresSafeArea())
        .navigationTitle(L10n.t("journeys_title"))
    }
}

private struct FriendCitiesScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    let friendID: String

    var body: some View {
        let friend = socialStore.friends.first(where: { $0.id == friendID })
        let cards = friend?.unlockedCityCards ?? []

        List(cards) { card in
            HStack {
                Text(card.name)
                Spacer()
                Text(card.countryISO2 ?? "")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(L10n.t("cities_title"))
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

    var body: some View {
        if let friend {
            ScrollView {
                VStack(spacing: 12) {
                    RobotRendererView(size: 150, face: .front, loadout: friend.loadout)
                        .frame(width: 180, height: 180)
                        .background(Color(red: 227.0/255.0, green: 239.0/255.0, blue: 235.0/255.0))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        FriendEquipmentRow(title: "Hair", value: equippedName(categoryID: "hair", itemID: friend.loadout.hairId))
                        FriendEquipmentRow(title: "Outfit", value: equippedName(categoryID: "outfit", itemID: friend.loadout.outfitId))
                        FriendEquipmentRow(title: "Accessory", value: equippedName(categoryID: "accessory", itemID: friend.loadout.accessoryId))
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
}

private struct FriendEquipmentRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
        }
        .padding(.vertical, 4)
    }
}

private struct FriendPublicMemoriesScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    let friendID: String

    private struct PublicMemoryItem: Identifiable {
        let id: String
        let journeyTitle: String
        let memory: FriendSharedMemory
    }

    private var items: [PublicMemoryItem] {
        guard let friend = socialStore.friends.first(where: { $0.id == friendID }) else { return [] }
        return friend.journeys
            .filter { $0.visibility == .public }
            .flatMap { journey in
                journey.memories.map {
                    PublicMemoryItem(id: "\(journey.id)_\($0.id)", journeyTitle: journey.title, memory: $0)
                }
            }
            .sorted { $0.memory.timestamp > $1.memory.timestamp }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if items.isEmpty {
                    Text("暂无公开旅程记忆")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                }

                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.memory.title.isEmpty ? "Untitled" : item.memory.title)
                            .font(.system(size: 14, weight: .bold))
                        Text(item.journeyTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black.opacity(0.5))
                        if !item.memory.notes.isEmpty {
                            Text(item.memory.notes)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black.opacity(0.68))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(12)
        }
        .background(Color(red: 251.0/255.0, green: 251.0/255.0, blue: 249.0/255.0).ignoresSafeArea())
        .navigationTitle("Public Memories")
    }
}

private struct FriendJourneyRouteScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore

    let friendID: String
    let journeyID: String

    @State private var likeCount: Int = 0
    @State private var likedByMe: Bool = false
    @State private var likesLoading = false

    private var friend: FriendProfileSnapshot? {
        socialStore.friends.first(where: { $0.id == friendID })
    }

    private var journey: FriendSharedJourney? {
        friend?.journeys.first(where: { $0.id == journeyID })
    }

    private var journeyPathCoordinates: [CLLocationCoordinate2D] {
        (journey?.routeCoordinates ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var body: some View {
        Group {
            if let friend, let journey {
                ScrollView {
                    VStack(spacing: 12) {
                        FriendJourneyMapPreview(coords: journeyPathCoordinates)
                            .frame(height: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(journey.title)
                                .font(.system(size: 18, weight: .black))
                            HStack(spacing: 8) {
                                Text(friend.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.black.opacity(0.7))
                                Text(journey.visibility.titleCN)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.07))
                                    .clipShape(Capsule())
                            }
                            HStack(spacing: 10) {
                                Button {
                                    Task { await toggleLike() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: likedByMe ? "heart.fill" : "heart")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(likedByMe ? .red : .black.opacity(0.7))
                                        Text("\(likeCount)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.black.opacity(0.72))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.06))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(likesLoading || !sessionStore.isLoggedIn)

                                if likesLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            Text(String(format: "%.2fkm", journey.distance / 1000.0))
                                .font(.system(size: 13, weight: .semibold))
                            if let mem = journey.overallMemory, !mem.isEmpty {
                                Text(mem)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.black.opacity(0.65))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("journey_memories"))
                                .font(.system(size: 14, weight: .black))

                            if journey.memories.isEmpty {
                                Text(L10n.t("no_memories_yet"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(journey.memories) { memory in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(memory.title.isEmpty ? "Untitled" : memory.title)
                                            .font(.system(size: 14, weight: .bold))
                                        if !memory.notes.isEmpty {
                                            Text(memory.notes)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.black.opacity(0.65))
                                        }

                                        if !memory.imageURLs.isEmpty {
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 8) {
                                                    ForEach(memory.imageURLs, id: \.self) { url in
                                                        AsyncImage(url: URL(string: url)) { phase in
                                                            switch phase {
                                                            case .empty:
                                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                                    .fill(Color.black.opacity(0.05))
                                                                    .frame(width: 120, height: 90)
                                                            case .success(let image):
                                                                image
                                                                    .resizable()
                                                                    .scaledToFill()
                                                                    .frame(width: 120, height: 90)
                                                                    .clipped()
                                                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                            case .failure:
                                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                                    .fill(Color.black.opacity(0.05))
                                                                    .frame(width: 120, height: 90)
                                                                    .overlay(Image(systemName: "photo"))
                                                            @unknown default:
                                                                EmptyView()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                }
                .background(Color(red: 251.0/255.0, green: 251.0/255.0, blue: 249.0/255.0).ignoresSafeArea())
                .navigationTitle(L10n.t("journey_route_title"))
                .task {
                    await loadLikeState()
                }
            } else {
                Text(L10n.t("content_unavailable"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    @MainActor
    private func loadLikeState() async {
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        guard BackendConfig.isEnabled else { return }
        do {
            let stats = try await BackendAPIClient.shared.fetchJourneyLikeStats(
                token: token,
                journeyIDs: [journeyID],
                ownerUserID: friendID
            )
            if let item = stats[journeyID] {
                likeCount = item.likes
                likedByMe = item.likedByMe
            }
        } catch {
            // Keep page readable if like meta request fails.
        }
    }

    @MainActor
    private func toggleLike() async {
        guard !likesLoading else { return }
        guard let token = sessionStore.currentAccessToken, !token.isEmpty else { return }
        guard BackendConfig.isEnabled else { return }
        likesLoading = true
        defer { likesLoading = false }

        do {
            if likedByMe {
                let resp = try await BackendAPIClient.shared.unlikeJourney(
                    token: token,
                    ownerUserID: friendID,
                    journeyID: journeyID
                )
                likeCount = max(0, resp.likes)
                likedByMe = resp.likedByMe
            } else {
                let resp = try await BackendAPIClient.shared.likeJourney(
                    token: token,
                    ownerUserID: friendID,
                    journeyID: journeyID
                )
                likeCount = max(0, resp.likes)
                likedByMe = resp.likedByMe
            }
        } catch {
            // Ignore one-off action failures to keep interaction smooth.
        }
    }
}

private struct FriendJourneyMapPreview: UIViewRepresentable {
    let coords: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)

        guard coords.count > 1 else {
            if let only = coords.first {
                let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                map.setRegion(MKCoordinateRegion(center: only, span: span), animated: false)
            }
            return
        }

        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(polyline)
        map.delegate = context.coordinator

        let rect = polyline.boundingMapRect
        let padding = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        map.setVisibleMapRect(rect, edgePadding: padding, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemTeal
            renderer.lineWidth = 4
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}
