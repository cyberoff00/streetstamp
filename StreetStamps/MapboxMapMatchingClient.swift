import Foundation
import CoreLocation

/// Mapbox Map Matching API client.
///
/// Snaps a sequence of GPS coordinates to the nearest road network using HMM + Viterbi.
/// Returns a snapped polyline + per-tracepoint confidence.
///
/// Cost-aware behavior:
///   - Auto-downsamples input to ~10m spacing before sending (sport mode produces
///     dense 3m points; matching algorithm doesn't need that density).
///   - Auto-rejects journeys < 200m total distance (matching is meaningless on
///     near-stationary fragments).
///   - Auto-chunks long traces (>90 points) into segments with 5-point overlap,
///     stitches result.
///
/// Security:
///   - Token is `pk.*` public token from Info.plist's MBXAccessToken.
///   - Restrict to bundle ID in Mapbox dashboard for production deployments.
///
/// Reference: https://docs.mapbox.com/api/navigation/map-matching/
enum MapboxMapMatching {

    enum Profile: String {
        case driving
        case walking
        case cycling
    }

    enum Failure: Error {
        case missingToken
        case insufficientInput        // < 2 points after downsampling, or distance < threshold
        case networkError(Error)
        case httpError(statusCode: Int)
        case malformedResponse
        case lowConfidence(Double)    // matching ran but result not trustworthy
    }

    struct Result {
        let coordinates: [CLLocationCoordinate2D]
        /// Average matching confidence across all chunks (0.0–1.0).
        let confidence: Double
    }

    // MARK: - Tunables

    /// Maximum points per single API request (Mapbox limit is 100).
    static let maxPointsPerRequest = 90
    /// Overlap between adjacent chunks for stitching.
    static let chunkOverlap = 5
    /// Downsample target spacing before sending to API.
    static let downsampleSpacingMeters: Double = 10
    /// Skip matching if total trace distance is below this.
    static let minTraceDistanceMeters: Double = 200
    /// Reject matched result if average confidence is below this.
    static let minAcceptableConfidence: Double = 0.5

    // MARK: - Public entry

    /// Snap `coordinates` to road network. Caller decides what to do with the result
    /// (e.g. write to `route.matchedCoordinates`, fallback if `nil`).
    ///
    /// - Parameter coordinates: input trace (any density). Will be downsampled to ~10m.
    /// - Parameter profile: routing profile (driving/walking/cycling).
    /// - Parameter accuracies: per-point horizontal accuracy in meters; used as
    ///   `radiuses` parameter so the matching algorithm respects GPS uncertainty.
    ///   Pass `nil` to use default radius. If non-nil, length must equal `coordinates`.
    /// - Returns: matched coordinates + average confidence, or throws `Failure`.
    static func match(
        coordinates: [CLLocationCoordinate2D],
        profile: Profile,
        accuracies: [Double]? = nil,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { req in
            try await URLSession.shared.data(for: req)
        }
    ) async throws -> Result {
        guard let token = mapboxAccessToken else { throw Failure.missingToken }

        // 1. Downsample input to ~10m spacing — matching doesn't need 3m density,
        //    saves API calls drastically for sport-mode traces.
        let (downsampledCoords, downsampledAccuracies) = downsample(
            coords: coordinates,
            accuracies: accuracies,
            spacing: downsampleSpacingMeters
        )

        // 2. Reject if too short — matching meaningless for near-stationary traces.
        let totalDistance = polylineDistance(downsampledCoords)
        guard downsampledCoords.count >= 2, totalDistance >= minTraceDistanceMeters else {
            throw Failure.insufficientInput
        }

        // 3. Chunk for API limit (≤100 points/request, we use 90 with 5-point overlap).
        let chunks = chunkCoordinates(downsampledCoords, accuracies: downsampledAccuracies)

        // 4. Send each chunk, collect responses.
        var matchedChunks: [[CLLocationCoordinate2D]] = []
        var confidences: [Double] = []
        for chunk in chunks {
            let (matched, conf) = try await sendChunk(
                chunk: chunk,
                profile: profile,
                token: token,
                transport: transport
            )
            matchedChunks.append(matched)
            confidences.append(conf)
        }

        // 5. Average confidence — single low-confidence chunk poisons the whole trace
        //    only weakly; we take the mean to allow partial-good traces through.
        let avgConfidence = confidences.reduce(0.0, +) / Double(confidences.count)
        guard avgConfidence >= minAcceptableConfidence else {
            throw Failure.lowConfidence(avgConfidence)
        }

        // 6. Stitch: drop first `overlap` points of each non-first chunk to avoid duplicates.
        let stitched = stitchChunks(matchedChunks)
        return Result(coordinates: stitched, confidence: avgConfidence)
    }

    // MARK: - Token resolution

