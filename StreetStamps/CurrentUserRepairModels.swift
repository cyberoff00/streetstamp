import Foundation

enum JourneyRepairSource: Equatable, Codable {
    case deviceGuest(guestID: String)
    case accountCache(accountUserID: String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case kind
        case guestID
        case accountUserID
    }

    private enum Kind: String, Codable {
        case deviceGuest
        case accountCache
        case unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .deviceGuest:
            self = .deviceGuest(guestID: try container.decode(String.self, forKey: .guestID))
        case .accountCache:
            self = .accountCache(accountUserID: try container.decode(String.self, forKey: .accountUserID))
        case .unknown:
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .deviceGuest(let guestID):
            try container.encode(Kind.deviceGuest, forKey: .kind)
            try container.encode(guestID, forKey: .guestID)
        case .accountCache(let accountUserID):
            try container.encode(Kind.accountCache, forKey: .kind)
            try container.encode(accountUserID, forKey: .accountUserID)
        case .unknown:
            try container.encode(Kind.unknown, forKey: .kind)
        }
    }
}

enum JourneyRepairDisposition: Equatable {
    case allow
    case quarantine
}

struct CurrentUserRepairPolicy {
    let activeLocalProfileID: String
    let currentGuestScopedUserID: String
    let currentAccountUserID: String?

    func allows(_ source: JourneyRepairSource) -> Bool {
        disposition(for: source) == .allow
    }

    func disposition(for source: JourneyRepairSource) -> JourneyRepairDisposition {
        switch source {
        case .deviceGuest(let guestID):
            return guestID == normalizedGuestID(fromScopedUserID: currentGuestScopedUserID) ? .allow : .quarantine
        case .accountCache(let accountUserID):
            guard let currentAccountUserID else { return .quarantine }
            return accountUserID == currentAccountUserID ? .allow : .quarantine
        case .unknown:
            return .quarantine
        }
    }

    private func normalizedGuestID(fromScopedUserID scopedUserID: String) -> String {
        if scopedUserID.hasPrefix("guest_") {
            return String(scopedUserID.dropFirst("guest_".count))
        }
        return scopedUserID
    }
}

struct CurrentUserRepairReport: Equatable {
    var allowedJourneyIDs: [String]
    var quarantinedJourneyIDs: [String]
    var missingFromIndexJourneyIDs: [String]
    var orphanedIndexedJourneyIDs: [String]
}

struct CurrentUserRepairResult: Equatable {
    var keptJourneyIDs: [String]
    var quarantinedJourneyIDs: [String]
}
