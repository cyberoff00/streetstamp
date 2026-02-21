//
//  JourneyGeoJSON.swift
//  StreetStamps
//
//  Created by Claire Yang on 12/01/2026.
//

import Foundation
import CoreLocation



struct Feature: Codable {
    var type: String = "Feature"
    var geometry: Geometry
    var properties: [String: CodableValue] = [:]
}

struct Geometry: Codable {
    var type: String
    var coordinates: CodableCoordinates
}

enum CodableCoordinates: Codable {
    case point([Double])
    case lineString([[Double]])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let p = try? c.decode([Double].self) { self = .point(p); return }
        if let ls = try? c.decode([[Double]].self) { self = .lineString(ls); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid coordinates")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .point(let p): try c.encode(p)
        case .lineString(let ls): try c.encode(ls)
        }
    }
}

// properties 的值支持 string / number / bool（够用了）
enum CodableValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid property value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        }
    }
}

extension Array where Element == CoordinateCodable {
    func toLineStringCoordinates() -> [[Double]] {
        // GeoJSON uses [lon, lat]
        map { [$0.lon, $0.lat] }
    }

    func toPointFeatures() -> [Feature] {
        map {
            Feature(
                geometry: Geometry(type: "Point", coordinates: .point([$0.lon, $0.lat])),
                properties: [:]
            )
        }
    }
}

extension JourneyRoute {
    func toLineFeature() -> Feature? {
        guard coordinates.count >= 2 else { return nil }
        var f = Feature(
            geometry: Geometry(type: "LineString", coordinates: .lineString(coordinates.toLineStringCoordinates()))
        )
        f.properties["journeyId"] = .string(id)
        f.properties["city"] = .string(currentCity)
        f.properties["distanceKm"] = .number(distance / 1000.0)
        f.properties["memoryCount"] = .number(Double(memories.count))
        if let s = startTime { f.properties["start"] = .number(s.timeIntervalSince1970) }
        if let e = endTime { f.properties["end"] = .number(e.timeIntervalSince1970) }
        return f
    }

    /// 用采样点做“足迹点”，远景做 heatmap/聚合（不需要国家网格也能好看）
    func toFootprintPointFeatures(maxPoints: Int) -> [Feature] {
        guard !coordinates.isEmpty else { return [] }
        let step = max(1, coordinates.count / maxPoints)
        let sampled = stride(from: 0, to: coordinates.count, by: step).map { coordinates[$0] }

        return sampled.map {
            var f = Feature(geometry: Geometry(type: "Point", coordinates: .point([$0.lon, $0.lat])))
            f.properties["city"] = .string(currentCity)
            f.properties["journeyId"] = .string(id)
            return f
        }
    }
}