    /// Read public Mapbox token from Info.plist's MBXAccessToken (same key Mapbox SDK uses).
    static var mapboxAccessToken: String? {
        let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    // MARK: - Single-chunk request

    /// Build URL + send one chunk. Returns matched coords + confidence.
    private static func sendChunk(
        chunk: ChunkInput,
        profile: Profile,
        token: String,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> ([CLLocationCoordinate2D], Double) {
        let coordsParam = chunk.coords
            .map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }
            .joined(separator: ";")

        var components = URLComponents(string: "https://api.mapbox.com/matching/v5/mapbox/\(profile.rawValue)/\(coordsParam)")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "tidy", value: "true")
        ]
        if let radiuses = chunk.radiuses {
            // Mapbox accepts radiuses ≤ 50; clamp.
            let clamped = radiuses.map { String(format: "%.0f", min(max($0, 1), 50)) }.joined(separator: ";")
            queryItems.append(URLQueryItem(name: "radiuses", value: clamped))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw Failure.malformedResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(req)
        } catch {
            throw Failure.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Failure.httpError(statusCode: http.statusCode)
        }

        return try parseResponse(data: data)
    }

    // MARK: - Response parsing

    /// Mapbox API response (geojson mode):
    /// ```
    /// { "matchings": [{ "geometry": {"type":"LineString","coordinates":[[lon,lat],...]},
    ///                    "confidence": 0.85 }],
    ///   "code": "Ok" }
    /// ```
    private static func parseResponse(data: Data) throws -> ([CLLocationCoordinate2D], Double) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = json["code"] as? String,
            code == "Ok",
            let matchings = json["matchings"] as? [[String: Any]],
            let first = matchings.first,
            let geometry = first["geometry"] as? [String: Any],
            let coordsArray = geometry["coordinates"] as? [[Double]]
        else {
            throw Failure.malformedResponse
        }

        let coords: [CLLocationCoordinate2D] = coordsArray.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            // Mapbox returns [lon, lat] (note ordering!)
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        let confidence = (first["confidence"] as? Double) ?? 0.0
        return (coords, confidence)
    }

    // MARK: - Helpers (downsample / chunk / stitch / distance)

    struct ChunkInput {
        let coords: [CLLocationCoordinate2D]
        let radiuses: [Double]?
    }

    /// Drop points closer than `spacing` meters from the previously kept point.
    /// Always keeps first and last. Linear time.
    static func downsample(
        coords: [CLLocationCoordinate2D],
        accuracies: [Double]?,
        spacing: Double
    ) -> ([CLLocationCoordinate2D], [Double]?) {
        guard coords.count > 2 else { return (coords, accuracies) }

        var keptCoords: [CLLocationCoordinate2D] = [coords[0]]
        var keptAccs: [Double]? = (accuracies != nil) ? [accuracies![0]] : nil

        var lastKept = coords[0]
        for i in 1..<(coords.count - 1) {
            let d = CLLocation(latitude: lastKept.latitude, longitude: lastKept.longitude)
                .distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
            if d >= spacing {
                keptCoords.append(coords[i])
                if let accs = accuracies { keptAccs?.append(accs[i]) }
                lastKept = coords[i]
            }
        }
        // Always keep last
        keptCoords.append(coords[coords.count - 1])
        if let accs = accuracies { keptAccs?.append(accs[accs.count - 1]) }
        return (keptCoords, keptAccs)
    }

    /// Cumulative polyline distance (meters).
    static func polylineDistance(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    /// Split into chunks of ≤90 points with 5-point overlap.
    /// `[0..89], [85..174], [170..259], ...`
    static func chunkCoordinates(
        _ coords: [CLLocationCoordinate2D],
        accuracies: [Double]?
    ) -> [ChunkInput] {
        guard coords.count > maxPointsPerRequest else {
            return [ChunkInput(coords: coords, radiuses: accuracies)]
        }

        var chunks: [ChunkInput] = []
        let stride = maxPointsPerRequest - chunkOverlap
        var idx = 0
        while idx < coords.count {
            let endIdx = min(idx + maxPointsPerRequest, coords.count)
            let chunkCoords = Array(coords[idx..<endIdx])
            let chunkAccs: [Double]? = accuracies.map { Array($0[idx..<endIdx]) }
            chunks.append(ChunkInput(coords: chunkCoords, radiuses: chunkAccs))
            if endIdx == coords.count { break }
            idx += stride
        }
        return chunks
    }

    /// Stitch chunks: keep first chunk in full, drop first `chunkOverlap` of subsequent chunks.
    /// Note: Mapbox's snapped output for overlapping input may differ slightly between
    /// chunks (HMM has different context). Dropping the overlap is a pragmatic stitch
    /// that avoids duplicate visible points; minor seam discontinuity (< 5m) is acceptable.
    static func stitchChunks(_ chunks: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D] {
        guard !chunks.isEmpty else { return [] }
        var out: [CLLocationCoordinate2D] = chunks[0]
        for i in 1..<chunks.count {
            let chunk = chunks[i]
            // Drop the first `chunkOverlap` points to avoid duplicating overlap region.
            // Use min so a short final chunk doesn't underflow.
            let dropCount = min(chunkOverlap, chunk.count)
            out.append(contentsOf: chunk.dropFirst(dropCount))
        }
        return out
    }
}
