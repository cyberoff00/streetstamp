import SwiftUI

struct FriendMapCharacterOverlay: View {
    let friendLoadout: RobotLoadout
    let distanceText: String
    @State private var showDoor = false
    @State private var doorOpen = false
    @State private var showBubble = false
    @State private var overlayLayout: FriendMapCharacterOverlayLayout.Layout? = nil
    @State private var myCharacterPosition: CGPoint = .zero
    @State private var myCharacterVisible = false

    var body: some View {
        GeometryReader { geo in
            let layout = overlayLayout ?? FriendMapCharacterOverlayLayout.makeLayout(in: geo.size)
            ZStack {
                friendCharacter
                    .position(layout.friendPosition)

                if showDoor {
                    doorView
                        .position(layout.doorPosition)
                }

                if myCharacterVisible {
                    myCharacter
                        .position(myCharacterPosition)
                }

                if showBubble {
                    distanceBubble
                        .position(layout.bubblePosition)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .onAppear {
                let resolvedLayout = FriendMapCharacterOverlayLayout.makeLayout(in: geo.size)
                overlayLayout = resolvedLayout
                myCharacterPosition = resolvedLayout.myStartPosition
                startAnimation(layout: resolvedLayout)
            }
        }
        .allowsHitTesting(false)
    }

    private var friendCharacter: some View {
        RobotRendererView(size: FriendMapCharacterOverlayLayout.characterSize, face: .front, loadout: friendLoadout)
    }

    private var doorView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.brown.opacity(0.8))
                .frame(width: doorOpen ? 10 : 50, height: 70)
                .offset(x: doorOpen ? -20 : 0)

            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.brown.opacity(0.9), lineWidth: 3)
                .frame(width: 50, height: 70)
        }
    }

    private var myCharacter: some View {
        RobotRendererView(size: FriendMapCharacterOverlayLayout.characterSize, face: .front, loadout: AvatarLoadoutStore.load())
    }

    private var distanceBubble: some View {
        Text("I'm \(distanceText) away from u")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.62))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.9))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
            .fixedSize()
    }

    private func startAnimation(layout: FriendMapCharacterOverlayLayout.Layout) {
        showBubble = false

        withAnimation(.easeInOut(duration: 0.3).delay(0.5)) {
            showDoor = true
        }

        withAnimation(.easeInOut(duration: 0.4).delay(1.0)) {
            doorOpen = true
        }

        withAnimation(.easeInOut(duration: 0.3).delay(1.2)) {
            myCharacterVisible = true
        }

        withAnimation(.easeInOut(duration: 1.5).delay(1.5)) {
            myCharacterPosition = layout.myPosition
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.75).delay(3.15)) {
            showBubble = true
        }
    }
}
