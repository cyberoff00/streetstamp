import Foundation
import CoreLocation

/// WGS84 <-> GCJ-02 conversion helpers.
///
/// Important:
/// - **Do NOT** decide whether to apply GCJ based on a coarse bbox.
///   Instead, opt-in only when we have an authoritative ISO2 (`CN`) or a canonical cityKey ending with `|CN`.
/// - The GCJ algorithm itself still uses a common bbox validity gate (to avoid producing garbage output).
enum ChinaCoordinateTransform {

    /// Single, conservative source of truth for whether we should render in GCJ-02.
    ///
    /// - Prefer `countryISO2` (from reverse geocode / canonical resolver).
    /// - Fallback to `cityKey` suffix (`"<City>|CN"`).
    static func shouldApplyGCJ(countryISO2: String?, cityKey: String? = nil) -> Bool {
        if let iso = countryISO2?.uppercased(), iso == "CN" { return true }
        if let key = cityKey, let suffix = key.split(separator: "|").last?.uppercased(), suffix == "CN" { return true }
        return false
    }

    /// Common GCJ validity bbox (used by many implementations).
    /// This is *not* used as a product decision gate; only as an algorithm safety check.
    static func isWithinGCJValidRegion(_ c: CLLocationCoordinate2D) -> Bool {
        let lat = c.latitude
        let lon = c.longitude
        return (lat >= 0.8293 && lat <= 55.8271 && lon >= 72.004 && lon <= 137.8347)
    }

    static func wgs84ToGcj02(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if outOfChina(c) { return c }

        let a = 6378245.0
        let ee = 0.00669342162296594323

        var dLat = transformLat(x: c.longitude - 105.0, y: c.latitude - 35.0)
        var dLon = transformLon(x: c.longitude - 105.0, y: c.latitude - 35.0)
        let radLat = c.latitude / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * Double.pi)

        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }

    // MARK: - Internals

    private static func outOfChina(_ c: CLLocationCoordinate2D) -> Bool {
        !isWithinGCJValidRegion(c)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * Double.pi) + 320 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return ret
    }
}

extension CLLocationCoordinate2D {
    var wgs2gcj: CLLocationCoordinate2D { ChinaCoordinateTransform.wgs84ToGcj02(self) }
}
