import Foundation
import CoreLocation

/// Debug-only diagnostic: calls Apple CLGeocoder with real coordinates for many
/// countries and logs what fields are returned.
///
/// Trigger from anywhere in Debug builds:
///   GeocoderCountryDiagnostics.run()
///
/// Output goes to console (print). Takes several minutes due to rate limiting.
#if DEBUG
enum GeocoderCountryDiagnostics {

    private struct Point {
        let iso2: String
        let label: String
        let lat: Double
        let lon: Double
    }

    private static let samplePoints: [Point] = [
        // ── China ──
        .init(iso2: "CN", label: "Beijing-center",    lat: 39.9042,  lon: 116.4074),
        .init(iso2: "CN", label: "Shanghai-Pudong",   lat: 31.2304,  lon: 121.4737),
        .init(iso2: "CN", label: "Shenzhen-Futian",   lat: 22.5431,  lon: 114.0579),
        .init(iso2: "CN", label: "Kunming",           lat: 25.0389,  lon: 102.7183),
        .init(iso2: "CN", label: "Lhasa",             lat: 29.6500,  lon: 91.1000),

        // ── Japan ──
        .init(iso2: "JP", label: "Tokyo-Shibuya",     lat: 35.6595,  lon: 139.7004),
        .init(iso2: "JP", label: "Osaka-Namba",        lat: 34.6627,  lon: 135.5022),
        .init(iso2: "JP", label: "Kyoto",             lat: 35.0116,  lon: 135.7681),
        .init(iso2: "JP", label: "Sapporo",           lat: 43.0618,  lon: 141.3545),

        // ── Korea ──
        .init(iso2: "KR", label: "Seoul-Gangnam",     lat: 37.4979,  lon: 127.0276),
        .init(iso2: "KR", label: "Busan-Haeundae",    lat: 35.1587,  lon: 129.1604),
        .init(iso2: "KR", label: "Jeju",              lat: 33.4996,  lon: 126.5312),

        // ── Thailand ──
        .init(iso2: "TH", label: "Bangkok-Sukhumvit", lat: 13.7278,  lon: 100.5695),
        .init(iso2: "TH", label: "Chiang-Mai",        lat: 18.7883,  lon: 98.9853),
        .init(iso2: "TH", label: "Phuket",            lat: 7.8804,   lon: 98.3923),

        // ── Singapore / HK / TW / MO ──
        .init(iso2: "SG", label: "Singapore-Marina",   lat: 1.2838,  lon: 103.8591),
        .init(iso2: "HK", label: "HongKong-Central",  lat: 22.2800,  lon: 114.1588),
        .init(iso2: "TW", label: "Taipei-101",        lat: 25.0330,  lon: 121.5654),
        .init(iso2: "MO", label: "Macau-center",      lat: 22.1987,  lon: 113.5439),

        // ── UK ──
        .init(iso2: "GB", label: "London-Westminster", lat: 51.5007, lon: -0.1246),
        .init(iso2: "GB", label: "Manchester",        lat: 53.4808,  lon: -2.2426),
        .init(iso2: "GB", label: "Edinburgh",         lat: 55.9533,  lon: -3.1883),
        .init(iso2: "GB", label: "Birmingham",        lat: 52.4862,  lon: -1.8904),

        // ── France ──
        .init(iso2: "FR", label: "Paris-center",      lat: 48.8566,  lon: 2.3522),
        .init(iso2: "FR", label: "Lyon",              lat: 45.7640,  lon: 4.8357),
        .init(iso2: "FR", label: "Marseille",         lat: 43.2965,  lon: 5.3698),
        .init(iso2: "FR", label: "Nice",              lat: 43.7102,  lon: 7.2620),

        // ── Italy ──
        .init(iso2: "IT", label: "Rome-Colosseum",    lat: 41.8902,  lon: 12.4922),
        .init(iso2: "IT", label: "Milan",             lat: 45.4642,  lon: 9.1900),
        .init(iso2: "IT", label: "Florence",          lat: 43.7696,  lon: 11.2558),

        // ── Spain ──
        .init(iso2: "ES", label: "Madrid-center",     lat: 40.4168,  lon: -3.7038),
        .init(iso2: "ES", label: "Barcelona",         lat: 41.3851,  lon: 2.1734),
        .init(iso2: "ES", label: "Seville",           lat: 37.3891,  lon: -5.9845),

        // ── Germany ──
        .init(iso2: "DE", label: "Berlin-Mitte",      lat: 52.5200,  lon: 13.4050),
        .init(iso2: "DE", label: "Munich",            lat: 48.1351,  lon: 11.5820),
        .init(iso2: "DE", label: "Hamburg",           lat: 53.5511,  lon: 9.9937),

        // ── Netherlands ──
        .init(iso2: "NL", label: "Amsterdam",         lat: 52.3676,  lon: 4.9041),
        .init(iso2: "NL", label: "Rotterdam",         lat: 51.9244,  lon: 4.4777),

        // ── Switzerland ──
        .init(iso2: "CH", label: "Zurich",            lat: 47.3769,  lon: 8.5417),
        .init(iso2: "CH", label: "Geneva",            lat: 46.2044,  lon: 6.1432),

        // ── Belgium ──
        .init(iso2: "BE", label: "Brussels",          lat: 50.8503,  lon: 4.3517),
        .init(iso2: "BE", label: "Antwerp",           lat: 51.2194,  lon: 4.4025),

        // ── Scandinavia ──
        .init(iso2: "SE", label: "Stockholm",         lat: 59.3293,  lon: 18.0686),
        .init(iso2: "NO", label: "Oslo",              lat: 59.9139,  lon: 10.7522),
        .init(iso2: "DK", label: "Copenhagen",        lat: 55.6761,  lon: 12.5683),

        // ── Australia / NZ ──
        .init(iso2: "AU", label: "Sydney-Opera",      lat: -33.8568, lon: 151.2153),
        .init(iso2: "AU", label: "Melbourne",         lat: -37.8136, lon: 144.9631),
        .init(iso2: "NZ", label: "Auckland",          lat: -36.8485, lon: 174.7633),

        // ── Southeast Asia ──
        .init(iso2: "ID", label: "Jakarta",           lat: -6.2088,  lon: 106.8456),
        .init(iso2: "ID", label: "Bali-Kuta",         lat: -8.7180,  lon: 115.1710),
        .init(iso2: "PH", label: "Manila",            lat: 14.5995,  lon: 120.9842),
        .init(iso2: "VN", label: "Hanoi",             lat: 21.0278,  lon: 105.8342),
        .init(iso2: "VN", label: "HoChiMinh",         lat: 10.8231,  lon: 106.6297),
        .init(iso2: "MY", label: "KualaLumpur",       lat: 3.1390,   lon: 101.6869),
        .init(iso2: "MY", label: "Penang",            lat: 5.4141,   lon: 100.3288),

        // ── USA ──
        .init(iso2: "US", label: "NewYork-Manhattan", lat: 40.7580,  lon: -73.9855),
        .init(iso2: "US", label: "LosAngeles",        lat: 34.0522,  lon: -118.2437),
        .init(iso2: "US", label: "Chicago",           lat: 41.8781,  lon: -87.6298),
        .init(iso2: "US", label: "SanFrancisco",      lat: 37.7749,  lon: -122.4194),

        // ── Other common destinations ──
        .init(iso2: "AE", label: "Dubai-Downtown",    lat: 25.1972,  lon: 55.2744),
        .init(iso2: "TR", label: "Istanbul",          lat: 41.0082,  lon: 28.9784),
        .init(iso2: "EG", label: "Cairo",             lat: 30.0444,  lon: 31.2357),
        .init(iso2: "IN", label: "Mumbai",            lat: 19.0760,  lon: 72.8777),
        .init(iso2: "IN", label: "Delhi",             lat: 28.6139,  lon: 77.2090),
        .init(iso2: "BR", label: "SaoPaulo",          lat: -23.5505, lon: -46.6333),
        .init(iso2: "BR", label: "Rio",               lat: -22.9068, lon: -43.1729),
        .init(iso2: "MX", label: "MexicoCity",        lat: 19.4326,  lon: -99.1332),
        .init(iso2: "RU", label: "Moscow",            lat: 55.7558,  lon: 37.6173),
        .init(iso2: "ZA", label: "CapeTown",          lat: -33.9249, lon: 18.4241),
        .init(iso2: "KE", label: "Nairobi",           lat: -1.2921,  lon: 36.8219),
        .init(iso2: "AR", label: "BuenosAires",       lat: -34.6037, lon: -58.3816),
        .init(iso2: "CL", label: "Santiago",          lat: -33.4489, lon: -70.6693),
        .init(iso2: "PE", label: "Lima",              lat: -12.0464, lon: -77.0428),
        .init(iso2: "PT", label: "Lisbon",            lat: 38.7223,  lon: -9.1393),
        .init(iso2: "GR", label: "Athens",            lat: 37.9838,  lon: 23.7275),
        .init(iso2: "HR", label: "Dubrovnik",         lat: 42.6507,  lon: 18.0944),
        .init(iso2: "CZ", label: "Prague",            lat: 50.0755,  lon: 14.4378),
        .init(iso2: "AT", label: "Vienna",            lat: 48.2082,  lon: 16.3738),
        .init(iso2: "HU", label: "Budapest",          lat: 47.4979,  lon: 19.0402),
        .init(iso2: "PL", label: "Warsaw",            lat: 52.2297,  lon: 21.0122),
        .init(iso2: "FI", label: "Helsinki",          lat: 60.1699,  lon: 24.9384),
        .init(iso2: "IS", label: "Reykjavik",         lat: 64.1466,  lon: -21.9426),
        .init(iso2: "MA", label: "Marrakech",         lat: 31.6295,  lon: -7.9811),
        .init(iso2: "NP", label: "Kathmandu",         lat: 27.7172,  lon: 85.3240),
        .init(iso2: "LK", label: "Colombo",           lat: 6.9271,   lon: 79.8612),
        .init(iso2: "KH", label: "PhnomPenh",         lat: 11.5564,  lon: 104.9282),
        .init(iso2: "MM", label: "Yangon",            lat: 16.8661,  lon: 96.1951),
        .init(iso2: "LA", label: "Vientiane",         lat: 17.9757,  lon: 102.6331),
    ]

