import CoreLocation
import Foundation

enum PassiveLocationState: Equatable {
    case moving
    case stationary
}

struct PassiveLocationProfile: Equatable {
    let desiredAccuracy: CLLocationAccuracy
    let distanceFilter: CLLocationDistance
    let activityType: CLActivityType

    static func profile(for state: PassiveLocationState) -> PassiveLocationProfile {
        switch state {
        case .moving:
            return PassiveLocationProfile(
                desiredAccuracy: kCLLocationAccuracyNearestTenMeters,
                distanceFilter: 40,
                activityType: .fitness
            )
        case .stationary:
            return PassiveLocationProfile(
                desiredAccuracy: kCLLocationAccuracyHundredMeters,
                distanceFilter: 80,
                activityType: .otherNavigation
            )
        }
    }
}

enum LocationLifecycleAction: Equatable {
    case requestSingleRefresh
    case startPassive
    case stayIdle
}

enum LocationLifecycleDecision {
    static func idleActivationAction(
        isTrackingJourney: Bool,
        isPassiveEnabled: Bool,
        authorizationStatus: CLAuthorizationStatus
    ) -> LocationLifecycleAction {
        guard !isTrackingJourney else { return .stayIdle }
        guard isPassiveEnabled, authorizationStatus == .authorizedAlways else {
            return .requestSingleRefresh
        }
        return .startPassive
    }

    static func postJourneyAction(
        isPassiveEnabled: Bool,
        authorizationStatus: CLAuthorizationStatus
    ) -> LocationLifecycleAction {
        guard isPassiveEnabled, authorizationStatus == .authorizedAlways else {
            return .stayIdle
        }
        return .startPassive
    }
}

enum MotionActivityPolicy {
    static func shouldRun(
        isTrackingJourney: Bool,
        isPassiveLifelogActive: Bool
    ) -> Bool {
        isTrackingJourney || isPassiveLifelogActive
    }

    static func shouldRun(
        isTrackingJourney: Bool,
        isPassiveLifelogEnabled: Bool,
        authorizationStatus: CLAuthorizationStatus
    ) -> Bool {
        shouldRun(
            isTrackingJourney: isTrackingJourney,
            isPassiveLifelogActive: isPassiveLifelogEnabled && authorizationStatus == .authorizedAlways
        )
    }
}
