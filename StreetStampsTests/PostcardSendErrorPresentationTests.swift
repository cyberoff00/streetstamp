import XCTest
@testable import StreetStamps

final class PostcardSendErrorPresentationTests: XCTestCase {
    func test_friendQuotaExceeded_usesLocalizedProductCopy() {
        let error = BackendAPIError.serverCode("city_friend_quota_exceeded", "postcard quota exceeded")

        let english = PostcardSendErrorPresentation.message(for: error) { key in
            switch key {
            case "postcard_quota_friend_limit_reached":
                return "You've reached this friend's postcard limit for the city. Start more journeys here to unlock more postcard quota."
            case "postcard_send_failed":
                return "Send failed. Please try again."
            default:
                return key
            }
        }
        let chinese = PostcardSendErrorPresentation.message(for: error) { key in
            switch key {
            case "postcard_quota_friend_limit_reached":
                return "这位好友在这座城市的明信片额度已经满了，开启更多旅程即可解锁更多明信片额度。"
            case "postcard_send_failed":
                return "发送失败，请稍后重试。"
            default:
                return key
            }
        }

        XCTAssertEqual(english, "You've reached this friend's postcard limit for the city. Start more journeys here to unlock more postcard quota.")
        XCTAssertEqual(chinese, "这位好友在这座城市的明信片额度已经满了，开启更多旅程即可解锁更多明信片额度。")
    }

    func test_cityQuotaExceeded_usesLocalizedProductCopy() {
        let error = BackendAPIError.serverCode("city_total_quota_exceeded", "postcard quota exceeded")

        let english = PostcardSendErrorPresentation.message(for: error) { key in
            switch key {
            case "postcard_quota_city_limit_reached":
                return "This city's postcard quota is full. Start more journeys here to unlock more postcard quota."
            case "postcard_send_failed":
                return "Send failed. Please try again."
            default:
                return key
            }
        }

        XCTAssertEqual(english, "This city's postcard quota is full. Start more journeys here to unlock more postcard quota.")
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
