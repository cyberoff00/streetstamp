import Foundation

struct ProfileLoadoutRemoteMerge {
    struct Result: Equatable {
        let appliedLoadout: RobotLoadout?
        let lastSyncedLoadout: RobotLoadout?
        let pendingLocalLoadout: RobotLoadout?
    }

    static func resolve(
        remoteLoadout: RobotLoadout?,
        currentLocal: RobotLoadout,
        lastSynced: RobotLoadout?,
        pendingLocal: RobotLoadout?
    ) -> Result {
        let normalizedCurrent = currentLocal.normalizedForCurrentAvatar()
        let normalizedLastSynced = lastSynced?.normalizedForCurrentAvatar()
        let normalizedPending = pendingLocal?.normalizedForCurrentAvatar()

        guard let normalizedRemote = remoteLoadout?.normalizedForCurrentAvatar() else {
            return Result(
                appliedLoadout: nil,
                lastSyncedLoadout: normalizedLastSynced,
                pendingLocalLoadout: normalizedPending
            )
        }

        if let normalizedPending {
            if normalizedRemote == normalizedPending || normalizedRemote == normalizedCurrent {
                return Result(
                    appliedLoadout: normalizedRemote,
                    lastSyncedLoadout: normalizedRemote,
                    pendingLocalLoadout: nil
                )
            }

            return Result(
                appliedLoadout: nil,
                lastSyncedLoadout: normalizedLastSynced,
                pendingLocalLoadout: normalizedPending
            )
        }

        return Result(
            appliedLoadout: normalizedRemote,
            lastSyncedLoadout: normalizedRemote,
            pendingLocalLoadout: nil
        )
    }
}
