import Foundation

enum PostcardSendCompletionPresentation {
    static let sentBoxOpenDelay: TimeInterval = 0.35

    static func performOpenSentBox(
        onSent: (() -> Void)?,
        dismiss: @escaping () -> Void,
        notificationCenter: NotificationCenter = .default
    ) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + sentBoxOpenDelay) {
            onSent?()
            notificationCenter.post(name: .postcardSentGoToInbox, object: nil)
        }
    }
}
