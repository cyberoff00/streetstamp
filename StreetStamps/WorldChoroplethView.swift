//
//  WorldChoroplethView.swift
//  StreetStamps
//
//  A flat, static "been-style" world map: visited countries filled in the brand
//  color, the rest grey. Pure SwiftUI Canvas + a bundled country-outline GeoJSON
//  — no Mapbox, no network, deterministic. Used as the top summary of
//  「你的小世界」 (FootprintView); tapping it opens the live globe.
//
//  REQUIRED RESOURCE: add a world-countries GeoJSON to the StreetStamps target
//  named `world_countries.geojson` (Natural Earth Admin-0, 110m is ideal —
//  public domain, ~300KB). Each feature needs an ISO-3166-1 alpha-2 code in one
//  of: ISO_A2 / ISO3166-1-Alpha-2 / iso_a2 / WB_A2. If the file is missing the
//  view degrades gracefully (renders nothing) — callers should show a fallback.
//

import SwiftUI

/// One country, coordinates kept as raw (lon, lat) in CGPoint (x=lon, y=lat);
/// projected to pixels only at draw time.
struct CountryShape: Equatable {
    let iso: String
    /// Each element is one polygon ring (exterior; holes ignored at 110m).
    let rings: [[CGPoint]]
}

enum WorldGeoJSONLoader {
    private static let isoKeys = ["ISO_A2", "ISO3166-1-Alpha-2", "iso_a2", "ISO_A2_EH", "WB_A2", "iso2"]

    static func loadFromBundle(_ resource: String = "world_countries") -> [CountryShape] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson")
                ?? Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        return parse(data)
    }

    /// Tolerant GeoJSON parse via JSONSerialization (GeoJSON's nested coordinate
    /// arrays are awkward for Codable). Returns [] on any structural problem.
    static func parse(_ data: Data) -> [CountryShape] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }

        var out: [CountryShape] = []
        for feature in features {
            let props = feature["properties"] as? [String: Any] ?? [:]
            let iso = isoKeys.compactMap { props[$0] as? String }
                .first { !$0.isEmpty && $0 != "-99" }?
                .uppercased() ?? ""
            guard let geom = feature["geometry"] as? [String: Any],
                  let type = geom["type"] as? String else { continue }

            var rings: [[CGPoint]] = []
            switch type {
            case "Polygon":
                if let coords = geom["coordinates"] as? [[[Double]]] {
                    rings.append(contentsOf: coords.map(ringPoints))
                }
            case "MultiPolygon":
                if let coords = geom["coordinates"] as? [[[[Double]]]] {
                    for polygon in coords { rings.append(contentsOf: polygon.map(ringPoints)) }
                }
            default:
                continue
            }
            if !rings.isEmpty { out.append(CountryShape(iso: iso, rings: rings)) }
        }
        return out
    }

    private static func ringPoints(_ ring: [[Double]]) -> [CGPoint] {
        ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1]) // x=lon, y=lat
        }
    }

    // Web Mercator with the poles cropped — the familiar "world map" look. The
    // latitude band drops most of Antarctica and keeps proportions natural
    // (plain equirectangular squished the populated north and showed a huge
    // empty Antarctica).
    static let latMax = 84.0
    static let latMin = -56.0

    static func mercatorY(_ lat: Double) -> Double {
        let c = min(latMax, max(latMin, lat))
        return log(tan(.pi / 4 + c * .pi / 360))
    }

    /// width / height for the cropped Mercator band (conformal, no distortion).
    static var aspect: Double { (2 * .pi) / (mercatorY(latMax) - mercatorY(latMin)) }

    static func project(lon: Double, lat: Double, in size: CGSize) -> CGPoint {
        let x = (lon + 180.0) / 360.0 * Double(size.width)
        let top = mercatorY(latMax)
        let bottom = mercatorY(latMin)
        let y = (top - mercatorY(lat)) / (top - bottom) * Double(size.height)
        return CGPoint(x: x, y: y)
    }
}

/// Pure drawing of preloaded shapes — no async loading, so it's safe inside
/// `ImageRenderer` (used by the share poster).
struct WorldChoroplethCanvas: View {
    let shapes: [CountryShape]
    let visitedISO2: Set<String>
    var visitedColor: Color = FigmaTheme.primary
    var landColor: Color = Color(white: 0.85)
    var borderColor: Color = .white

    var body: some View {
        Canvas { ctx, size in
            for country in shapes {
                var path = Path()
                for ring in country.rings where ring.count > 1 {
                    let pts = ring.map { WorldGeoJSONLoader.project(lon: $0.x, lat: $0.y, in: size) }
                    path.addLines(pts)
                    path.closeSubpath()
                }
                // Unify Taiwan/HK/Macao into China so they always match the
                // mainland's color — never shown as a separate territory.
                let iso = FootprintFactsBuilder.unifiedISO(country.iso)
                let visited = !iso.isEmpty && visitedISO2.contains(iso)
                ctx.fill(path, with: .color(visited ? visitedColor : landColor))
                ctx.stroke(path, with: .color(borderColor), lineWidth: 0.4)
            }
        }
        .aspectRatio(CGFloat(WorldGeoJSONLoader.aspect), contentMode: .fit)
    }
}

struct WorldChoroplethView: View {
    let visitedISO2: Set<String>
    var visitedColor: Color = FigmaTheme.primary
    var landColor: Color = Color(white: 0.85)
    var borderColor: Color = .white

    @State private var shapes: [CountryShape] = []
    @State private var didLoad = false

    var body: some View {
        WorldChoroplethCanvas(shapes: shapes, visitedISO2: visitedISO2,
                              visitedColor: visitedColor, landColor: landColor, borderColor: borderColor)
            .task {
                guard !didLoad else { return }
                didLoad = true
                shapes = await Task.detached(priority: .userInitiated) {
                    WorldGeoJSONLoader.loadFromBundle()
                }.value
            }
    }
}
