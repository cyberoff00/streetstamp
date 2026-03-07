//
//  CityMapUtils.swift
//  StreetStamps
//
//  Created by Claire Yang on 13/01/2026.
//

import Foundation
import MapKit
import CoreLocation
import UIKit

public func bboxPolygon(for coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D]? {
    guard !coords.isEmpty else { return nil }

    var minLat = coords[0].latitude, maxLat = coords[0].latitude
    var minLon = coords[0].longitude, maxLon = coords[0].longitude

    for c in coords {
        minLat = min(minLat, c.latitude)
        maxLat = max(maxLat, c.latitude)
        minLon = min(minLon, c.longitude)
        maxLon = max(maxLon, c.longitude)
    }

    let latPad = max(0.01, (maxLat - minLat) * 0.35)
    let lonPad = max(0.01, (maxLon - minLon) * 0.35)

    minLat -= latPad; maxLat += latPad
    minLon -= lonPad; maxLon += lonPad

    let sw = CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
    let se = CLLocationCoordinate2D(latitude: minLat, longitude: maxLon)
    let ne = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
    let nw = CLLocationCoordinate2D(latitude: maxLat, longitude: minLon)
    return [sw, se, ne, nw]
}

public func regionToFit(coords: [CLLocationCoordinate2D], minSpan: Double, paddingFactor: Double) -> MKCoordinateRegion? {
    guard !coords.isEmpty else { return nil }
    var minLat = coords[0].latitude, maxLat = coords[0].latitude
    var minLon = coords[0].longitude, maxLon = coords[0].longitude

    for c in coords {
        minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
        minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
    }

    let center = CLLocationCoordinate2D(latitude: (minLat + maxLat)/2, longitude: (minLon + maxLon)/2)
    let span = MKCoordinateSpan(
        latitudeDelta: max(minSpan, (maxLat - minLat) * paddingFactor),
        longitudeDelta: max(minSpan, (maxLon - minLon) * paddingFactor)
    )
    return MKCoordinateRegion(center: center, span: span)
}

