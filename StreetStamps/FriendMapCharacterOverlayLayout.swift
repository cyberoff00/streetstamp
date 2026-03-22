import CoreGraphics

enum FriendMapCharacterOverlayLayout {
    struct Layout: Equatable {
        let doorPosition: CGPoint
        let friendPosition: CGPoint
        let myPosition: CGPoint
        let myStartPosition: CGPoint
        let bubblePosition: CGPoint
    }

    static let characterSize: CGFloat = 72

    static func makeLayout(in size: CGSize) -> Layout {
        let doorPosition = CGPoint(
            x: 92,
            y: size.height - 245
        )
        let friendPosition = CGPoint(
            x: size.width - 84,
            y: 150
        )
        let myPosition = CGPoint(
            x: friendPosition.x - 70,
            y: friendPosition.y
        )
        let myStartPosition = CGPoint(
            x: doorPosition.x,
            y: doorPosition.y - 2
        )
        let bubblePosition = CGPoint(
            x: myPosition.x + 13,
            y: friendPosition.y - 58
        )

        return Layout(
            doorPosition: doorPosition,
            friendPosition: friendPosition,
            myPosition: myPosition,
            myStartPosition: myStartPosition,
            bubblePosition: bubblePosition
        )
    }
}
