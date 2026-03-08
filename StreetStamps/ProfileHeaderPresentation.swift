import Foundation

enum ProfileHeaderPresentation {
    static func showsNotificationCloud(notificationCount: Int) -> Bool {
        notificationCount > 0
    }

    static func levelHelpText(remainingJourneys: Int) -> String {
        "还差 \(max(0, remainingJourneys)) 段旅程升级"
    }
}
