import SwiftUI

/// Hosts `JourneyMemoryDetailView` for an APNs-deep-linked journey when the
/// signed-in user is the journey owner. Reads from the active user's own
/// `JourneyStore` / `CityCache`.
struct OwnerCommentDeepLinkContent: View {
    let link: JourneyCommentDeepLink

    @EnvironmentObject private var journeyStore: JourneyStore
    @EnvironmentObject private var cityCache: CityCache
    @EnvironmentObject private var sessionStore: UserSessionStore

    var body: some View {
        if let journey = journeyStore.journeys.first(where: { $0.id == link.journeyID }) {
            JourneyMemoryDetailView(
                journey: journey,
                memories: journey.memories.sorted { $0.timestamp < $1.timestamp },
                cityName: JourneyCommentDeepLinkHelpers.displayCityName(for: journey, cityCache: cityCache),
                countryName: JourneyCommentDeepLinkHelpers.displayCountryName(for: journey),
                readOnly: false,
                friendLoadout: nil,
                autoPresentCommentSheet: true,
                journeyOwnerID: sessionStore.accountUserID ?? "",
                focusCommentSenderID: link.senderID
            )
        } else {
            JourneyCommentDeepLinkUnavailableView()
        }
    }
}

/// Hosts `JourneyMemoryDetailView` for a friend-owned journey opened from a
/// comment deep link. Mirrors the friend's snapshot into a per-friend
/// `JourneyStore` / `CityCache` via `FriendMirrorContext`, matching the
/// existing FriendsHub friend-detail path so map / cover / memories render
/// fully.
struct FriendCommentDeepLinkContent: View {
    let link: JourneyCommentDeepLink
    private let initialSnapshot: FriendProfileSnapshot?

    @EnvironmentObject private var socialStore: SocialGraphStore
    @EnvironmentObject private var sessionStore: UserSessionStore
    @StateObject private var mirror: FriendMirrorContext

    init(link: JourneyCommentDeepLink, initialSnapshot: FriendProfileSnapshot?) {
        self.link = link
        self.initialSnapshot = initialSnapshot
        // Build the mirror lazily inside the StateObject autoclosure so the
        // heavy work — FriendMirrorContext's directory I/O plus the synchronous
        // full-history `applySync` — runs exactly ONCE, when SwiftUI first
        // creates the StateObject. Constructing `ctx` eagerly here re-ran that
        // work on every SwiftUI re-init of this view, hitching the main thread
        // each time the deep link opened. The async `mirror.apply` in the body
        // still re-syncs from disk afterwards.
        _mirror = StateObject(
            wrappedValue: Self.makeMirror(friendID: link.ownerID, snapshot: initialSnapshot)
        )
    }

    private static func makeMirror(
        friendID: String,
        snapshot: FriendProfileSnapshot?
    ) -> FriendMirrorContext {
        let ctx = FriendMirrorContext(friendID: friendID)
        if let snapshot {
            ctx.applySync(snapshot: snapshot)
        }
        return ctx
    }

    var body: some View {
        Group {
            if let friend = resolvedFriend {
                friendContent(for: friend)
            } else {
                JourneyCommentDeepLinkUnavailableView()
            }
        }
        .task {
            await socialStore.refreshFriendProfileIfPossible(
                friendID: link.ownerID,
                accessToken: sessionStore.currentAccessToken
            )
        }
    }

    private var resolvedFriend: FriendProfileSnapshot? {
        socialStore.friends.first(where: { $0.id == link.ownerID }) ?? initialSnapshot
    }

    @ViewBuilder
    private func friendContent(for friend: FriendProfileSnapshot) -> some View {
        let mirroredJourney = mirror.journeyStore.journeys.first(where: { $0.id == link.journeyID })
        if let journey = mirroredJourney {
            JourneyMemoryDetailView(
                journey: journey,
                memories: journey.memories.sorted { $0.timestamp < $1.timestamp },
                cityName: JourneyCommentDeepLinkHelpers.displayCityName(for: journey, cityCache: mirror.cityCache),
                countryName: JourneyCommentDeepLinkHelpers.displayCountryName(for: journey),
                readOnly: true,
                friendLoadout: friend.loadout,
                autoPresentCommentSheet: true,
                journeyOwnerID: link.ownerID,
                focusCommentSenderID: link.senderID
            )
            // Override the parent app's journey/city stores so the detail
            // view reads the friend's mirrored data, not the active user's.
            .environmentObject(mirror.journeyStore)
            .environmentObject(mirror.cityCache)
            .task(id: FriendMirrorContext.signature(for: friend)) {
                await mirror.apply(snapshot: friend)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: FriendMirrorContext.signature(for: friend)) {
                    await mirror.apply(snapshot: friend)
                }
        }
    }
}

/// Fallback when the deep-linked journey is no longer accessible — e.g. the
/// owner deleted it, the friend was unfriended, or the snapshot hasn't loaded
/// yet on a cold start.
struct JourneyCommentDeepLinkUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)
            Text(L10n.t("content_unavailable"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            Button(L10n.t("done")) { dismiss() }
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(FigmaTheme.background.ignoresSafeArea())
    }
}

@MainActor
enum JourneyCommentDeepLinkHelpers {
    static func displayCityName(for journey: JourneyRoute, cityCache: CityCache) -> String {
        let key = journey.stableCityKey ?? journey.cityKey
        if !key.isEmpty,
           let cached = cityCache.cachedCitiesByKey[key] {
            let title = cached.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        if let name = journey.cityName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return L10n.t("unknown")
    }

    static func displayCountryName(for journey: JourneyRoute) -> String {
        let iso = (journey.countryISO2 ?? "").uppercased()
        guard iso.count == 2 else { return "" }
        return LanguagePreference.shared.displayLocale.localizedString(forRegionCode: iso) ?? iso
    }
}
