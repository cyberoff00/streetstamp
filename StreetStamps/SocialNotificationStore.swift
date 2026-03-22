import Foundation
import SwiftUI

@MainActor
final class SocialNotificationStore: ObservableObject {
    @Published private(set) var notifications: [BackendNotificationItem] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading = false

    private static let cutoffInterval: TimeInterval = 3 * 24 * 60 * 60
    private static let pollingInterval: UInt64 = 25_000_000_000 // 25 seconds

    private var lastPromptNotificationID: String?

    // MARK: - Fetch

    func refresh(
        token: String?,
        showToastCallback: ((String) -> Void)? = nil
    ) async {
        guard BackendConfig.isEnabled,
              let token, !token.isEmpty else {
            notifications = []
            unreadCount = 0
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let all = try await BackendAPIClient.shared.fetchNotifications(token: token, unreadOnly: false)
            PostcardNotificationBridge.shared.surfaceUnreadPostcardNotifications(all)

            let cutoff = Date().addingTimeInterval(-Self.cutoffInterval)
            let fetched = all
                .filter { SocialNotificationPolicy.supports(type: $0.type) }
                .filter { $0.createdAt >= cutoff }
                .sorted { $0.createdAt > $1.createdAt }

            var mergedByID: [String: BackendNotificationItem] = [:]
            for item in notifications where item.createdAt >= cutoff {
                mergedByID[item.id] = item
            }
            for item in fetched {
                mergedByID[item.id] = item
            }

            let merged = mergedByID.values
                .filter { $0.createdAt >= cutoff }
                .sorted { $0.createdAt > $1.createdAt }
            notifications = merged
            unreadCount = merged.filter { !$0.read }.count

            if let callback = showToastCallback {
                let unread = merged.filter { !$0.read }
                if let latest = unread.first,
                   latest.id != lastPromptNotificationID {
                    callback(SocialNotificationPresentation.message(for: latest))
                    lastPromptNotificationID = latest.id
                }
            }
        } catch {
            // Keep UI resilient; stale data is better than crashing.
        }
    }

    // MARK: - Mark Read

    func markRead(ids: [String], token: String?) async {
        let targetIDs = Array(Set(ids))
        guard !targetIDs.isEmpty,
              BackendConfig.isEnabled,
              let token, !token.isEmpty else { return }

        // Optimistic local update first
        applyReadLocally(ids: targetIDs)

        do {
            try await BackendAPIClient.shared.markNotificationsRead(token: token, ids: targetIDs)
            SocialNotificationReadSync.post(ids: targetIDs, markAll: false)
        } catch {
            // Revert optimistic update on failure by re-fetching
            await refresh(token: token)
        }
    }

    func markAllRead(token: String?) async {
        let unreadIDs = notifications.filter { !$0.read }.map(\.id)
        guard !unreadIDs.isEmpty,
              BackendConfig.isEnabled,
              let token, !token.isEmpty else { return }

        // Optimistic local update
        applyReadLocally(ids: unreadIDs)

        do {
            try await BackendAPIClient.shared.markNotificationsRead(token: token, ids: unreadIDs, markAll: true)
            SocialNotificationReadSync.post(ids: unreadIDs, markAll: true)
        } catch {
            await refresh(token: token)
        }
    }

    func markSingleRead(id: String, token: String?) async {
        guard notifications.contains(where: { $0.id == id && !$0.read }) else { return }
        await markRead(ids: [id], token: token)
    }

    // MARK: - Cross-View Sync

    func applyReadSync(_ notification: Notification) {
        guard let payload = SocialNotificationReadSync.payload(from: notification) else { return }
        notifications = SocialNotificationReadSync.applying(payload, to: notifications)
        unreadCount = notifications.filter { !$0.read }.count
    }

    // MARK: - Internal (test support)

    func setNotifications(_ items: [BackendNotificationItem]) {
        notifications = items
        unreadCount = items.filter { !$0.read }.count
    }

    // MARK: - Private

    private func applyReadLocally(ids: [String]) {
        let idSet = Set(ids)
        notifications = notifications.map { item in
            guard idSet.contains(item.id), !item.read else { return item }
            var copy = item
            copy.read = true
            return copy
        }
        unreadCount = notifications.filter { !$0.read }.count
    }
}
