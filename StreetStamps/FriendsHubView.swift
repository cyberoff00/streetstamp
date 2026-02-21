import SwiftUI
import UIKit
import MapKit

private enum FriendsTopTab: String, CaseIterable, Identifiable {
    case activity
    case allFriends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "ACTIVITY FEED"
        case .allFriends: return "ALL FRIENDS"
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
        case .inviteCode: return "邀请码"
        case .handle: return "Handle"
        case .qrToken: return "二维码"
        }
    }
}

private enum FriendsRoute: Hashable, Identifiable {
    case profile(String)
    case journeys(String)
    case cities(String)
    case journey(friendID: String, journeyID: String)

    var id: String {
        switch self {
        case .profile(let friendID):
            return "profile_\(friendID)"
        case .journeys(let friendID):
            return "journeys_\(friendID)"
        case .cities(let friendID):
            return "cities_\(friendID)"
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

            Divider().overlay(Color.black.opacity(0.08))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if tab == .activity {
                        if feedEvents.isEmpty {
                            emptyState("还没有好友动态")
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
                            emptyState("还没有好友，点击右上角 + 添加")
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
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 24)
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
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("BACK")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("FRIENDS")
                .appHeaderStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            if tab == .allFriends {
                Button {
                    showAddFriendSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 34, height: 34)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(FigmaTheme.background)
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
                        .appBodyStrongStyle()
                        .foregroundColor(tab == item ? .white : Color.black.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Capsule()
                                .fill(tab == item ? FigmaTheme.primary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 14)
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
        return "Active \(shortAgoText(from: date).lowercased())"
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
            let sortedJourneys = friend.journeys.sorted {
                ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast)
            }

            if let latestJourney = sortedJourneys.first {
                let eventDate = latestJourney.endTime ?? latestJourney.startTime ?? friend.createdAt
                let city = friend.unlockedCityCards.first?.name ?? latestJourney.title
                events.append(
                    FriendFeedEvent(
                        id: "journey_\(friend.id)_\(latestJourney.id)",
                        kind: .journey,
                        friendID: friend.id,
                        timestamp: eventDate,
                        journeyID: latestJourney.id,
                        title: "Completed \(latestJourney.title)",
                        location: city,
                        meta: "\(formatDistance(latestJourney.distance))  \(formatDuration(start: latestJourney.startTime, end: latestJourney.endTime))"
                    )
                )

                let memoryCount = latestJourney.memories.count
                if memoryCount > 0 {
                    let photos = latestJourney.memories.reduce(0) { $0 + $1.imageURLs.count }
                    events.append(
                        FriendFeedEvent(
                            id: "memory_\(friend.id)_\(latestJourney.id)",
                            kind: .memory,
                            friendID: friend.id,
                            timestamp: eventDate.addingTimeInterval(-120),
                            journeyID: latestJourney.id,
                            title: "Added \(memoryCount) new memories",
                            location: city,
                            meta: "\(max(photos, memoryCount)) photos"
                        )
                    )
                }
            }

            if let city = friend.unlockedCityCards.first {
                events.append(
                    FriendFeedEvent(
                        id: "city_\(friend.id)_\(city.id)",
                        kind: .city,
                        friendID: friend.id,
                        timestamp: friend.createdAt.addingTimeInterval(-240),
                        journeyID: nil,
                        title: "Visited \(city.name)",
                        location: city.countryISO2 ?? "",
                        meta: ""
                    )
                )
            }
        }

        return events.sorted { $0.timestamp > $1.timestamp }
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
        case .journey: return "JOURNEY"
        case .memory: return "MEMORY"
        case .city: return "CITY"
        }
    }

    private var agoText: String {
        let delta = max(1, Int(Date().timeIntervalSince(event.timestamp)))
        if delta < 3600 { return "\(max(1, delta / 60))M AGO" }
        if delta < 86400 { return "\(max(1, delta / 3600))H AGO" }
        if delta < 7 * 86400 { return "\(max(1, delta / 86400))D AGO" }
        return "\(max(1, delta / (7 * 86400)))W AGO"
    }

    var body: some View {
        Button(action: onOpenEvent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: onOpenProfile) {
                        RobotRendererView(size: 38, face: .front, loadout: friend.loadout)
                            .frame(width: 62, height: 62)
                            .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(friend.displayName)
                                .font(.system(size: 16, weight: .bold))
                            Spacer(minLength: 4)
                            Text(agoText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black.opacity(0.55))
                        }
                        Text(event.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black.opacity(0.68))
                            .lineLimit(2)

                        if !event.location.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "location")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(event.location)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.black.opacity(0.58))
                        }
                    }
                }

                HStack {
                    HStack(spacing: 8) {
                        Text(badgeLabel)
                            .font(.system(size: 11, weight: .semibold))
                        if !event.meta.isEmpty {
                            Text(event.meta)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black.opacity(0.62))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(badgeColor)
                    .clipShape(Capsule())
                    .foregroundColor(badgeTextColor)

                    Spacer()
                }
            }
            .padding(16)
            .figmaSurfaceCard(radius: 32)
        }
        .buttonStyle(.plain)
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
            RobotRendererView(size: 38, face: .front, loadout: friend.loadout)
                .frame(width: 62, height: 62)
                .background(Color(red: 227.0 / 255.0, green: 239.0 / 255.0, blue: 235.0 / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                Text(activeText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black.opacity(0.55))
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(distanceLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                Text(cityLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(.black.opacity(0.48))
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
                Picker("方式", selection: $method) {
                    ForEach(AddFriendMethod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField(inputPlaceholder, text: $friendCode)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                TextField("好友备注（可选）", text: $friendNote)
                    .textFieldStyle(.roundedBorder)

                Button(submitting ? "添加中..." : "添加好友") {
                    Task {
                        await submit()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("提示", isPresented: $showMessage) {
                Button("好", role: .cancel) {}
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
            message = "添加失败：\(error.localizedDescription)"
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

        VStack(spacing: 14) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("BACK")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(f.displayName)
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Color.clear.frame(width: 60)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        RobotRendererView(size: 92, face: .front, loadout: f.loadout)
                            .frame(width: 130, height: 130)
                            .background(Color(red: 227.0/255.0, green: 239.0/255.0, blue: 235.0/255.0))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

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

                    NavigationLink(value: FriendsRoute.journeys(friendID)) {
                        FriendSectionLink(title: "Journeys", subtitle: "查看好友公开/好友可见旅程")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: FriendsRoute.cities(friendID)) {
                        FriendSectionLink(title: "Cities", subtitle: "查看好友解锁城市卡片")
                    }
                    .buttonStyle(.plain)

                    if sessionStore.isLoggedIn {
                        Button(role: .destructive) {
                            Task {
                                try? await socialStore.removeFriendSmart(friendID, accessToken: sessionStore.currentAccessToken)
                                dismiss()
                            }
                        } label: {
                            Text("删除好友")
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

private struct FriendJourneysScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore
    let friendID: String

    var body: some View {
        let friend = socialStore.friends.first(where: { $0.id == friendID })
        let journeys = friend?.journeys.sorted { ($0.endTime ?? $0.startTime ?? .distantPast) > ($1.endTime ?? $1.startTime ?? .distantPast) } ?? []

        ScrollView {
            VStack(spacing: 10) {
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
        .background(Color(red: 251.0/255.0, green: 251.0/255.0, blue: 249.0/255.0).ignoresSafeArea())
        .navigationTitle("Journeys")
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
        .navigationTitle("Cities")
    }
}

private struct FriendJourneyRouteScreen: View {
    @EnvironmentObject private var socialStore: SocialGraphStore

    let friendID: String
    let journeyID: String

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
                            Text("Journey Memories")
                                .font(.system(size: 14, weight: .black))

                            if journey.memories.isEmpty {
                                Text("暂无记忆")
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
                .navigationTitle("Journey Route")
            } else {
                Text("内容不可见或已不存在")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
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
