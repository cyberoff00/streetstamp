import CoreLocation
import Foundation

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

struct PassiveLocationProfile: Equatable {
    let desiredAccuracy: CLLocationAccuracy
    let distanceFilter: CLLocationDistance
    let activityType: CLActivityType

    static func profile(for mode: LifelogBackgroundMode) -> PassiveLocationProfile {
        switch mode {
        case .highPrecision:
            return PassiveLocationProfile(
                desiredAccuracy: kCLLocationAccuracyNearestTenMeters,
                distanceFilter: 35,
                activityType: .fitness
            )
        case .lowPrecision:
            return PassiveLocationProfile(
                desiredAccuracy: kCLLocationAccuracyHundredMeters,
                distanceFilter: 70,
                activityType: .otherNavigation
            )
        }
    }
}
