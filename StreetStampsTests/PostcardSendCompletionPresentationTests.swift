import XCTest
@testable import StreetStamps

final class PostcardSendCompletionPresentationTests: XCTestCase {
    @MainActor
    func test_performOpenSentBox_dismissesThenInvokesCallbackAndPostsNotification() async {
        let center = NotificationCenter()
        let notificationExpectation = expectation(description: "posts sent-box notification")
        let callbackExpectation = expectation(description: "invokes onSent callback")
        var dismissCount = 0

        let observer = center.addObserver(
            forName: .postcardSentGoToInbox,
            object: nil,
            queue: nil
        ) { _ in
            notificationExpectation.fulfill()
        }
        defer { center.removeObserver(observer) }

        PostcardSendCompletionPresentation.performOpenSentBox(
            onSent: {
                callbackExpectation.fulfill()
            },
            dismiss: {
                dismissCount += 1
            },
            notificationCenter: center
        )

        XCTAssertEqual(dismissCount, 1)
        await fulfillment(of: [callbackExpectation, notificationExpectation], timeout: 1.0)
    }

    func test_sentBoxOpenDelay_matchesPreviewTransitionDelay() {
        XCTAssertEqual(PostcardSendCompletionPresentation.sentBoxOpenDelay, 0.35, accuracy: 0.0001)
    }
}
