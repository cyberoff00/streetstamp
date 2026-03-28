import SwiftUI

/// Shared image loader with two-tier cache: NSCache (memory) + URLCache (disk).
/// Replaces AsyncImage for all remote image loading to guarantee:
/// - Instant display when returning to a previously viewed image (memory hit)
/// - Fast display after app relaunch (disk hit, no network)
/// - Automatic LRU eviction under memory pressure (NSCache) and disk cap (URLCache)
struct CachedRemoteImage<Placeholder: View, Failure: View>: View {
    let url: URL
    let placeholder: () -> Placeholder
    let failure: () -> Failure
    let content: (Image) -> Image

    @State private var uiImage: UIImage?
    @State private var failed = false

    init(
        url: URL,
        @ViewBuilder content: @escaping (Image) -> Image = { $0 },
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else if failed {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            if let cached = RemoteImageCache.shared.image(for: url) {
                uiImage = cached
                return
            }
            do {
                let (data, _) = try await RemoteImageCache.shared.session.data(from: url)
                guard let decoded = UIImage(data: data) else {
                    failed = true
                    return
                }
                RemoteImageCache.shared.setImage(decoded, for: url)
                uiImage = decoded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

/// Two-tier cache: NSCache for decoded UIImages, URLCache for raw HTTP responses.
final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()

    let session: URLSession
    private let memoryCache = NSCache<NSURL, UIImage>()

    private init() {
        let urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,   // 8 MB RAM for raw responses
            diskCapacity: 100 * 1024 * 1024     // 100 MB disk
        )
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)

        memoryCache.countLimit = 80
        memoryCache.totalCostLimit = 40 * 1024 * 1024  // ~40 MB decoded
    }

    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func setImage(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}
