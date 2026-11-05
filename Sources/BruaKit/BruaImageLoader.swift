#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Loads a `BruaImage`'s files. Set one for a view tree with `.bruaImageLoader(_:)`, for example to share an app's own
/// image cache and prefetch; without it, `BruaDefaultImageLoader.shared` loads them. The URLs are Brua's versioned files,
/// which never change, so a loader may keep what it loaded for as long as it likes.
public protocol BruaImageLoader: Sendable {
    /// The image at this URL when it is already in memory, else nil. Called on the first frame, so it must not wait.
    func cached(_ url: URL) -> Image?
    /// Loads the file; throws when it can't be loaded or decoded.
    func load(_ url: URL) async throws -> Image
}

/// The loader `BruaImage` uses unless told otherwise: files cached on disk in a URL cache of BruaKit's own
/// (`URLSession.brua`, apart from the app's other responses), decoded images in memory, and one request per file at a
/// time however many views ask for it.
public final class BruaDefaultImageLoader: BruaImageLoader, @unchecked Sendable {
    /// The loader every `BruaImage` uses by default, on `URLSession.brua`.
    public static let shared = BruaDefaultImageLoader(session: .brua)

    private let session: URLSession
    private let memory = NSCache<NSURL, Decoded>()
    private let lock = NSLock()
    private var loads: [URL: Task<Decoded, Error>] = [:]

    /// A decoded file. Nothing changes an image once it is decoded, so it may cross threads, whichever OS version
    /// marks the platform's image type Sendable.
    private final class Decoded: @unchecked Sendable {
        let image: PlatformImage
        init(_ image: PlatformImage) { self.image = image }
    }

    /// A loader with other cache sizes, in bytes. Use it instead of `shared`, not beside it: both keep their files in
    /// `Library/Caches/BruaKit`.
    public convenience init(diskCapacity: Int, memoryCapacity: Int) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: diskCapacity, directory: URLSession.bruaCacheDirectory)
        self.init(session: URLSession(configuration: configuration), memoryCapacity: memoryCapacity)
    }

    init(session: URLSession, memoryCapacity: Int = 50 * 1024 * 1024) {
        self.session = session
        memory.totalCostLimit = memoryCapacity
    }

    public func cached(_ url: URL) -> Image? {
        memory.object(forKey: url as NSURL).map { Image(platform: $0.image) }
    }

    public func load(_ url: URL) async throws -> Image {
        if let decoded = memory.object(forKey: url as NSURL) { return Image(platform: decoded.image) }
        let task = lock.withLock {
            if let running = loads[url] { return running }
            let task = Task { try await fetch(url) }
            loads[url] = task
            return task
        }
        defer { lock.withLock { loads[url] = nil } }
        return Image(platform: try await task.value.image)
    }

    private func fetch(_ url: URL) async throws -> Decoded {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard let image = PlatformImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        let decoded = Decoded(image)
        memory.setObject(decoded, forKey: url as NSURL, cost: data.count)
        return decoded
    }
}

extension Image {
    init(platform image: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}

public extension EnvironmentValues {
    /// The loader `BruaImage` loads its files with. Set it with `.bruaImageLoader(_:)`.
    @Entry var bruaImageLoader: any BruaImageLoader = BruaDefaultImageLoader.shared
}

public extension View {
    /// Loads every `BruaImage` below through this loader, such as one wrapping the app's own image cache.
    func bruaImageLoader(_ loader: any BruaImageLoader) -> some View {
        environment(\.bruaImageLoader, loader)
    }
}
#endif
