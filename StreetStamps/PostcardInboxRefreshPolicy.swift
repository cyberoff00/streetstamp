import Foundation

enum PostcardInboxRefreshPolicy {
    static func hasUnseenItems(
        currentSentMessageIDs: [String],
        candidateSentMessageIDs: [String],
        currentReceivedMessageIDs: [String],
        candidateReceivedMessageIDs: [String]
    ) -> Bool {
        let currentSent = Set(currentSentMessageIDs)
        let currentReceived = Set(currentReceivedMessageIDs)

        let hasNewSent = candidateSentMessageIDs.contains { !currentSent.contains($0) }
        let hasNewReceived = candidateReceivedMessageIDs.contains { !currentReceived.contains($0) }
        return hasNewSent || hasNewReceived
    }
}