public func regionForCityWhole(
    boundary: [CLLocationCoordinate2D]?,
    bboxOrRouteCoords: [CLLocationCoordinate2D],
    anchor: CLLocationCoordinate2D?
) -> MKCoordinateRegion? {

    if let boundary, boundary.count >= 3 {
        return regionToFit(coords: boundary, minSpan: 0.12, paddingFactor: 1.15)
    }

    if !bboxOrRouteCoords.isEmpty {
        return regionToFit(coords: bboxOrRouteCoords, minSpan: 0.12, paddingFactor: 1.45)
    }

    if let a = anchor {
        return MKCoordinateRegion(
            center: a,
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
    }

    return nil
}

enum JourneySnapshotFraming {
    static func region(
        for coordsWGS84: [CLLocationCoordinate2D],
        countryISO2: String?,
        cityKey: String?,
        targetAspectRatio: CGFloat
    ) -> MKCoordinateRegion? {
        let coords = MapCoordAdapter.forMapKit(
            coordsWGS84.filter(\.isValid),
            countryISO2: countryISO2,
            cityKey: cityKey
        )
        guard !coords.isEmpty else { return nil }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude

        for coord in coords.dropFirst() {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let rawLat = maxLat - minLat
        let rawLon = maxLon - minLon
        let paddingFactor = 1.18
        var latDelta = max(0.01, rawLat * paddingFactor)
        var lonDelta = max(0.01, rawLon * paddingFactor)

        let safeAspectRatio = max(1.0, Double(targetAspectRatio))
        if lonDelta / latDelta < safeAspectRatio {
            lonDelta = latDelta * safeAspectRatio
        } else {
            latDelta = lonDelta / safeAspectRatio
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}

enum MapCoordAdapter {
    /// MapKit in Mainland China expects GCJ-02. We only opt-in when we have an authoritative signal.
    static func forMapKit(
        _ c: CLLocationCoordinate2D,
        countryISO2: String? = nil,
        cityKey: String? = nil
    ) -> CLLocationCoordinate2D {
        guard ChinaCoordinateTransform.shouldApplyGCJ(countryISO2: countryISO2, cityKey: cityKey) else { return c }
        return ChinaCoordinateTransform.wgs84ToGcj02(c)
    }

    static func forMapKit(
        _ coords: [CLLocationCoordinate2D],
        countryISO2: String? = nil,
        cityKey: String? = nil
    ) -> [CLLocationCoordinate2D] {
        coords.map { forMapKit($0, countryISO2: countryISO2, cityKey: cityKey) }
    }
}

struct CityDeepStyledSegment {
    let coords: [CLLocationCoordinate2D]
    let isGap: Bool
    let repeatWeight: Double
}

enum CityDeepRenderEngine {
    private static let cityFocusRadiusMeters: CLLocationDistance = 80_000
    private static let cityFocusWindowMeters: CLLocationDistance = 40_000
    private static let cityFocusMinPoints = 2
    private static let cityFocusWindowMaxPoints = 80
    private static let boundaryTrustMaxDistanceMeters: CLLocationDistance = 120_000
    private static let boundaryTrustMaxSpanDegrees: CLLocationDegrees = 3.0

    static func styledSegments(
        journeys: [JourneyRoute],
        countryISO2: String?,
        cityKey: String?
    ) -> [CityDeepStyledSegment] {
        let raw: [CityDeepStyledSegment] = journeys.flatMap { journey in
            RouteRenderingPipeline
                .buildSegments(
                    .init(
                        coordsWGS84: journey.allCLCoords,
                        applyGCJForChina: false,
                        gapDistanceMeters: 2_200,
                        countryISO2: countryISO2,
                        cityKey: cityKey
                    ),
                    surface: .mapKit
                )
                .segments
                .map { segment in
                    CityDeepStyledSegment(
                        coords: segment.coords,
                        isGap: segment.style == .dashed,
                        repeatWeight: 0
                    )
                }
        }

        guard !raw.isEmpty else { return [] }

        var freq: [String: Int] = [:]
        for seg in raw where !seg.isGap && seg.coords.count >= 2 {
            let key = segmentSignature(seg.coords)
            freq[key, default: 0] += 1
        }

        let p95 = max(1.0, quantile(Array(freq.values), p: 0.95))
        return raw.map { seg in
            guard !seg.isGap, seg.coords.count >= 2 else { return seg }
            let key = segmentSignature(seg.coords)
            let n = Double(freq[key, default: 1])
            let weight = min(1.0, log(1.0 + n) / log(1.0 + p95))
            return CityDeepStyledSegment(coords: seg.coords, isGap: false, repeatWeight: weight)
        }
    }

    static func fittedRegion(
        cityKey: String,
        countryISO2: String?,
        journeys: [JourneyRoute],
        anchorWGS: CLLocationCoordinate2D?,
        effectiveBoundaryWGS: [CLLocationCoordinate2D]?,
        fetchedBoundaryWGS: [CLLocationCoordinate2D]?
    ) -> MKCoordinateRegion? {
        let derivedAnchorWGS: CLLocationCoordinate2D? = {
            if let anchorWGS { return anchorWGS }
            if let byStart = journeys.first(where: { $0.startCityKey == cityKey })?.allCLCoords.first {
                return byStart
            }
            return journeys.first?.allCLCoords.first
        }()

        let derivedAnchorForMap = derivedAnchorWGS.map {
            MapCoordAdapter.forMapKit($0, countryISO2: countryISO2, cityKey: cityKey)
        }
        let focusedWGS = focusedJourneyCoords(journeys: journeys, anchorWGS: derivedAnchorWGS)
        let focusedForMap = MapCoordAdapter.forMapKit(focusedWGS, countryISO2: countryISO2, cityKey: cityKey)

        let boundaryCandidates = [fetchedBoundaryWGS, effectiveBoundaryWGS]
        if let boundaryWGS = boundaryCandidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            let boundaryForMap = MapCoordAdapter.forMapKit(boundaryWGS, countryISO2: countryISO2, cityKey: cityKey)
            if let boundaryRegion = regionByFitting(boundaryForMap),
               isBoundaryTrusted(boundaryRegion, anchor: derivedAnchorForMap) {
                return zoomRegionInsideBoundary(boundaryRegion: boundaryRegion, journeyCoordsForMap: focusedForMap)
            }
        }

        if let anchorWGS = derivedAnchorWGS {
            let anchor = MapCoordAdapter.forMapKit(anchorWGS, countryISO2: countryISO2, cityKey: cityKey)
            if let region = regionByFitting(focusedForMap), !focusedForMap.isEmpty { return region }
            return MKCoordinateRegion(center: anchor, span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18))
        }

        return regionByFitting(focusedForMap)
    }

    static func routeBaseColor(for appearanceRaw: String) -> UIColor {
        if appearanceRaw == MapAppearanceStyle.light.rawValue {
            return UIColor(red: 214.0 / 255.0, green: 109.0 / 255.0, blue: 34.0 / 255.0, alpha: 1.0)
        }
        return UIColor(red: 221.0 / 255.0, green: 247.0 / 255.0, blue: 161.0 / 255.0, alpha: 1.0)
    }

    static func drawStyledSegments(
        _ segments: [CityDeepStyledSegment],
        snapshot: MKMapSnapshotter.Snapshot,
        context: CGContext,
        appearanceRaw: String
    ) {
        guard !segments.isEmpty else { return }

        let base = routeBaseColor(for: appearanceRaw)
        let dash = RouteRenderStyleTokens.dashLengths

        for seg in segments where seg.coords.count >= 2 {
            let points = seg.coords.map(snapshot.point(for:)).filter { $0.x.isFinite && $0.y.isFinite }
            guard points.count >= 2 else { continue }

            let weight = CGFloat(max(0, min(1, seg.repeatWeight)))
            let glowWidth: CGFloat = seg.isGap ? 2.0 : (3.0 + weight * 1.2)
            let coreWidth: CGFloat = seg.isGap ? 1.1 : (1.6 + weight * 0.8)
            let glowAlpha: CGFloat = seg.isGap ? 0.08 : 0.12
            let coreAlpha: CGFloat = seg.isGap ? 0.30 : 0.84

            drawPolyline(points: points, in: context, color: base.withAlphaComponent(glowAlpha), lineWidth: glowWidth, dash: seg.isGap ? dash : nil)
            drawPolyline(points: points, in: context, color: base.withAlphaComponent(coreAlpha), lineWidth: coreWidth, dash: seg.isGap ? dash : nil)
        }
    }

    private static func drawPolyline(
        points: [CGPoint],
        in context: CGContext,
        color: UIColor,
        lineWidth: CGFloat,
        dash: [CGFloat]?
    ) {
        guard points.count >= 2 else { return }
        context.saveGState()
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if let dash, !dash.isEmpty {
            context.setLineDash(phase: 0, lengths: dash)
        } else {
            context.setLineDash(phase: 0, lengths: [])
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func focusedJourneyCoords(
        journeys: [JourneyRoute],
        anchorWGS: CLLocationCoordinate2D?
    ) -> [CLLocationCoordinate2D] {
        guard let anchorWGS else { return journeys.flatMap { $0.allCLCoords } }
        let anchorLoc = CLLocation(latitude: anchorWGS.latitude, longitude: anchorWGS.longitude)

        func localWindow(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
            guard !coords.isEmpty else { return [] }

            let near = coords.filter {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: anchorLoc) < cityFocusRadiusMeters
            }
            if near.count >= cityFocusMinPoints { return near }

            var out: [CLLocationCoordinate2D] = []
            let head = CLLocation(latitude: coords[0].latitude, longitude: coords[0].longitude)
            for c in coords {
                out.append(c)
                if out.count >= cityFocusWindowMaxPoints { break }
                let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: head)
                if d >= cityFocusWindowMeters, out.count >= cityFocusMinPoints { break }
            }
            return out
        }

        let focused = journeys.flatMap { localWindow($0.allCLCoords) }
        if focused.count >= cityFocusMinPoints { return focused }
        return [anchorWGS]
    }

    private static func regionByFitting(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.25),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.25)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func isBoundaryTrusted(_ region: MKCoordinateRegion, anchor: CLLocationCoordinate2D?) -> Bool {
        guard let anchor else { return true }
        let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let centerLoc = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let centerDistance = centerLoc.distance(from: anchorLoc)
        return centerDistance <= boundaryTrustMaxDistanceMeters
            && region.span.latitudeDelta <= boundaryTrustMaxSpanDegrees
            && region.span.longitudeDelta <= boundaryTrustMaxSpanDegrees
    }

    private static func clampCenter(
        _ center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        inside boundary: MKCoordinateRegion
    ) -> CLLocationCoordinate2D {
        let minLat = boundary.center.latitude - boundary.span.latitudeDelta / 2 + span.latitudeDelta / 2
        let maxLat = boundary.center.latitude + boundary.span.latitudeDelta / 2 - span.latitudeDelta / 2
        let minLon = boundary.center.longitude - boundary.span.longitudeDelta / 2 + span.longitudeDelta / 2
        let maxLon = boundary.center.longitude + boundary.span.longitudeDelta / 2 - span.longitudeDelta / 2
        return CLLocationCoordinate2D(
            latitude: min(max(center.latitude, minLat), maxLat),
            longitude: min(max(center.longitude, minLon), maxLon)
        )
    }

    private static func zoomRegionInsideBoundary(
        boundaryRegion: MKCoordinateRegion,
        journeyCoordsForMap: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard let journeyRegion = regionByFitting(journeyCoordsForMap), !journeyCoordsForMap.isEmpty else {
            return boundaryRegion
        }
        let minZoomSpan: CLLocationDegrees = 0.04
        let targetSpan = MKCoordinateSpan(
            latitudeDelta: min(boundaryRegion.span.latitudeDelta, max(minZoomSpan, journeyRegion.span.latitudeDelta)),
            longitudeDelta: min(boundaryRegion.span.longitudeDelta, max(minZoomSpan, journeyRegion.span.longitudeDelta))
        )
        let targetCenter = clampCenter(journeyRegion.center, span: targetSpan, inside: boundaryRegion)
        return MKCoordinateRegion(center: targetCenter, span: targetSpan)
    }

    private static func segmentSignature(_ coords: [CLLocationCoordinate2D]) -> String {
        guard let first = coords.first, let last = coords.last else { return UUID().uuidString }
        let stride = max(1, coords.count / 6)
        var samples: [CLLocationCoordinate2D] = [first]
        if coords.count > 2 {
            var i = stride
            while i < coords.count - 1 {
                samples.append(coords[i])
                i += stride
            }
        }
        samples.append(last)

        func quantized(_ c: CLLocationCoordinate2D) -> String {
            let lat = Int((c.latitude * 2_000).rounded())
            let lon = Int((c.longitude * 2_000).rounded())
            return "\(lat):\(lon)"
        }

        let forward = samples.map(quantized).joined(separator: "|")
        let backward = samples.reversed().map(quantized).joined(separator: "|")
        return min(forward, backward)
    }

    private static func quantile(_ values: [Int], p: Double) -> Double {
        guard !values.isEmpty else { return 1.0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return Double(sorted[max(0, min(sorted.count - 1, index))])
    }
}
