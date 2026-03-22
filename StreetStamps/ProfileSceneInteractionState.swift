import Foundation

enum ProfileSceneMode {
    case myProfile
    case friendProfile
}

enum ProfileSceneSeat: Equatable {
    case left
    case center
    case right
}

enum ProfileSceneCTAAction: Equatable {
    case sit
    case leave
}

struct ProfileSceneInteractionState: Equatable {
    let hostSeat: ProfileSceneSeat
    let visitorSeat: ProfileSceneSeat?
    let showsWelcomeBubble: Bool
    let showsCTA: Bool
    let isCTAEnabled: Bool
    let ctaTitle: String?
    let ctaAction: ProfileSceneCTAAction?
    let postcardPromptText: String?
    let showsPhotoBooth: Bool

    static func resolve(
        mode: ProfileSceneMode,
        isViewingOwnFriendProfile: Bool,
        isVisitorSeated: Bool,
        isInteractionInFlight: Bool,
        localize: (String) -> String = { L10n.t($0) }
    ) -> ProfileSceneInteractionState {
        switch mode {
        case .myProfile:
            return ProfileSceneInteractionState(
                hostSeat: .center,
                visitorSeat: nil,
                showsWelcomeBubble: false,
                showsCTA: false,
                isCTAEnabled: false,
                ctaTitle: nil,
                ctaAction: nil,
                postcardPromptText: nil,
                showsPhotoBooth: false
            )
        case .friendProfile:
            let showsCTA = !isViewingOwnFriendProfile
            let ctaTitle: String?
            let isCTAEnabled: Bool
            let ctaAction: ProfileSceneCTAAction?
            let postcardPromptText: String?

            if !showsCTA {
                ctaTitle = nil
                isCTAEnabled = false
                ctaAction = nil
                postcardPromptText = nil
            } else if isInteractionInFlight {
                ctaTitle = localize("friend_profile_cta_loading")
                isCTAEnabled = false
                ctaAction = nil
                postcardPromptText = nil
            } else if isVisitorSeated {
                ctaTitle = localize("friend_profile_cta_leave")
                isCTAEnabled = true
                ctaAction = .leave
                postcardPromptText = localize("friends_postcard_prompt")
            } else {
                ctaTitle = localize("friend_profile_cta_idle")
                isCTAEnabled = true
                ctaAction = .sit
                postcardPromptText = nil
            }

            return ProfileSceneInteractionState(
                hostSeat: .left,
                visitorSeat: isVisitorSeated ? .right : nil,
                showsWelcomeBubble: true,
                showsCTA: showsCTA,
                isCTAEnabled: isCTAEnabled,
                ctaTitle: ctaTitle,
                ctaAction: ctaAction,
                postcardPromptText: postcardPromptText,
                showsPhotoBooth: isVisitorSeated && !isViewingOwnFriendProfile
            )
        }
    }
}