    static func run() {
        Task.detached(priority: .utility) {
            let geocoder = CLGeocoder()
            let locale = Locale(identifier: "en_US")

            var results: [(iso2: String, label: String, locality: String?, subAdmin: String?, admin: String?, country: String?)] = []

            print("\n" + String(repeating: "=", count: 120))
            print("📍 GEOCODER COUNTRY DIAGNOSTICS — \(samplePoints.count) points")
            print(String(repeating: "=", count: 120))
            print(String(format: "%-4s %-22s %-25s %-25s %-25s %-20s",
                          "ISO", "Label", "locality", "subAdminArea", "adminArea", "country"))
            print(String(repeating: "-", count: 120))

            for point in samplePoints {
                let location = CLLocation(latitude: point.lat, longitude: point.lon)

                try? await Task.sleep(nanoseconds: 2_000_000_000)

                var placemarks: [CLPlacemark]?
                do {
                    placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: locale)
                } catch {
                    let nsErr = error as NSError
                    if nsErr.domain == "GEOErrorDomain", nsErr.code == -3 {
                        print("  ⏳ Throttled at \(point.label), waiting 15s...")
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                        do {
                            placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: locale)
                        } catch {
                            print(String(format: "%-4s %-22s ⚠️ ERROR (retry): %@", point.iso2, point.label, error.localizedDescription))
                            continue
                        }
                    } else {
                        print(String(format: "%-4s %-22s ⚠️ ERROR: %@", point.iso2, point.label, error.localizedDescription))
                        continue
                    }
                }

                guard let pm = placemarks?.first else {
                    print(String(format: "%-4s %-22s (no placemark)", point.iso2, point.label))
                    continue
                }

                results.append((
                    iso2: point.iso2,
                    label: point.label,
                    locality: pm.locality,
                    subAdmin: pm.subAdministrativeArea,
                    admin: pm.administrativeArea,
                    country: pm.country
                ))

                print(String(format: "%-4s %-22s %-25s %-25s %-25s %-20s",
                              point.iso2,
                              point.label,
                              pm.locality ?? "nil",
                              pm.subAdministrativeArea ?? "nil",
                              pm.administrativeArea ?? "nil",
                              pm.country ?? "nil"))
            }

