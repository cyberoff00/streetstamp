import Foundation
import StoreKit

@MainActor
final class FeatureFlagStore: ObservableObject {
    static let shared = FeatureFlagStore()

    @Published private(set) var socialEnabled: Bool = true
    @Published private(set) var hasFetched: Bool = false

    private let socialOverrideKey = "streetstamps.feature.social_enabled_override"
    private let everUnlockedKey = "streetstamps.feature.social_ever_unlocked"

    private init() {
        let overrideValue = UserDefaults.standard.object(forKey: socialOverrideKey) as? Bool
        let everUnlocked = UserDefaults.standard.bool(forKey: everUnlockedKey)
        #if DEBUG
        print("[FeatureFlag] init override=\(String(describing: overrideValue)) everUnlocked=\(everUnlocked)")
        #endif
        if let override = overrideValue {
            socialEnabled = override
            return
        }
        // Asymmetric rule: once the server has ever returned social:true for this
        // install, we keep it on forever — even if the user later switches to a
        // gated Apple ID. Only users who have never been unlocked are subject to
        // the region gate.
        if everUnlocked {
            socialEnabled = true
        }
    }

    func fetchFlags() async {
        #if DEBUG
        print("[FeatureFlag] fetchFlags entered, socialEnabled=\(socialEnabled)")
        #endif
        let region = await resolveStorefrontRegion()
        #if DEBUG
        print("[FeatureFlag] resolved region=\(region ?? "nil"), everUnlocked=\(UserDefaults.standard.bool(forKey: everUnlockedKey))")
        #endif
        guard let base = BackendConfig.baseURL else {
            hasFetched = true
            return
        }

        var components = URLComponents(url: base.appendingPathComponent("v1/feature-flags"), resolvingAgainstBaseURL: false)
        if let region, !region.isEmpty {
            components?.queryItems = [URLQueryItem(name: "region", value: region)]
        }

        guard let url = components?.url else {
            hasFetched = true
            return
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue(region, forHTTPHeaderField: "X-Storefront-Region")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                #if DEBUG
                print("[FeatureFlag] fetch failed http=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                hasFetched = true
                return
            }
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[FeatureFlag] fetch body=\(body)")
            #endif
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let social = json["social"] as? Bool {
                if social {
                    UserDefaults.standard.set(true, forKey: everUnlockedKey)
                    socialEnabled = true
                } else if !UserDefaults.standard.bool(forKey: everUnlockedKey) {
                    socialEnabled = false
                }
                // else: previously unlocked — ignore server-side false.
            }
        } catch {
            #if DEBUG
            print("[FeatureFlag] fetch error=\(error)")
            #endif
            // Keep cached/default value on network failure.
        }
        hasFetched = true
    }

