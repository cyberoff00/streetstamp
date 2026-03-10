import Foundation

enum PostcardInboxPresentation {
    static func recipientLabel(toDisplayName: String?, toUserID: String) -> String {
        normalizedDisplayName(toDisplayName) ?? toUserID
    }

    static func senderLabel(fromDisplayName: String?, fromUserID: String) -> String {
        normalizedDisplayName(fromDisplayName) ?? fromUserID
    }

    private static func normalizedDisplayName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
