import SwiftUI
import CommonCrypto

/// Shared image loader with two-tier cache: NSCache (memory) + custom disk cache.
/// Guarantees:
/// - Instant display when returning to a previously viewed image (memory hit)
/// - Fast display after app relaunch (disk hit, no network)
/// - Reliable offline access for all previously viewed images
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
            // Check our own disk cache (reliable, survives URLCache eviction)
            if let diskData = RemoteImageDiskCache.shared.read(for: url),
               let decoded = UIImage(data: diskData) {
                RemoteImageCache.shared.setImage(decoded, for: url)
                uiImage = decoded
                return
            }
            do {
                let data = try await RemoteImageFetcher.shared.data(for: url)
                guard let decoded = UIImage(data: data) else {
                    failed = true
                    return
                }
                RemoteImageCache.shared.setImage(decoded, for: url)
                RemoteImageDiskCache.shared.write(data, for: url)
                uiImage = decoded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

/// In-memory cache for decoded UIImages.
final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()

    private let memoryCache = NSCache<NSURL, UIImage>()

    private init() {
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

/// Centralized remote-image byte fetcher.
/// - Bounded timeouts prevent stuck requests from piling up behind default 60s/7day limits.
/// - In-flight de-duplication collapses concurrent fetches of the same URL
///   into one network round-trip (common when a list renders many cells sharing one URL).
/// - A single shared URLSession keeps DNS/TLS connections warm across the app.
actor RemoteImageFetcher {
    static let shared = RemoteImageFetcher()

    private let session: URLSession
    private var inFlight: [URL: Task<Data, Error>] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func data(for url: URL) async throws -> Data {
        if let existing = inFlight[url] {
            return try await existing.value
        }
        let task = Task<Data, Error>.detached(priority: .utility) { [session] in
            let (data, _) = try await session.data(from: url)
            return data
        }
        inFlight[url] = task
        // Clear the entry based on the underlying fetch, not the awaiter.
        // An awaiter's cancellation must not drop the in-flight record while
        // the detached fetch is still running for other awaiters.
        Task { [weak self] in
            _ = try? await task.value
            await self?.remove(url)
        }
        return try await task.value
    }

    private func remove(_ url: URL) {
        inFlight[url] = nil
    }

    /// Fire-and-forget prefetch into the disk cache. Errors are silent.
    /// Skips URLs already on disk; in-flight de-dup keeps overlap with on-demand
    /// fetches (scrolling into view while prewarming) to a single network request.
    nonisolated func prewarm(_ urls: [URL]) {
        for url in urls {
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                if RemoteImageDiskCache.shared.read(for: url) != nil { return }
                if let data = try? await self.data(for: url) {
                    RemoteImageDiskCache.shared.write(data, for: url)
                }
            }
        }
    }
}

/// Custom disk cache stored in Application Support (not Caches, so iOS won't purge it).
/// Uses SHA-256 hashed filenames keyed by URL. LRU eviction at 200 MB cap.
final class RemoteImageDiskCache: @unchecked Sendable {
    static let shared = RemoteImageDiskCache()

    private let directory: URL
    private let maxBytes: Int = 200 * 1024 * 1024 // 200 MB
    private let ioQueue = DispatchQueue(label: "RemoteImageDiskCache.io", qos: .utility)

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("RemoteImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func read(for url: URL) -> Data? {
        let path = filePath(for: url)
        guard let data = FileManager.default.contents(atPath: path.path) else { return nil }
        // Touch access date so LRU eviction keeps recently read files.
        ioQueue.async {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: path.path
            )
        }
        return data
    }

    func write(_ data: Data, for url: URL) {
        let path = filePath(for: url)
        ioQueue.async { [directory, maxBytes] in
            try? data.write(to: path, options: .atomic)
            // Evict oldest files when over budget.
            Self.evictIfNeeded(directory: directory, maxBytes: maxBytes)
        }
    }

    private static func evictIfNeeded(directory: URL, maxBytes: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var entries: [(url: URL, size: Int, date: Date)] = []
        var totalSize = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { continue }
            let date = values.contentModificationDate ?? .distantPast
            entries.append((file, size, date))
            totalSize += size
        }

        guard totalSize > maxBytes else { return }

        // Sort oldest first for LRU eviction.
        entries.sort { $0.date < $1.date }
        for entry in entries {
            guard totalSize > maxBytes else { break }
            try? fm.removeItem(at: entry.url)
            totalSize -= entry.size
        }
    }

    private func filePath(for url: URL) -> URL {
        let hash = sha256(url.absoluteString)
        return directory.appendingPathComponent(hash)
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
