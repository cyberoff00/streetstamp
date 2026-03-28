import SwiftUI

/// A light card-like press feedback to mimic "tap-down then spring back".
struct CardPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.95
    var pressedOpacity: Double = 0.92
    var enableHaptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && enableHaptic {
                    Haptics.light()
                }
            }
    }
}
