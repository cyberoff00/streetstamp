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

struct ProfileSceneInteractionState: Equatable {
    let hostSeat: ProfileSceneSeat
    let visitorSeat: ProfileSceneSeat?
    let showsWelcomeBubble: Bool
    let showsCTA: Bool
    let isCTAEnabled: Bool
    let ctaTitle: String?
    let postcardPromptText: String?

    static func resolve(
        mode: ProfileSceneMode,
        isViewingOwnFriendProfile: Bool,
        isVisitorSeated: Bool,
        isInteractionInFlight: Bool
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
                postcardPromptText: nil
            )
        case .friendProfile:
            let showsCTA = !isViewingOwnFriendProfile
            let ctaTitle: String?
            let isCTAEnabled: Bool
            let postcardPromptText: String?

            if !showsCTA {
                ctaTitle = nil
                isCTAEnabled = false
                postcardPromptText = nil
            } else if isInteractionInFlight {
                ctaTitle = "坐下中..."
                isCTAEnabled = false
                postcardPromptText = nil
            } else if isVisitorSeated {
                ctaTitle = "已坐下"
                isCTAEnabled = false
                postcardPromptText = "send a postcard?"
            } else {
                ctaTitle = "坐一坐"
                isCTAEnabled = true
                postcardPromptText = nil
            }

            return ProfileSceneInteractionState(
                hostSeat: .left,
                visitorSeat: isVisitorSeated ? .right : nil,
                showsWelcomeBubble: true,
                showsCTA: showsCTA,
                isCTAEnabled: isCTAEnabled,
                ctaTitle: ctaTitle,
                postcardPromptText: postcardPromptText
            )
        }
    }
}
