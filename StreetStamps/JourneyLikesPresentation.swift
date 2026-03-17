import Foundation

enum JourneyMemoryMainLoadPolicy {
    static func shouldLoadOnAppear(hasLoaded: Bool) -> Bool {
        !hasLoaded
    }
}

enum JourneyLikesPresentation {
    static func likers(from notifications: [BackendNotificationItem], journeyID: String) -> [JourneyLiker] {
        notifications
            .filter { $0.type == "journey_like" && $0.journeyID == journeyID }
            .sorted { $0.createdAt > $1.createdAt }
            .reduce(into: [JourneyLiker]()) { partialResult, item in
                let key = item.fromUserID ?? item.fromDisplayName ?? item.id
                guard !partialResult.contains(where: { $0.id == key }) else { return }

                let trimmedName = item.fromDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallbackName = item.fromUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let name = !trimmedName.isEmpty ? trimmedName : (!fallbackName.isEmpty ? fallbackName : L10n.t("unknown"))

                partialResult.append(JourneyLiker(id: key, name: name, likedAt: item.createdAt))
            }
    }
}
