import SwiftUI

enum PromptBubbleStyle {
    case plain
    case chat
}

private enum PromptBubbleTailSide {
    case leading
    case trailing
}

struct SofaProfileSceneView: View {
    let state: ProfileSceneInteractionState
    let hostLoadout: RobotLoadout
    let visitorLoadout: RobotLoadout?
    let welcomeText: String
    let postcardPromptText: String?
    let onPostcardPromptTap: (() -> Void)?
    let promptBubbleStyle: PromptBubbleStyle

    init(
        state: ProfileSceneInteractionState,
        hostLoadout: RobotLoadout,
        visitorLoadout: RobotLoadout? = nil,
        welcomeText: String = "Welcome!",
        postcardPromptText: String? = nil,
        onPostcardPromptTap: (() -> Void)? = nil,
        promptBubbleStyle: PromptBubbleStyle = .plain
    ) {
        self.state = state
        self.hostLoadout = hostLoadout
        self.visitorLoadout = visitorLoadout
        self.welcomeText = welcomeText
        self.postcardPromptText = postcardPromptText
        self.onPostcardPromptTap = onPostcardPromptTap
        self.promptBubbleStyle = promptBubbleStyle
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let avatarSize = min(size.width * 0.34, size.height * 0.72)

            ZStack {
                floorPlatform(size: size)
                    .offset(y: size.height * 0.30)

                couch(size: size)
                    .offset(y: size.height * 0.16)

                lamp(size: size)
                    .offset(x: size.width * 0.30, y: -size.height * 0.06)

                if let postcardPromptText {
                    postcardPrompt(text: postcardPromptText)
                        .offset(
                            x: promptBubbleStyle == .chat ? size.width * 0.12 : size.width * 0.16,
                            y: promptBubbleStyle == .chat ? -size.height * 0.15 : -size.height * 0.01
                        )
                }

                characters(size: size, avatarSize: avatarSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .aspectRatio(340.0 / 210.0, contentMode: .fit)
    }

    @ViewBuilder
    private func characters(size: CGSize, avatarSize: CGFloat) -> some View {
        let yOffset = size.height * 0.01

        ZStack(alignment: .top) {
            if state.showsWelcomeBubble {
                promptBubble(
                    text: welcomeText,
                    bold: false,
                    tailSide: .leading
                )
                .offset(
                    x: bubbleX(for: size),
                    y: promptBubbleStyle == .chat ? -size.height * 0.15 : -size.height * 0.05
                )
            }

            ZStack {
                avatarView(loadout: hostLoadout, size: avatarSize)
                    .offset(x: seatX(for: state.hostSeat, in: size), y: yOffset)

                if let visitorSeat = state.visitorSeat, let visitorLoadout {
                    avatarView(loadout: visitorLoadout, size: avatarSize)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .offset(x: seatX(for: visitorSeat, in: size), y: yOffset)
                }
            }
            .offset(y: size.height * 0.03)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: state.visitorSeat)
    }

    @ViewBuilder
    private func postcardPrompt(text: String) -> some View {
        if let onPostcardPromptTap {
            Button(action: onPostcardPromptTap) {
                promptBubble(text: text, bold: false, tailSide: .trailing)
            }
            .buttonStyle(.plain)
        } else {
            promptBubble(text: text, bold: false, tailSide: .trailing)
        }
    }

    private func avatarView(loadout: RobotLoadout, size: CGFloat) -> some View {
        RobotRendererView(size: size, face: .front, loadout: loadout)
            .frame(width: size, height: size)
    }

    private func couch(size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 13.0 / 255.0, green: 148.0 / 255.0, blue: 136.0 / 255.0))
                .frame(width: size.width * 0.58, height: size.height * 0.25)
                .offset(y: -size.height * 0.03)

            Capsule()
                .fill(Color(red: 45.0 / 255.0, green: 212.0 / 255.0, blue: 191.0 / 255.0))
                .frame(width: size.width * 0.64, height: size.height * 0.13)
        }
    }

    private func floorPlatform(size: CGSize) -> some View {
        Capsule()
            .fill(Color(red: 15.0 / 255.0, green: 118.0 / 255.0, blue: 110.0 / 255.0).opacity(0.20))
            .frame(width: size.width * 0.94, height: size.height * 0.20)
            .blur(radius: 2)
    }

    private func lamp(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 24, bottomLeading: 0, bottomTrailing: 0, topTrailing: 24),
                style: .continuous
            )
            .fill(Color(red: 254.0 / 255.0, green: 240.0 / 255.0, blue: 138.0 / 255.0))
            .frame(width: size.width * 0.14, height: size.height * 0.16)
            .shadow(color: Color(red: 253.0 / 255.0, green: 224.0 / 255.0, blue: 71.0 / 255.0).opacity(0.55), radius: 20, x: 0, y: 10)

            Rectangle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 2, height: size.height * 0.28)
                .offset(y: size.height * 0.16)
        }
    }

    @ViewBuilder
    private func promptBubble(text: String, bold: Bool, tailSide: PromptBubbleTailSide) -> some View {
        let bubble = Text(text)
            .font(.system(size: 10, weight: bold ? .bold : .regular))
            .foregroundColor(bold ? .black : Color(red: 75.0 / 255.0, green: 85.0 / 255.0, blue: 99.0 / 255.0))
            .padding(.horizontal, promptBubbleStyle == .chat ? 12 : 10)
            .padding(.vertical, promptBubbleStyle == .chat ? 7 : 6)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: promptBubbleStyle == .chat ? 14 : 10, style: .continuous))
            .shadow(color: Color.black.opacity(promptBubbleStyle == .chat ? 0.10 : 0.08), radius: 8, x: 0, y: 4)

        if promptBubbleStyle == .plain {
            bubble
        } else {
            VStack(alignment: tailSide == .leading ? .leading : .trailing, spacing: -1) {
                bubble

                promptBubbleTail
                    .fill(Color.white)
                    .frame(width: 12, height: 8)
                    .padding(tailSide == .leading ? .leading : .trailing, 12)
                    .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 2)
            }
        }
    }

    private var promptBubbleTail: some Shape {
        PromptBubbleTailShape()
    }

    private func seatX(for seat: ProfileSceneSeat, in size: CGSize) -> CGFloat {
        switch seat {
        case .left:
            return -size.width * 0.16
        case .center:
            return 0
        case .right:
            return size.width * 0.18
        }
    }

    private func bubbleX(for size: CGSize) -> CGFloat {
        switch state.hostSeat {
        case .left:
            return -size.width * 0.18
        case .center:
            return 0
        case .right:
            return size.width * 0.18
        }
    }
}

private struct PromptBubbleTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: 0),
            control: CGPoint(x: rect.width * 0.5, y: rect.height * 0.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.3, y: rect.height),
            control: CGPoint(x: rect.width * 0.86, y: rect.height * 0.96)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: 0),
            control: CGPoint(x: rect.width * 0.06, y: rect.height * 0.7)
        )
        path.closeSubpath()
        return path
    }
}