            // Summary
            print("\n" + String(repeating: "=", count: 90))
            print("📊 SUMMARY — Field availability per country")
            print(String(repeating: "=", count: 90))
            print(String(format: "%-4s  %-10s %-10s %-10s %-10s  %s",
                          "ISO", "locality", "subAdmin", "admin", "country", "Suggested"))
            print(String(repeating: "-", count: 90))

            let grouped = Dictionary(grouping: results, by: { $0.iso2 })
            for iso2 in grouped.keys.sorted() {
                let rows = grouped[iso2]!
                let n = rows.count
                let loc = rows.filter { $0.locality != nil }.count
                let sub = rows.filter { $0.subAdmin != nil }.count
                let adm = rows.filter { $0.admin != nil }.count
                let cty = rows.filter { $0.country != nil }.count

                let suggestion: String
                if loc == n && sub == n { suggestion = "locality or subAdmin (both always present)" }
                else if loc == n { suggestion = "locality (always present)" }
                else if sub == n { suggestion = "subAdmin (always present)" }
                else if adm == n { suggestion = "admin (locality/subAdmin unreliable)" }
                else { suggestion = "⚠️ check manually" }

                print(String(format: "%-4s  %-10s %-10s %-10s %-10s  %s",
                              iso2,
                              "\(loc)/\(n)",
                              "\(sub)/\(n)",
                              "\(adm)/\(n)",
                              "\(cty)/\(n)",
                              suggestion))
            }
            print(String(repeating: "=", count: 90))
            print("✅ Diagnostics complete.\n")
        }
    }
}
#endif
