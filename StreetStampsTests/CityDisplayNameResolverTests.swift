import XCTest
@testable import StreetStamps

final class CityDisplayNameResolverTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        LanguagePreference.shared.currentLanguage = nil
    }

    func test_languagePreferenceDisplayLocalePrefersAppLanguageSelection() {
        LanguagePreference.shared.currentLanguage = "en"

        XCTAssertEqual(LanguagePreference.shared.effectiveLocaleIdentifier, "en")
        XCTAssertEqual(LanguagePreference.shared.displayLocale.identifier, "en")
    }

    func test_cityLocalizedNameUsesAppDisplayLanguageInsteadOfSystemLocale() {
        LanguagePreference.shared.currentLanguage = "en"
        let city = City(
            displayName: nil,
            id: "Taipei|TW",
            name: "Taipei",
            countryISO2: "TW",
            journeys: [],
            boundaryPolygon: nil,
            anchor: nil,
            explorations: 1,
            memories: 0,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil,
            reservedLevelRaw: nil,
            reservedParentRegionKey: nil,
            reservedAvailableLevelNames: nil,
            reservedAvailableLevelNamesLocaleID: nil,
            localizedDisplayNameByLocale: [
                "en": "Taipei",
                "zh-Hans": "台北"
            ]
        )

        XCTAssertEqual(city.localizedName, "Taipei")
    }

    func test_cityLevelReconcilePolicy_skipsFreshProfileWhenCachedOptionsExist() {
        XCTAssertFalse(
            CityLevelReconcilePolicy.shouldFetchFreshProfile(
                isLoading: false,
                hasExistingOptions: true
            )
        )
    }

    func test_cityLevelReconcilePolicy_fetchesFreshProfileWhenCachedOptionsMissing() {
        XCTAssertTrue(
            CityLevelReconcilePolicy.shouldFetchFreshProfile(
                isLoading: false,
                hasExistingOptions: false
            )
        )
    }

    func test_cityLevelReconcilePolicy_skipsWhileLoading() {
        XCTAssertFalse(
            CityLevelReconcilePolicy.shouldFetchFreshProfile(
                isLoading: true,
                hasExistingOptions: true
            )
        )
    }

    func test_cityLocalizationDebugTraceIncludesSourceAndLocale() {
        let message = CityLocalizationDebugTrace.displayDecision(
            cityKey: "Taipei|TW",
            locale: Locale(identifier: "zh-Hans"),
            source: "displayCacheByLocaleKey.v2",
            title: "台湾",
            fallbackTitle: "Taiwan",
            chosenLevel: .admin,
            parentRegionKey: "Taiwan Province|TW",
            availableLevelNames: [.admin: "Taiwan"]
        )

        XCTAssertTrue(message.contains("cityKey=Taipei|TW"))
        XCTAssertTrue(message.contains("locale=zh-Hans"))
        XCTAssertTrue(message.contains("source=displayCacheByLocaleKey.v2"))
        XCTAssertTrue(message.contains("chosenLevel=admin"))
    }

    func test_cityDisplayTitlePresentationPrefersCurrentLocaleTitleFromCityKey() {
        let title = CityDisplayTitlePresentation.title(
            cityKey: "Taiwan|TW",
            iso2: "TW",
            fallbackTitle: "Taiwan",
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(title, "台湾")
    }

    func test_cityDisplayTitlePresentationPrefersLocalizedLookupBeforeFallback() {
        let title = CityDisplayTitlePresentation.title(
            cityKey: "Taiwan|TW",
            iso2: "TW",
            fallbackTitle: "Taiwan",
            localizedCityNameByKey: ["Taiwan|TW": "台湾"],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(title, "台湾")
    }

    func test_cityDisplayTitlePresentationFallsBackWhenCityKeyMissing() {
        let title = CityDisplayTitlePresentation.title(
            cityKey: "   ",
            iso2: nil,
            fallbackTitle: "台北"
        )

        XCTAssertEqual(title, "台北")
    }

    func test_displayTitleUsesPreferredAdminLevelForTaiwanInSimplifiedChinese() {
        let parentRegionKey = "resolver-test-tw-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        let title = CityPlacemarkResolver.displayTitle(
            cityKey: "Xinyi Township|TW",
            iso2: "TW",
            fallbackTitle: "Xinyi Township",
            availableLevelNames: [
                .locality: "Xinyi Township",
                .admin: "Taiwan"
            ],
            parentRegionKey: parentRegionKey,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(title, "台湾")
    }

    func test_displayTitleNormalizesHongKongRegionNameInSimplifiedChinese() {
        let parentRegionKey = "resolver-test-hk-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        let title = CityPlacemarkResolver.displayTitle(
            cityKey: "Central and Western District|HK",
            iso2: "HK",
            fallbackTitle: "China Hong Kong SAR",
            availableLevelNames: [
                .subAdmin: "Central and Western District",
                .admin: "Hong Kong"
            ],
            parentRegionKey: parentRegionKey,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(title, "香港")
    }

    func test_displayTitleIgnoresAsciiOnlyLocalizedCacheForChineseWhenLocalizedLevelsExist() {
        let title = CityPlacemarkResolver.displayTitle(
            cityKey: "Shanghai|CN",
            iso2: "CN",
            fallbackTitle: "Shanghai",
            availableLevelNames: [
                .admin: "上海",
                .locality: "上海"
            ],
            localizedDisplayNameByLocale: ["zh_CN": "Shanghai"],
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(title, "上海")
    }

    func test_displayTitleUsesPreferredLevelLocalizedNameWhenLocalizedCacheIsMismatched() {
        let parentRegionKey = "resolver-test-jeju-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        let title = CityPlacemarkResolver.displayTitle(
            cityKey: "Jeju Province|KR",
            iso2: "KR",
            fallbackTitle: "Jeju Province",
            availableLevelNames: [
                .admin: "济州特别自治道",
                .locality: "济州市"
            ],
            parentRegionKey: parentRegionKey,
            preferredLevel: .admin,
            localizedDisplayNameByLocale: ["zh_CN": "Jeju Province"],
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(title, "济州特别自治道")
    }

    func test_displayTitleSelectedLevelOverridesLocalizedCacheTitle() {
        let parentRegionKey = "resolver-test-level-override-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        let title = CityPlacemarkResolver.displayTitle(
            cityKey: "Jeju Province|KR",
            iso2: "KR",
            fallbackTitle: "济州市",
            availableLevelNames: [
                .admin: "济州特别自治道",
                .locality: "济州市"
            ],
            parentRegionKey: parentRegionKey,
            preferredLevel: .admin,
            localizedDisplayNameByLocale: ["zh-Hans": "济州市"],
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(title, "济州特别自治道")
    }

    func test_displayTitleUsesLocalizedLevelWhenLocaleIsChineseEvenWithoutPreferredLevel() {
        let title = CityPlacemarkResolver.displayTitle(
            cityKey: "Shanghai|CN",
            iso2: "CN",
            fallbackTitle: "Shanghai",
            availableLevelNames: [
                .admin: "上海",
                .locality: "上海"
            ],
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(title, "上海")
    }

    func test_displayTitleCanonicalizesRegionStyledCityKeyBeforeUsingLocalizedCache() {
        let title = CityPlacemarkResolver.displayTitle(
            cityKey: "Taiwan|TW",
            iso2: "TW",
            fallbackTitle: "Taiwan",
            localizedDisplayNameByLocale: ["zh_CN": "信义乡"],
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(title, "台湾")
    }

    func test_cityLibraryPrefetchNormalizesEnglishCandidateIntoChineseHierarchyTitle() {
        let city = City(
            displayName: "上海",
            id: "Shanghai|CN",
            name: "Shanghai",
            countryISO2: "CN",
            journeys: [],
            boundaryPolygon: nil,
            anchor: nil,
            explorations: 1,
            memories: 0,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil,
            reservedLevelRaw: CityPlacemarkResolver.CardLevel.admin.rawValue,
            reservedParentRegionKey: "Shanghai|CN",
            reservedAvailableLevelNames: [
                CityPlacemarkResolver.CardLevel.admin.rawValue: "上海",
                CityPlacemarkResolver.CardLevel.locality.rawValue: "上海"
            ],
            reservedAvailableLevelNamesLocaleID: "zh_CN",
            localizedDisplayNameByLocale: ["zh_CN": "Shanghai"]
        )

        let resolved = CityLibraryVM.normalizedPrefetchedDisplayTitle(
            for: city,
            candidateLocalizedTitle: "Shanghai",
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(resolved, "上海")
    }

    func test_cityLibraryPrefetchNormalizesEnglishCandidateIntoChineseAdminTitleForJeju() {
        let city = City(
            displayName: "济州特别自治道",
            id: "Jeju Province|KR",
            name: "Jeju Province",
            countryISO2: "KR",
            journeys: [],
            boundaryPolygon: nil,
            anchor: nil,
            explorations: 1,
            memories: 0,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil,
            reservedLevelRaw: CityPlacemarkResolver.CardLevel.admin.rawValue,
            reservedParentRegionKey: "Jeju Province|KR",
            reservedAvailableLevelNames: [
                CityPlacemarkResolver.CardLevel.admin.rawValue: "济州特别自治道",
                CityPlacemarkResolver.CardLevel.locality.rawValue: "济州市"
            ],
            reservedAvailableLevelNamesLocaleID: "zh_CN",
            localizedDisplayNameByLocale: ["zh_CN": "Jeju Province"]
        )

        let resolved = CityLibraryVM.normalizedPrefetchedDisplayTitle(
            for: city,
            candidateLocalizedTitle: "Jeju Province",
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(resolved, "济州特别自治道")
    }

    func test_stableCityKeyUsesCanonicalLevelNameInsteadOfLocalizedDisplayName() {
        let key = CityPlacemarkResolver.stableCityKey(
            selectedLevel: .admin,
            canonicalAvailableLevels: [
                .admin: "Shanghai",
                .locality: "Shanghai"
            ],
            fallbackCityKey: "Shanghai|CN",
            iso2: "CN"
        )

        XCTAssertEqual(key, "Shanghai|CN")
    }

    func test_preferredStableCityKeyUsesStoredHierarchyPreference() {
        let parentRegionKey = "resolver-preferred-key-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        let key = CityPlacemarkResolver.preferredStableCityKey(
            canonicalResult: ReverseGeocodeService.CanonicalResult(
                cityName: "Xinyi Township",
                iso2: "TW",
                cityKey: "Xinyi Township|TW",
                level: .locality,
                parentRegionKey: parentRegionKey,
                availableLevels: [
                    .locality: "Xinyi Township",
                    .admin: "Taiwan"
                ],
                localeIdentifier: "en_US"
            )
        )

        XCTAssertEqual(key, "Taiwan|TW")
    }

    func test_identityLevelMatchesOriginalCityKeyAgainstAvailableLevels() {
        let level = CityPlacemarkResolver.identityLevel(
            cityKey: "Nanshan District|CN",
            availableLevelNames: [
                .locality: "Nanshan District",
                .subAdmin: "Shenzhen",
                .admin: "Guangdong",
                .country: "China"
            ],
            iso2: "CN"
        )

        XCTAssertEqual(level, .locality)
    }

    func test_identityLevelSupportsRegionStyledKeys() {
        let level = CityPlacemarkResolver.identityLevel(
            cityKey: "Taiwan|TW",
            availableLevelNames: [
                .locality: "Xinyi Township",
                .admin: "Taiwan",
                .country: "China"
            ],
            iso2: "TW"
        )

        XCTAssertEqual(level, .country)
    }

    func test_preferredAvailableLevelNamesRejectsEnglishStoredLabelsForChineseLocale() {
        let labels = CityPlacemarkResolver.preferredAvailableLevelNamesForDisplay(
            [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "London",
                CityPlacemarkResolver.CardLevel.subAdmin.rawValue: "London",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "England"
            ],
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertNil(labels)
    }

    func test_preferredAvailableLevelNamesRejectsChineseStoredLabelsForEnglishLocale() {
        let labels = CityPlacemarkResolver.preferredAvailableLevelNamesForDisplay(
            [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "上海",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "上海"
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertNil(labels)
    }

    func test_preferredAvailableLevelNamesKeepsMatchingLocaleLabels() {
        let labels = CityPlacemarkResolver.preferredAvailableLevelNamesForDisplay(
            [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "上海",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "上海"
            ],
            locale: Locale(identifier: "zh_CN")
        )

        XCTAssertEqual(labels?[.locality], "上海")
        XCTAssertEqual(labels?[.admin], "上海")
    }

    func test_resolvedStableLevelNamesPrefersStoredLabelsWhenLocaleMatches() {
        let labels = CityPlacemarkResolver.resolvedStableLevelNamesForDisplay(
            storedAvailableLevelNamesRaw: [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "济州市",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "济州特别自治道"
            ],
            storedLocaleIdentifier: "zh-Hans",
            freshlyResolvedLevelNames: [
                .locality: "济州市",
                .admin: "济州道"
            ],
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(labels[.locality], "济州市")
        XCTAssertEqual(labels[.admin], "济州特别自治道")
    }

    func test_resolvedStableLevelNamesUsesFreshLabelsWhenLocaleChanged() {
        let labels = CityPlacemarkResolver.resolvedStableLevelNamesForDisplay(
            storedAvailableLevelNamesRaw: [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "Jeju-si",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "Jeju Special Self-Governing Province"
            ],
            storedLocaleIdentifier: "en_US",
            freshlyResolvedLevelNames: [
                .locality: "济州市",
                .admin: "济州特别自治道"
            ],
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(labels[.locality], "济州市")
        XCTAssertEqual(labels[.admin], "济州特别自治道")
    }

    func test_resolvedStableLevelNamesUsesFreshLabelsWhenStoredMissing() {
        let labels = CityPlacemarkResolver.resolvedStableLevelNamesForDisplay(
            storedAvailableLevelNamesRaw: nil,
            storedLocaleIdentifier: nil,
            freshlyResolvedLevelNames: [
                .locality: "济州市",
                .admin: "济州特别自治道"
            ],
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(labels[.locality], "济州市")
        XCTAssertEqual(labels[.admin], "济州特别自治道")
    }

    func test_resolvedStableLevelNamesRefreshesFlattenedStoredLabels() {
        let labels = CityPlacemarkResolver.resolvedStableLevelNamesForDisplay(
            storedAvailableLevelNamesRaw: [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "济州市",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "济州市"
            ],
            storedLocaleIdentifier: "zh-Hans",
            freshlyResolvedLevelNames: [
                .locality: "济州市",
                .admin: "济州特别自治道"
            ],
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(labels[.locality], "济州市")
        XCTAssertEqual(labels[.admin], "济州特别自治道")
    }

    func test_displayCacheScopeChangesWhenPreferredLevelChanges() {
        let parentRegionKey = "resolver-test-scope-\(UUID().uuidString)"

        let initial = CityLevelPreferenceStore.shared.displayCacheScope(for: parentRegionKey)
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)
        let updated = CityLevelPreferenceStore.shared.displayCacheScope(for: parentRegionKey)

        XCTAssertNotEqual(initial, updated)
        XCTAssertEqual(updated, "admin")
    }

    func test_journeyPresentationPrefersLocalizedTitleForMatchingCityKey() {
        let journey = JourneyRoute(
            id: "journey-1",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            cityKey: "Taiwan|TW",
            canonicalCity: "Taiwan",
            coordinates: [
                CoordinateCodable(lat: 23.6978, lon: 120.9605)
            ],
            countryISO2: "TW",
            currentCity: "Xinyi Township",
            cityName: "Xinyi Township",
            startCityKey: "Taiwan|TW",
            endCityKey: "Taiwan|TW"
        )

        let title = JourneyCityNamePresentation.title(
            for: journey,
            localizedCityNameByKey: ["Taiwan|TW": "台湾"]
        )

        XCTAssertEqual(title, "台湾")
    }

    func test_journeyPresentationFallsBackToCachedCityHierarchyWhenLocalizedMapMissing() {
        let parentRegionKey = "resolver-test-journey-\(UUID().uuidString)"
        CityLevelPreferenceStore.shared.setPreferredLevel(.admin, for: parentRegionKey)

        let journey = JourneyRoute(
            id: "journey-2",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            cityKey: "Xinyi Township|TW",
            canonicalCity: "Xinyi Township",
            coordinates: [
                CoordinateCodable(lat: 23.6978, lon: 120.9605)
            ],
            countryISO2: "TW",
            currentCity: "Xinyi Township",
            cityName: "Xinyi Township",
            startCityKey: "Xinyi Township|TW",
            endCityKey: "Xinyi Township|TW"
        )
        let cachedCity = CachedCity(
            id: "Xinyi Township|TW",
            name: "Xinyi Township",
            countryISO2: "TW",
            journeyIds: [],
            explorations: 1,
            memories: 0,
            boundary: nil,
            anchor: nil,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil,
            reservedLevelRaw: CityPlacemarkResolver.CardLevel.locality.rawValue,
            reservedParentRegionKey: parentRegionKey,
            reservedAvailableLevelNames: [
                CityPlacemarkResolver.CardLevel.locality.rawValue: "Xinyi Township",
                CityPlacemarkResolver.CardLevel.admin.rawValue: "Taiwan"
            ],
            isTemporary: false
        )

        let title = JourneyCityNamePresentation.title(
            for: journey,
            localizedCityNameByKey: [:],
            cachedCitiesByKey: [cachedCity.id: cachedCity],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(title, "Taiwan")
    }

    func test_journeyPresentationExposesParentRegionKeyFromCachedCity() {
        let journey = JourneyRoute(
            id: "journey-3",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_600),
            cityKey: "Taipei|TW",
            canonicalCity: "Taipei",
            coordinates: [],
            countryISO2: "TW",
            currentCity: "Taipei",
            cityName: "Taipei",
            startCityKey: "Taipei|TW",
            endCityKey: "Taipei|TW"
        )
        let cachedCity = CachedCity(
            id: "Taipei|TW",
            name: "Taipei",
            countryISO2: "TW",
            journeyIds: [],
            explorations: 1,
            memories: 0,
            boundary: nil,
            anchor: nil,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil,
            reservedLevelRaw: nil,
            reservedParentRegionKey: "Taiwan Province|TW",
            reservedAvailableLevelNames: nil,
            isTemporary: false
        )

        let parentRegionKey = JourneyCityNamePresentation.parentRegionKey(
            for: journey,
            cachedCitiesByKey: [cachedCity.id: cachedCity]
        )

        XCTAssertEqual(parentRegionKey, "Taiwan Province|TW")
    }

}
