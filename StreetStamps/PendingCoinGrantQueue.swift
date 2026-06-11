//
//  PendingCoinGrantQueue.swift
//  StreetStamps
//
//  Durable retry queue for coin grants that failed after the user already
//  paid (IAP coin packs) or earned them (journey rewards). Every entry
//  carries a dedupe token, so replaying it against the idempotent
//  /v1/coins/grant endpoint can never double-credit. CoinService drains the
//  queue on bootstrap/refresh.
//

import Foundation

struct PendingCoinGrant: Codable, Equatable {
    let amount: Int
    let reason: String
    let dedupeToken: String
    let accountUserID: String
}

enum PendingCoinGrantQueue {
    private static let storageKey = "streetstamps.coins.pending_grants.v1"
    private static let maxEntries = 100

    static func load() -> [PendingCoinGrant] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([PendingCoinGrant].self, from: data) else {
            return []
        }
        return entries
    }

    static func enqueue(_ grant: PendingCoinGrant) {
        var entries = load()
        guard !entries.contains(where: { $0.dedupeToken == grant.dedupeToken }) else { return }
        entries.append(grant)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        save(entries)
    }

    static func remove(dedupeToken: String) {
        let entries = load().filter { $0.dedupeToken != dedupeToken }
        save(entries)
    }

    static func entries(forAccount accountID: String) -> [PendingCoinGrant] {
        load().filter { $0.accountUserID == accountID }
    }

    private static func save(_ entries: [PendingCoinGrant]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
