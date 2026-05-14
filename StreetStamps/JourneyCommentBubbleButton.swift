import SwiftUI

/// Bubble icon used in `JourneyRouteDetailView`'s header to open the comment
/// thread sheet. Shows a red badge dot when there's any unread.
///
/// - `viewer`: simple dot, no number (viewer has at most one thread, the
///   precise count adds no information).
/// - `owner`: dot with a digit, since the count aggregates across multiple
///   friends and the digit tells the owner how many friends are waiting.
struct JourneyCommentBubbleButton: View {
    enum Tone {
        case viewer
        case owner
    }

    let unreadCount: Int
    let tone: Tone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bubble.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .appMinTapTarget()
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        badge
                            .padding(.top, 6)
                            .padding(.trailing, 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("comments"))
    }

    @ViewBuilder
    private var badge: some View {
        switch tone {
        case .viewer:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        case .owner:
            Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.red))
                .overlay(Capsule().stroke(Color.white, lineWidth: 1))
        }
    }
}
