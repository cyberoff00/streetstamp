import Foundation
import SwiftUI

@MainActor
final class UserBlockStore: ObservableObject {
    @Published private(set) var blockedUserIDs: Set<String> = []
    @Published private(set) var blockedUsers: [BlockedUserDTO] = []

    func isBlocked(_ userID: String) -> Bool {
        blockedUserIDs.contains(userID)
    }

    func refresh(accessToken: String?) async {
        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else {
            blockedUserIDs = []
            blockedUsers = []
            return
        }
        do {
            let list = try await BackendAPIClient.shared.fetchBlockedUsers(token: token)
            blockedUsers = list
            blockedUserIDs = Set(list.map(\.id))
        } catch {
            print("[UserBlockStore] refresh failed: \(error)")
        }
    }

    func blockUser(_ userID: String, accessToken: String?) async throws {
        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else {
            throw BackendAPIError.server("not connected")
        }
        try await BackendAPIClient.shared.blockUser(token: token, userID: userID)
        blockedUserIDs.insert(userID)
        if !blockedUsers.contains(where: { $0.id == userID }) {
            blockedUsers.append(BlockedUserDTO(id: userID, displayName: "Unknown", handle: nil))
        }
    }

    func unblockUser(_ userID: String, accessToken: String?) async throws {
        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else {
            throw BackendAPIError.server("not connected")
        }
        try await BackendAPIClient.shared.unblockUser(token: token, userID: userID)
        blockedUserIDs.remove(userID)
        blockedUsers.removeAll { $0.id == userID }
    }

    func submitReport(
        accessToken: String?,
        reportedUserID: String,
        contentType: String = "user",
        contentID: String? = nil,
        reason: String,
        detail: String = ""
    ) async throws {
        guard BackendConfig.isEnabled, let token = accessToken, !token.isEmpty else {
            throw BackendAPIError.server("not connected")
        }
        try await BackendAPIClient.shared.submitReport(
            token: token,
            reportedUserID: reportedUserID,
            contentType: contentType,
            contentID: contentID,
            reason: reason,
            detail: detail
        )
    }
}
