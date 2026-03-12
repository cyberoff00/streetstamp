import CoreLocation
import UIKit
import XCTest
@testable import StreetStamps

final class CityThumbnailPersistenceTests: XCTestCase {
    func test_renderCacheKey_changesWhenAppearanceChanges() {
        let city = makeCity()

        let light = CityThumbnailLoader.renderCacheKey(for: city, appearanceRaw: MapAppearanceStyle.light.rawValue)
        let dark = CityThumbnailLoader.renderCacheKey(for: city, appearanceRaw: MapAppearanceStyle.dark.rawValue)

        XCTAssertNotEqual(light, dark)
    }

    func test_renderCacheKey_changesWhenJourneyContentChanges() {
        let city = makeCity()
        var changed = makeCity()
        changed.journeys[0].thumbnailCoordinates.append(CoordinateCodable(lat: 51.5034, lon: -0.1278))

        let original = CityThumbnailLoader.renderCacheKey(for: city, appearanceRaw: MapAppearanceStyle.dark.rawValue)
        let updated = CityThumbnailLoader.renderCacheKey(for: changed, appearanceRaw: MapAppearanceStyle.dark.rawValue)

        XCTAssertNotEqual(original, updated)
    }

    func test_renderCacheKey_doesNotChangeWhenBoundaryChanges() {
        let city = makeCity()
        var changed = makeCity()
        changed.boundaryPolygon = [
            CLLocationCoordinate2D(latitude: 51.40, longitude: -0.25),
            CLLocationCoordinate2D(latitude: 51.40, longitude: 0.02),
            CLLocationCoordinate2D(latitude: 51.65, longitude: 0.02),
            CLLocationCoordinate2D(latitude: 51.65, longitude: -0.25)
        ]

        let original = CityThumbnailLoader.renderCacheKey(for: city, appearanceRaw: MapAppearanceStyle.dark.rawValue)
        let updated = CityThumbnailLoader.renderCacheKey(for: changed, appearanceRaw: MapAppearanceStyle.dark.rawValue)

        XCTAssertEqual(original, updated)
    }

    func test_renderCacheKey_doesNotChangeWhenAnchorChanges() {
        let city = makeCity()
        var changed = makeCity()
        changed.anchor = CLLocationCoordinate2D(latitude: 51.5200, longitude: -0.1000)

        let original = CityThumbnailLoader.renderCacheKey(for: city, appearanceRaw: MapAppearanceStyle.dark.rawValue)
        let updated = CityThumbnailLoader.renderCacheKey(for: changed, appearanceRaw: MapAppearanceStyle.dark.rawValue)

        XCTAssertEqual(original, updated)
    }

    func test_renderCacheRelativePath_isStableAndSanitized() {
        let key = "render|city/London|dark|abc:123"

        let path = CityThumbnailLoader.renderCacheRelativePath(forKey: key)

        XCTAssertEqual(path, "city_render_city_London_dark_abc_123.jpg")
    }

    func test_renderCacheStore_resolvesPathsWithinItsOwnRoot() throws {
        let root = makeTemporaryDirectory(named: "render-cache-scope")
        let store = CityRenderCacheStore(rootDir: root)
        let key = "render|London|dark|abc"

        let resolved = store.fullPath(forKey: key)

        XCTAssertEqual(resolved, root.appendingPathComponent("city_render_London_dark_abc.jpg").path)
    }

    func test_renderCacheStore_doesNotLeakAcrossRoots() throws {
        let rootA = makeTemporaryDirectory(named: "render-cache-a")
        let rootB = makeTemporaryDirectory(named: "render-cache-b")
        let key = "render|London|dark|abc"
        let image = makeImage()

        let storeA = CityRenderCacheStore(rootDir: rootA)
        storeA.save(image, forKey: key)

        let storeB = CityRenderCacheStore(rootDir: rootB)

        XCTAssertNotNil(storeA.image(forKey: key))
        XCTAssertNil(storeB.image(forKey: key))
    }

    func test_existingPersistentCache_returnsDiskImageWhenMemoryCacheIsEmpty() throws {
        let root = makeTemporaryDirectory(named: "render-cache-disk-hit")
        let store = CityRenderCacheStore(rootDir: root)
        let city = makeCity()
        let key = CityThumbnailLoader.renderCacheKey(for: city, appearanceRaw: MapAppearanceStyle.dark.rawValue)
        let image = makeImage()

        store.save(image, forKey: key)

        let cached = CityThumbnailLoader.existingPersistentCache(
            for: city,
            appearanceRaw: MapAppearanceStyle.dark.rawValue,
            renderCacheStore: store
        )

        XCTAssertNotNil(cached)
    }

    private func makeCity() -> City {
        let journey = JourneyRoute(
            id: "journey-1",
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            distance: 1_200,
            coordinates: [
                CoordinateCodable(lat: 51.5007, lon: -0.1246),
                CoordinateCodable(lat: 51.5014, lon: -0.1419)
            ],
            thumbnailCoordinates: [
                CoordinateCodable(lat: 51.5007, lon: -0.1246),
                CoordinateCodable(lat: 51.5014, lon: -0.1419)
            ],
            countryISO2: "GB",
            currentCity: "London",
            cityName: "London"
        )

        return City(
            displayName: "London",
            id: "London|GB",
            name: "London",
            countryISO2: "GB",
            journeys: [journey],
            boundaryPolygon: [
                CLLocationCoordinate2D(latitude: 51.48, longitude: -0.18),
                CLLocationCoordinate2D(latitude: 51.48, longitude: -0.04),
                CLLocationCoordinate2D(latitude: 51.56, longitude: -0.04),
                CLLocationCoordinate2D(latitude: 51.56, longitude: -0.18)
            ],
            anchor: CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276),
            explorations: 1,
            memories: 0,
            thumbnailBasePath: nil,
            thumbnailRoutePath: nil
        )
    }

    private func makeTemporaryDirectory(named name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
