import XCTest
@testable import StreetStamps

final class LocationHubCountryResolutionTests: XCTestCase {
    func test_fastGuess_doesNotPromoteCountryISO2WithoutAuthoritativeResolution() {
        var state = LocationHub.CountryResolutionState()

        state.applyFastGuess("CN")

        XCTAssertEqual(state.provisionalISO2, "CN")
        XCTAssertNil(state.renderISO2)
    }

    func test_authoritativeResolution_promotesCountryISO2ForRendering() {
        var state = LocationHub.CountryResolutionState()

        state.applyFastGuess("CN")
        state.applyAuthoritativeISO2("CN")

        XCTAssertEqual(state.provisionalISO2, "CN")
        XCTAssertEqual(state.renderISO2, "CN")
    }

    func test_fastGuess_doesNotClearConfirmedCountryWithoutAuthoritativeUpdate() {
        var state = LocationHub.CountryResolutionState()

        state.applyAuthoritativeISO2("CN")
        state.applyFastGuess(nil)

        XCTAssertNil(state.provisionalISO2)
        XCTAssertEqual(state.renderISO2, "CN")
    }

    func test_authoritativeUpdate_replacesConfirmedCountry() {
        var state = LocationHub.CountryResolutionState()

        state.applyAuthoritativeISO2("CN")
        state.applyFastGuess(nil)
        state.applyAuthoritativeISO2("GB")

        XCTAssertEqual(state.renderISO2, "GB")
    }
}
