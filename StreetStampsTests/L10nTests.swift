import XCTest
@testable import StreetStamps

final class L10nTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func test_preferredChineseLocaleResolvesToSimplifiedChinese() {
        let localization = L10n.preferredLocalizationName(
            preferredLanguages: ["zh-CN"],
            currentLocale: Locale(identifier: "zh_CN"),
            availableLocalizations: ["en", "zh-Hans", "zh-Hant", "Base"]
        )

        XCTAssertEqual(localization, "zh-Hans")
    }

    func test_traditionalChineseLocaleResolvesToTraditionalChinese() {
        let localization = L10n.preferredLocalizationName(
            preferredLanguages: ["zh-TW"],
            currentLocale: Locale(identifier: "zh_TW"),
            availableLocalizations: ["en", "zh-Hans", "zh-Hant", "Base"]
        )

        XCTAssertEqual(localization, "zh-Hant")
    }

    func test_localizedValueResolvesMixedSimplifiedChineseLocale() throws {
        let bundle = try makeFixtureBundle(localizations: [
            "en": [
                "intro_skip": "Skip"
            ],
            "zh-Hans": [
                "intro_skip": "跳过"
            ]
        ])

        let value = L10n.localizedValue(
            for: "intro_skip",
            preferredLanguages: ["zh-Hans_GB"],
            currentLocale: Locale(identifier: "zh_Hans_GB"),
            bundle: bundle
        )

        XCTAssertEqual(value, "跳过")
    }

    func test_localizedValueFallsBackToEnglishWhenChineseKeyMissing() throws {
        let bundle = try makeFixtureBundle(localizations: [
            "en": [
                "prompt": "Prompt"
            ],
            "zh-Hans": [:]
        ])

        let value = L10n.localizedValue(
            for: "prompt",
            preferredLanguages: ["zh-Hans_GB"],
            currentLocale: Locale(identifier: "zh_Hans_GB"),
            bundle: bundle
        )

        XCTAssertEqual(value, "Prompt")
    }

    private func makeFixtureBundle(localizations: [String: [String: String]]) throws -> Bundle {
        let bundleURL = temporaryDirectoryURL.appendingPathComponent("Fixture.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        for (localization, entries) in localizations {
            let localizationURL = bundleURL.appendingPathComponent("\(localization).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: localizationURL, withIntermediateDirectories: true)

            let contents = entries
                .sorted(by: { $0.key < $1.key })
                .map { "\"\($0.key)\" = \"\($0.value)\";" }
                .joined(separator: "\n")

            try contents.write(
                to: localizationURL.appendingPathComponent("Localizable.strings"),
                atomically: true,
                encoding: .utf8
            )
        }

        guard let bundle = Bundle(path: bundleURL.path) else {
            XCTFail("Failed to create fixture bundle")
            throw NSError(domain: "L10nTests", code: 1)
        }

        return bundle
    }
}
