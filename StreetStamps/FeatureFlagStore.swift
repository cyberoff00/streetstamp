import Foundation
import StoreKit

@MainActor
final class FeatureFlagStore: ObservableObject {
    static let shared = FeatureFlagStore()

    @Published private(set) var socialEnabled: Bool = true
    @Published private(set) var hasFetched: Bool = false

    private let socialOverrideKey = "streetstamps.feature.social_enabled_override"

    private init() {
        if let override = UserDefaults.standard.object(forKey: socialOverrideKey) as? Bool {
            socialEnabled = override
        }
    }

    func fetchFlags() async {
        let region = await resolveStorefrontRegion()
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
                hasFetched = true
                return
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let social = json["social"] as? Bool {
                    socialEnabled = social
                }
            }
        } catch {
            // Keep cached/default value on network failure.
        }
        hasFetched = true
    }

    private func resolveStorefrontRegion() async -> String? {
        if #available(iOS 15.0, *) {
            do {
                if let storefront = try await Storefront.current {
                    return storefront.countryCode
                }
            } catch {
                // Fallback below.
            }
        }
        return Locale.current.region?.identifier
    }
}
