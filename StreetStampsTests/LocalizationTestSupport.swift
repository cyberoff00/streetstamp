import Foundation
import XCTest

func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func loadStringsFile(at url: URL) throws -> [String: String] {
    let dictionary = NSDictionary(contentsOf: url) as? [String: String]
    return try XCTUnwrap(dictionary, "Unable to parse strings file at \(url.path)")
}
