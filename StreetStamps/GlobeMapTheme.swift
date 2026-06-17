//
//  GlobeMapTheme.swift
//  StreetStamps
//
//  A selectable Mapbox base-map style for the globe, paired with a highlight
//  palette tuned for that base. Only the globe sphere's style changes between
//  themes — the surround stays the app background colour (set via the
//  atmosphere's space colour), so the globe always floats on app white.
//
//  Switching theme reloads the Mapbox style — which wipes all custom layers —
//  so MapboxGlobeView re-adds every layer reading the colours from the active
//  theme. There is no per-layer mutation path; reload + rebuild is the model.
//

import SwiftUI
import UIKit
import MapboxMaps

struct GlobeMapTheme: Identifiable, Equatable {
    let id: String
    /// Localization key for the picker label.
    let nameKey: String
    let styleURI: StyleURI

    // Highlight palette. Opacities below the max are applied by MapboxGlobeView's
    // zoom expressions; these are the base colours.
    let countryFill: UIColor
    let countryBorder: UIColor
    /// Peak country-fill opacity (at far zoom). Higher for busy bases like
    /// satellite where a faint tint would be invisible.
    let countryFillMaxOpacity: Double
    let routeColor: UIColor
    let cityColor: UIColor
    let heatTint: UIColor

    // Picker swatch: a representative base + accent so the carousel reads at a
    // glance without rendering a live map thumbnail.
    let swatchBase: Color
    let swatchAccent: Color

    static func == (lhs: GlobeMapTheme, rhs: GlobeMapTheme) -> Bool { lhs.id == rhs.id }

    /// Mapbox Static Images API URL for a real preview of this style, so the
    /// picker shows the actual map look (dark world, light world, satellite…)
    /// rather than a simulated colour. Clipped to a circle by the caller for a
    /// globe feel. Returns nil if the style isn't a standard mapbox:// preset.
    func staticThumbnailURL(token: String, pixelSize: Int = 120) -> URL? {
        guard !token.isEmpty else { return nil }
        let raw = styleURI.rawValue
        let prefix = "mapbox://styles/"
        guard raw.hasPrefix(prefix) else { return nil }
        let path = String(raw.dropFirst(prefix.count))   // e.g. "mapbox/dark-v11"
        // Centre on Africa/Europe at a low zoom so continents read in the crop.
        let urlString = "https://api.mapbox.com/styles/v1/\(path)/static/12,28,0.45/\(pixelSize)x\(pixelSize)@2x?access_token=\(token)&logo=false&attribution=false"
        return URL(string: urlString)
    }

    /// A friendly balloon map-pin in this theme's city colour: a rounded head
    /// with a white centre dot, white outline and a soft drop shadow, tapering
    /// to a tip at the bottom. The tip is the anchor point, so the SymbolLayer
    /// must use `iconAnchor = .bottom`.
    func cityPinImage() -> UIImage {
        let pad: CGFloat = 4          // room for the shadow
        let r: CGFloat = 11           // head radius
        let pointLen: CGFloat = 13    // tip extension below the head
        let w = r * 2 + pad * 2
        let cx = w / 2
        let headCenterY = pad + r
        let tipY = headCenterY + r + pointLen
        let h = tipY + pad

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)

        return renderer.image { rctx in
            let ctx = rctx.cgContext
            let center = CGPoint(x: cx, y: headCenterY)
            let tip = CGPoint(x: cx, y: tipY)
            let theta = CGFloat.pi * (50.0 / 180.0)
            let left = CGPoint(x: center.x - r * sin(theta), y: center.y + r * cos(theta))
            let right = CGPoint(x: center.x + r * sin(theta), y: center.y + r * cos(theta))
            let startAngle = atan2(left.y - center.y, left.x - center.x)
            let endAngle = atan2(right.y - center.y, right.x - center.x)

            // Balloon outline: tip → left shoulder → arc over the top → right
            // shoulder → tip.
            let path = UIBezierPath()
            path.move(to: tip)
            path.addLine(to: left)
            path.addArc(withCenter: center, radius: r, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.addLine(to: tip)
            path.close()

            // Coloured fill with a soft shadow so the pin lifts off the map.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1),
                          blur: 2.5,
                          color: UIColor.black.withAlphaComponent(0.35).cgColor)
            cityColor.setFill()
            path.fill()
            ctx.restoreGState()

            // White outline for legibility on any base map.
            UIColor.white.setStroke()
            path.lineWidth = 1.6
            path.stroke()

            // White centre dot.
            let dot = UIBezierPath(arcCenter: center, radius: r * 0.40,
                                   startAngle: 0, endAngle: .pi * 2, clockwise: true)
            UIColor.white.setFill()
            dot.fill()
        }
    }
}

extension GlobeMapTheme {
    /// The shipped themes, in picker order. (Mapbox "Standard" is excluded — it
    /// doesn't compose with our country-boundaries overlay.)
    static let all: [GlobeMapTheme] = [dark, light, satellite, outdoors, streets]

    static let defaultID = light.id

    static func theme(for id: String) -> GlobeMapTheme {
        all.first { $0.id == id } ?? dark
    }

    // MARK: Themes

