import Foundation

enum MapNavigationPresentationStyle: Equatable {
    case push
    case modal
}

enum MapNavigationScreen {
    case cityDeepView
    case journeyMemoryDetail
    case friendJourneyDetail
    case standardDetail
}

enum MapNavigationPresentationPolicy {
    static func presentation(for screen: MapNavigationScreen) -> MapNavigationPresentationStyle {
        switch screen {
        case .cityDeepView, .journeyMemoryDetail, .friendJourneyDetail:
            return .modal
        case .standardDetail:
            return .push
        }
    }
}
