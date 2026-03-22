//
//  GPXExportService.swift
//  StreetStamps
//
//  Exports a JourneyRoute to GPX format for sharing.
//

import Foundation
import CoreLocation

enum GPXExportService {

    static func generateGPX(from journey: JourneyRoute) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="StreetStamps"
             xmlns="http://www.topografix.com/GPX/1/1">
        """

        let name = xmlEscape(journey.customTitle ?? journey.displayCityName)
        xml += "\n  <metadata><name>\(name)</name>"
        if let startTime = journey.startTime {
            xml += "<time>\(iso8601(startTime))</time>"
        }
        xml += "</metadata>"

        xml += "\n  <trk>"
        xml += "\n    <name>\(name)</name>"
        xml += "\n    <trkseg>"

        let coords = journey.displayRouteCoordinates
        for coord in coords {
            let lat = String(format: "%.8f", coord.lat)
            let lon = String(format: "%.8f", coord.lon)
            xml += "\n      <trkpt lat=\"\(lat)\" lon=\"\(lon)\"></trkpt>"
        }

        xml += "\n    </trkseg>"
        xml += "\n  </trk>"
        xml += "\n</gpx>\n"

        return xml
    }

    static func writeToTempFile(journey: JourneyRoute) -> URL? {
        let gpx = generateGPX(from: journey)
        let safeName = (journey.customTitle ?? journey.displayCityName)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .prefix(50)
        let filename = "\(safeName)_\(journey.id.prefix(8)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
