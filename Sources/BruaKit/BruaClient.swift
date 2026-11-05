import Foundation

/// Reads the current release of an asset from the edge by its id: the `AssetResponse` at `{base}/{id}.json`, with
/// no key and no backend (SPEC.md 5.3).
///
/// The client remembers every release it has read. A release under the edge's minute old is answered from memory,
/// an older one is read again (URLSession revalidates it with its ETag), and when the edge can't be reached the
/// last known release is kept, so a merge lands within the minute and a screen still shows its images offline.
/// `cachedAsset(_:)` gives the last known release at once, for a view's first frame. Copies of a client share
/// what it remembers.
public struct BruaClient: Sendable {
    /// The organization's asset prefix on the edge, such as `https://cdn.brua.dev/assets/{org}`.
    public let base: URL
    /// The language for alt text and language-specific files; nil lets the device's languages decide.
    public let lang: String?
    private let session: URLSession
    private let store = AssetStore()
    private let preferredLanguages: @Sendable () -> [String]
    private let now: @Sendable () -> Date

    public init(base: URL, lang: String? = nil, session: URLSession = .brua) {
        self.init(base: base, lang: lang, session: session, preferredLanguages: { Locale.preferredLanguages }, now: { Date() })
    }

    init(base: URL, lang: String?, session: URLSession, preferredLanguages: @escaping @Sendable () -> [String],
         now: @escaping @Sendable () -> Date) {
        self.base = base
        self.lang = lang
        self.session = session
        self.preferredLanguages = preferredLanguages
        self.now = now
    }

    /// The JSON URL of the asset's current release. Without `lang` it carries the device's languages, so each
    /// language has its own entry in URLCache, which doesn't key on `Vary`.
    public func url(for id: String) -> URL {
        var components = URLComponents(url: base.appending(path: "\(id).json"), resolvingAgainstBaseURL: false)!
        let languages = lang ?? BruaHints.acceptLanguage(preferredLanguages())
        if !languages.isEmpty {
            components.queryItems = [URLQueryItem(name: "lang", value: languages)]
        }
        return components.url!
    }

    /// The asset's current release, or nil when the id is unknown or nothing is released. Reads of one id at the
    /// same time share a request. Throws only when the edge can't be reached and no release of it is known.
    public func asset(_ id: String) async throws -> AssetResponse? {
        let url = url(for: id)
        if let known = store.entry(url), now() < known.freshUntil { return known.asset }
        do {
            return try await store.load(url) {
                let (asset, freshFor) = try await read(url)
                return AssetStore.Entry(asset: asset, freshUntil: now().addingTimeInterval(freshFor))
            }.asset
        } catch {
            if let known = store.entry(url) { return known.asset }
            throw error
        }
    }

    /// The last release of the id this client has read, however old, or nil when it hasn't read one. For a view
    /// to draw at once while `asset(_:)` checks for a newer release.
    public func cachedAsset(_ id: String) -> AssetResponse? {
        store.entry(url(for: id))?.asset
    }

    /// The file each id's current release draws with in a box of this size, chosen as `BruaImage` chooses it: for an
    /// app's own loader to prefetch. Ids with nothing released, or that can't be read, are left out.
    public func fileURLs(for ids: [String], state: ClientState, boxWidth: Double? = nil, boxHeight: Double? = nil,
                         objectFit: String? = nil) async -> [String: URL] {
        await prefetch(ids)
        var urls: [String: URL] = [:]
        for id in Set(ids) {
            guard let asset = cachedAsset(id) else { continue }
            var client = state
            if let boxWidth {
                client.targetWidth = BruaLayout.targetWidth(asset: asset, boxWidth: boxWidth, boxHeight: boxHeight, objectFit: objectFit)
            }
            urls[id] = VariantSelector.url(for: asset, client: client)
        }
        return urls
    }

    /// Reads these ids at the same time, so a list's images draw at once when its cells appear.
    public func prefetch(_ ids: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for id in Set(ids) {
                group.addTask { _ = try? await asset(id) }
            }
        }
    }

    /// The release at this URL and how long it stays fresh, from the response's `max-age`. Offline, URLCache's
    /// last copy is used however old, so an app started without a connection still has what it read before.
    private func read(_ url: URL) async throws -> (AssetResponse?, TimeInterval) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            guard let cached = session.configuration.urlCache?.cachedResponse(for: URLRequest(url: url)) else { throw error }
            (data, response) = (cached.data, cached.response)
        }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let freshFor = Self.maxAge(http.value(forHTTPHeaderField: "Cache-Control")) ?? 60
        if http.statusCode == 404 { return (nil, freshFor) }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return (try JSONDecoder().decode(AssetResponse.self, from: data), freshFor)
    }

    static func maxAge(_ cacheControl: String?) -> TimeInterval? {
        guard let cacheControl else { return nil }
        for directive in cacheControl.split(separator: ",") {
            let parts = directive.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "max-age", let seconds = TimeInterval(parts[1]) { return seconds }
        }
        return nil
    }
}

/// The releases a client has read, by JSON URL, and the reads under way, so one id is read once at a time.
final class AssetStore: @unchecked Sendable {
    struct Entry: Sendable {
        let asset: AssetResponse?
        let freshUntil: Date
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]
    private var reads: [URL: Task<Entry, Error>] = [:]

    func entry(_ url: URL) -> Entry? {
        lock.withLock { entries[url] }
    }

    /// Runs `read` for this URL, or joins the read already under way, and keeps what it returns.
    func load(_ url: URL, _ read: @escaping @Sendable () async throws -> Entry) async throws -> Entry {
        let task = lock.withLock {
            if let running = reads[url] { return running }
            let task = Task { try await read() }
            reads[url] = task
            return task
        }
        do {
            let entry = try await task.value
            lock.withLock {
                entries[url] = entry
                reads[url] = nil
            }
            return entry
        } catch {
            lock.withLock { reads[url] = nil }
            throw error
        }
    }
}

public extension URLSession {
    /// BruaKit's own session, for the asset JSON and the files: a URL cache in `Library/Caches/BruaKit`, apart from
    /// `URLSession.shared`'s, so Brua's files and an app's other responses don't push each other out. The files are
    /// immutable, so a cached one is served without the network, offline too and after a relaunch; the system may clear
    /// the folder when storage runs low, since everything in it can be fetched again.
    static let brua: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, directory: bruaCacheDirectory)
        return URLSession(configuration: configuration)
    }()

    /// Where BruaKit's URL cache keeps its files.
    static var bruaCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "BruaKit")
    }
}
