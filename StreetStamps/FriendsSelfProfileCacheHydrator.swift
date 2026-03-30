import Foundation

enum FriendsSelfProfileCacheHydrator {
    static func resolve(
        currentRemoteProfile: BackendProfileDTO?,
        cachedProfile: BackendProfileDTO?,
        didSeedFromCache: Bool
    ) -> (profile: BackendProfileDTO?, didSeedFromCache: Bool) {
        guard !didSeedFromCache,
              currentRemoteProfile == nil,
              let cachedProfile else {
            return (currentRemoteProfile, didSeedFromCache)
        }

        return (cachedProfile, true)
    }
}
