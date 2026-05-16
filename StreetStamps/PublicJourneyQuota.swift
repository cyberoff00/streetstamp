//
//  PublicJourneyQuota.swift
//  StreetStamps
//
//  Free-tier quota on how many journeys the user can publish (set to
//  .friendsOnly) from the new-version cutoff onward. Pre-cutoff public
//  journeys are grandfathered and do not count toward the quota.
//
//  Cutoff is sealed lazily on first observation of the new build, so the
//  upgrade path is invisible to existing users with >5 historical public
//  journeys — they keep all of them, and only NEW publishes consume the
//  free allotment.
//

import Foundation

enum PublicJourneyQuota {
    private static let cutoffKey = "streetstamps.public_quota.cutoff"

    /// The first time this is called on a new install of this version, the
    /// current `Date()` is sealed in UserDefaults. Subsequent calls return
    /// the sealed value. Journeys with `sharedAt <= cutoff` are pre-existing
    /// public journeys and never count against the quota.
    @discardableResult
    static func ensureCutoff(now: Date = Date()) -> Date {
        let ud = UserDefaults.standard
        if let ts = ud.object(forKey: cutoffKey) as? Double, ts > 0 {
            return Date(timeIntervalSince1970: ts)
        }
        ud.set(now.timeIntervalSince1970, forKey: cutoffKey)
        return now
    }

    /// Count of distinct journeys this user has published since the cutoff.
    /// "Published" means `sharedAt != nil` — once a journey has been shared
    /// to friends, it consumes a slot for the lifetime of this account on
    /// this device. Toggling it back to private does NOT free the slot, by
    /// design: otherwise a user could publish/unpublish in a loop to bypass
    /// the quota.
    static func usedCount(journeys: [JourneyRoute], cutoff: Date = ensureCutoff()) -> Int {
        var count = 0
        for j in journeys {
            guard let shared = j.sharedAt, shared > cutoff else { continue }
            count += 1
        }
        return count
    }

    /// Whether a free-tier user has hit the free public-journey cap.
    static func isOverFreeLimit(journeys: [JourneyRoute], tier: MembershipTier) -> Bool {
        guard tier == .free else { return false }
        let limit = MembershipTierConfig.maxPublicJourneys(for: tier)
        return usedCount(journeys: journeys) >= limit
    }

    // MARK: Test hook

    /// Used by tests to inject a known cutoff. No production caller should use this.
    static func _setCutoffForTesting(_ date: Date?) {
        let ud = UserDefaults.standard
        if let d = date {
            ud.set(d.timeIntervalSince1970, forKey: cutoffKey)
        } else {
            ud.removeObject(forKey: cutoffKey)
        }
    }
}
