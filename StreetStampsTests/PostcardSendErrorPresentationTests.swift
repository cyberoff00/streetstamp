import XCTest
@testable import StreetStamps

final class PostcardSendErrorPresentationTests: XCTestCase {
    func test_friendQuotaExceeded_usesLocalizedProductCopy() {
        let error = BackendAPIError.serverCode("city_friend_quota_exceeded", "postcard quota exceeded")

        let english = PostcardSendErrorPresentation.message(for: error) { key in
            switch key {
            case "postcard_quota_friend_limit_reached":
                return "You've already sent this friend 2 postcards from this city. Try sending one from another city."
            case "postcard_send_failed":
                return "Send failed. Please try again."
            default:
                return key
            }
        }
        let chinese = PostcardSendErrorPresentation.message(for: error) { key in
            switch key {
            case "postcard_quota_friend_limit_reached":
                return "你已经给这位好友寄过 2 张来自这座城市的明信片了，换个城市再寄一张吧。"
            case "postcard_send_failed":
                return "发送失败，请稍后重试。"
            default:
                return key
            }
        }

        XCTAssertEqual(english, "You've already sent this friend 2 postcards from this city. Try sending one from another city.")
        XCTAssertEqual(chinese, "你已经给这位好友寄过 2 张来自这座城市的明信片了，换个城市再寄一张吧。")
    }

    func test_cityQuotaExceeded_usesLocalizedProductCopy() {
        let error = BackendAPIError.serverCode("city_total_quota_exceeded", "postcard quota exceeded")

        let english = PostcardSendErrorPresentation.message(for: error) { key in
            switch key {
            case "postcard_quota_city_limit_reached":
                return "Postcards from this city have already been sent to 10 friends. Try another city."
            case "postcard_send_failed":
                return "Send failed. Please try again."
            default:
                return key
            }
        }

        XCTAssertEqual(english, "Postcards from this city have already been sent to 10 friends. Try another city.")
    }

    func test_unknownError_fallsBackToGenericSendFailure() {
        let message = PostcardSendErrorPresentation.message(for: BackendAPIError.server("timeout")) { key in
            switch key {
            case "postcard_send_failed":
                return "Send failed. Please try again."
            default:
                return key
            }
        }

        XCTAssertEqual(message, "Send failed. Please try again.")
    }
}