    /// Resolves the live App Store storefront region on every launch.
    /// We no longer persist the region itself — the asymmetric unlock flag
    /// (`everUnlockedKey`) is what carries forward across launches.
    private func resolveStorefrontRegion() async -> String? {
        #if DEBUG
        // Testing-only override. Set via Scheme → Run → Arguments → Environment
        // Variables: FEATURE_FLAG_FORCE_REGION = CN | GB | US | ...
        if let forced = ProcessInfo.processInfo.environment["FEATURE_FLAG_FORCE_REGION"],
           !forced.trimmingCharacters(in: .whitespaces).isEmpty {
            let normalized = Self.normalizeToAlpha2(forced)
            print("[FeatureFlag] DEBUG forced region=\(normalized) (from FEATURE_FLAG_FORCE_REGION)")
            return normalized
        }
        #endif
        if #available(iOS 15.0, *) {
            do {
                if let storefront = try await Storefront.current {
                    // Storefront.countryCode is ISO 3166-1 alpha-3 ("CHN", "USA"...).
                    // Backend compares against alpha-2, so normalize here.
                    return Self.normalizeToAlpha2(storefront.countryCode)
                }
            } catch {
                // Fall through to Locale-based fallback.
            }
        }
        return Locale.current.region?.identifier
    }

    /// Accepts either alpha-2 or alpha-3 and returns alpha-2 when recognizable.
    /// Unknown inputs are returned uppercased and unchanged so the caller can still send something.
    private static func normalizeToAlpha2(_ code: String) -> String {
        let upper = code.trimmingCharacters(in: .whitespaces).uppercased()
        if upper.count == 2 { return upper }
        if upper.count == 3, let mapped = alpha3ToAlpha2[upper] { return mapped }
        return upper
    }

    private static let alpha3ToAlpha2: [String: String] = [
        "AFG": "AF", "ALA": "AX", "ALB": "AL", "DZA": "DZ", "ASM": "AS",
        "AND": "AD", "AGO": "AO", "AIA": "AI", "ATA": "AQ", "ATG": "AG",
        "ARG": "AR", "ARM": "AM", "ABW": "AW", "AUS": "AU", "AUT": "AT",
        "AZE": "AZ", "BHS": "BS", "BHR": "BH", "BGD": "BD", "BRB": "BB",
        "BLR": "BY", "BEL": "BE", "BLZ": "BZ", "BEN": "BJ", "BMU": "BM",
        "BTN": "BT", "BOL": "BO", "BES": "BQ", "BIH": "BA", "BWA": "BW",
        "BVT": "BV", "BRA": "BR", "IOT": "IO", "BRN": "BN", "BGR": "BG",
        "BFA": "BF", "BDI": "BI", "CPV": "CV", "KHM": "KH", "CMR": "CM",
        "CAN": "CA", "CYM": "KY", "CAF": "CF", "TCD": "TD", "CHL": "CL",
        "CHN": "CN", "CXR": "CX", "CCK": "CC", "COL": "CO", "COM": "KM",
        "COG": "CG", "COD": "CD", "COK": "CK", "CRI": "CR", "CIV": "CI",
        "HRV": "HR", "CUB": "CU", "CUW": "CW", "CYP": "CY", "CZE": "CZ",
        "DNK": "DK", "DJI": "DJ", "DMA": "DM", "DOM": "DO", "ECU": "EC",
        "EGY": "EG", "SLV": "SV", "GNQ": "GQ", "ERI": "ER", "EST": "EE",
        "SWZ": "SZ", "ETH": "ET", "FLK": "FK", "FRO": "FO", "FJI": "FJ",
        "FIN": "FI", "FRA": "FR", "GUF": "GF", "PYF": "PF", "ATF": "TF",
        "GAB": "GA", "GMB": "GM", "GEO": "GE", "DEU": "DE", "GHA": "GH",
        "GIB": "GI", "GRC": "GR", "GRL": "GL", "GRD": "GD", "GLP": "GP",
        "GUM": "GU", "GTM": "GT", "GGY": "GG", "GIN": "GN", "GNB": "GW",
        "GUY": "GY", "HTI": "HT", "HMD": "HM", "VAT": "VA", "HND": "HN",
        "HKG": "HK", "HUN": "HU", "ISL": "IS", "IND": "IN", "IDN": "ID",
        "IRN": "IR", "IRQ": "IQ", "IRL": "IE", "IMN": "IM", "ISR": "IL",
        "ITA": "IT", "JAM": "JM", "JPN": "JP", "JEY": "JE", "JOR": "JO",
        "KAZ": "KZ", "KEN": "KE", "KIR": "KI", "PRK": "KP", "KOR": "KR",
        "KWT": "KW", "KGZ": "KG", "LAO": "LA", "LVA": "LV", "LBN": "LB",
        "LSO": "LS", "LBR": "LR", "LBY": "LY", "LIE": "LI", "LTU": "LT",
        "LUX": "LU", "MAC": "MO", "MKD": "MK", "MDG": "MG", "MWI": "MW",
        "MYS": "MY", "MDV": "MV", "MLI": "ML", "MLT": "MT", "MHL": "MH",
        "MTQ": "MQ", "MRT": "MR", "MUS": "MU", "MYT": "YT", "MEX": "MX",
        "FSM": "FM", "MDA": "MD", "MCO": "MC", "MNG": "MN", "MNE": "ME",
        "MSR": "MS", "MAR": "MA", "MOZ": "MZ", "MMR": "MM", "NAM": "NA",
        "NRU": "NR", "NPL": "NP", "NLD": "NL", "NCL": "NC", "NZL": "NZ",
        "NIC": "NI", "NER": "NE", "NGA": "NG", "NIU": "NU", "NFK": "NF",
        "MNP": "MP", "NOR": "NO", "OMN": "OM", "PAK": "PK", "PLW": "PW",
        "PSE": "PS", "PAN": "PA", "PNG": "PG", "PRY": "PY", "PER": "PE",
        "PHL": "PH", "PCN": "PN", "POL": "PL", "PRT": "PT", "PRI": "PR",
        "QAT": "QA", "REU": "RE", "ROU": "RO", "RUS": "RU", "RWA": "RW",
        "BLM": "BL", "SHN": "SH", "KNA": "KN", "LCA": "LC", "MAF": "MF",
        "SPM": "PM", "VCT": "VC", "WSM": "WS", "SMR": "SM", "STP": "ST",
        "SAU": "SA", "SEN": "SN", "SRB": "RS", "SYC": "SC", "SLE": "SL",
        "SGP": "SG", "SXM": "SX", "SVK": "SK", "SVN": "SI", "SLB": "SB",
        "SOM": "SO", "ZAF": "ZA", "SGS": "GS", "SSD": "SS", "ESP": "ES",
        "LKA": "LK", "SDN": "SD", "SUR": "SR", "SJM": "SJ", "SWE": "SE",
        "CHE": "CH", "SYR": "SY", "TWN": "TW", "TJK": "TJ", "TZA": "TZ",
        "THA": "TH", "TLS": "TL", "TGO": "TG", "TKL": "TK", "TON": "TO",
        "TTO": "TT", "TUN": "TN", "TUR": "TR", "TKM": "TM", "TCA": "TC",
        "TUV": "TV", "UGA": "UG", "UKR": "UA", "ARE": "AE", "GBR": "GB",
        "USA": "US", "UMI": "UM", "URY": "UY", "UZB": "UZ", "VUT": "VU",
        "VEN": "VE", "VNM": "VN", "VGB": "VG", "VIR": "VI", "WLF": "WF",
        "ESH": "EH", "YEM": "YE", "ZMB": "ZM", "ZWE": "ZW",
    ]
}
