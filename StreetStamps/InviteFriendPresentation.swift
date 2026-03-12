import Foundation

struct InviteFriendPresentation: Equatable {
    let displayName: String
    let exclusiveID: String
    let inviteCode: String

    var titleText: String {
        displayName.uppercased()
    }

    var codeText: String {
        inviteCode
    }

    var visibleExclusiveIDText: String? {
        nil
    }
}
