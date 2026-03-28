import XCTest
@testable import StreetStamps

final class CoinPurchaseSheetPresentationTests: XCTestCase {
    func test_contentState_showsLoadingBeforeFirstProductLoadFinishes() {
        XCTAssertEqual(
            CoinPurchaseSheetContentState.resolve(
                hasFinishedInitialLoad: false,
                isLoading: false,
                productsCount: 0
            ),
            .loading
        )
    }

    func test_contentState_showsFallbackWhenFirstLoadFinishesWithoutProducts() {
        XCTAssertEqual(
            CoinPurchaseSheetContentState.resolve(
                hasFinishedInitialLoad: true,
                isLoading: false,
                productsCount: 0
            ),
            .fallback
        )
    }

    func test_contentState_showsProductsWhenStoreKitProductsExist() {
        XCTAssertEqual(
            CoinPurchaseSheetContentState.resolve(
                hasFinishedInitialLoad: true,
                isLoading: false,
                productsCount: 3
            ),
            .products
        )
    }
}