    /// Original look: dark globe, cyan countries, lime routes.
    static let dark = GlobeMapTheme(
        id: "dark",
        nameKey: "globe_theme_dark",
        styleURI: .dark,
        countryFill: .cyan,
        countryBorder: UIColor.cyan.withAlphaComponent(0.95),
        countryFillMaxOpacity: 0.30,
        routeColor: UIColor(red: 221.0/255.0, green: 247.0/255.0, blue: 161.0/255.0, alpha: 1.0),
        cityColor: .cyan,
        heatTint: .systemRed,
        swatchBase: Color(white: 0.10),
        swatchAccent: .cyan
    )

    /// "been"-style: light globe, warm amber countries.
    static let light = GlobeMapTheme(
        id: "light",
        nameKey: "globe_theme_light",
        styleURI: .light,
        countryFill: UIColor(red: 0.93, green: 0.62, blue: 0.18, alpha: 1.0),     // amber
        countryBorder: UIColor(red: 0.78, green: 0.49, blue: 0.10, alpha: 1.0),
        countryFillMaxOpacity: 0.45,
        routeColor: UIColor(red: 0.10, green: 0.46, blue: 0.78, alpha: 1.0),       // contrast blue
        cityColor: UIColor(red: 0.86, green: 0.40, blue: 0.08, alpha: 1.0),
        heatTint: UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1.0),
        swatchBase: Color(white: 0.90),
        swatchAccent: Color(red: 0.93, green: 0.62, blue: 0.18)
    )

    /// Modern Mapbox Standard globe: balanced day look, blue highlights.
    static let standard = GlobeMapTheme(
        id: "standard",
        nameKey: "globe_theme_standard",
        styleURI: StyleURI(rawValue: "mapbox://styles/mapbox/standard")!,
        countryFill: UIColor(red: 0.16, green: 0.52, blue: 0.96, alpha: 1.0),      // blue
        countryBorder: UIColor(red: 0.10, green: 0.40, blue: 0.82, alpha: 1.0),
        countryFillMaxOpacity: 0.38,
        routeColor: UIColor(red: 0.96, green: 0.45, blue: 0.10, alpha: 1.0),       // orange
        cityColor: UIColor(red: 0.12, green: 0.44, blue: 0.88, alpha: 1.0),
        heatTint: UIColor(red: 0.96, green: 0.45, blue: 0.10, alpha: 1.0),
        swatchBase: Color(red: 0.86, green: 0.90, blue: 0.95),
        swatchAccent: Color(red: 0.16, green: 0.52, blue: 0.96)
    )

    /// Satellite imagery: vivid magenta/pink countries — gold would clash with
    /// desert/sand tones in the imagery. Cyan routes stay clear of vegetation green.
    static let satellite = GlobeMapTheme(
        id: "satellite",
        nameKey: "globe_theme_satellite",
        styleURI: .satelliteStreets,
        countryFill: UIColor(red: 1.0, green: 0.18, blue: 0.55, alpha: 1.0),       // magenta
        countryBorder: UIColor(red: 1.0, green: 0.40, blue: 0.68, alpha: 1.0),
        countryFillMaxOpacity: 0.55,
        routeColor: UIColor(red: 0.20, green: 0.95, blue: 1.0, alpha: 1.0),        // bright cyan
        cityColor: .white,
        heatTint: UIColor(red: 1.0, green: 0.25, blue: 0.60, alpha: 1.0),
        swatchBase: Color(red: 0.22, green: 0.28, blue: 0.20),
        swatchAccent: Color(red: 1.0, green: 0.18, blue: 0.55)
    )

    /// Outdoors / terrain base: deep rose against the greens & tans.
    static let outdoors = GlobeMapTheme(
        id: "outdoors",
        nameKey: "globe_theme_outdoors",
        styleURI: .outdoors,
        countryFill: UIColor(red: 0.86, green: 0.20, blue: 0.42, alpha: 1.0),      // rose
        countryBorder: UIColor(red: 0.72, green: 0.12, blue: 0.32, alpha: 1.0),
        countryFillMaxOpacity: 0.40,
        routeColor: UIColor(red: 0.15, green: 0.35, blue: 0.78, alpha: 1.0),       // deep blue
        cityColor: UIColor(red: 0.86, green: 0.20, blue: 0.42, alpha: 1.0),
        heatTint: UIColor(red: 0.86, green: 0.20, blue: 0.42, alpha: 1.0),
        swatchBase: Color(red: 0.86, green: 0.88, blue: 0.78),
        swatchAccent: Color(red: 0.86, green: 0.20, blue: 0.42)
    )

    /// Colourful streets base: saturated indigo + magenta to cut through.
    static let streets = GlobeMapTheme(
        id: "streets",
        nameKey: "globe_theme_streets",
        styleURI: .streets,
        countryFill: UIColor(red: 0.36, green: 0.31, blue: 0.86, alpha: 1.0),      // indigo
        countryBorder: UIColor(red: 0.28, green: 0.23, blue: 0.74, alpha: 1.0),
        countryFillMaxOpacity: 0.35,
        routeColor: UIColor(red: 0.90, green: 0.18, blue: 0.45, alpha: 1.0),       // magenta
        cityColor: UIColor(red: 0.36, green: 0.31, blue: 0.86, alpha: 1.0),
        heatTint: UIColor(red: 0.90, green: 0.18, blue: 0.45, alpha: 1.0),
        swatchBase: Color(white: 0.95),
        swatchAccent: Color(red: 0.36, green: 0.31, blue: 0.86)
    )
}
