import Foundation

/// Reads the current release of an asset from the edge by its id: the `AssetResponse` at `{base}/{id}.json`, with
/// no key and no backend (SPEC.md 5.3). The session's cache honours the edge's minute, so a screen with a hundred
/// references costs one small request per asset, and a merge still lands within the minute.
public struct BruaClient: Sendable {
    /// The organization's asset prefix on the edge, such as `https://cdn.brua.dev/assets/{org}`.
    public let base: URL
    /// The language for alt text and language-specific files; nil lets the device's languages decide.
    public let lang: String?
    private let session: URLSession

    public init(base: URL, lang: String? = nil, session: URLSession = .shared) {
        self.base = base
        self.lang = lang
        self.session = session
    }

    /// The JSON URL of the asset's current release.
    public func url(for id: String) -> URL {
        var components = URLComponents(url: base.appending(path: "\(id).json"), resolvingAgainstBaseURL: false)!
        if let lang {
            components.queryItems = [URLQueryItem(name: "lang", value: lang)]
        }
        return components.url!
    }

    /// The asset's current release, or nil when the id is unknown or nothing is released.
    public func asset(_ id: String) async throws -> AssetResponse? {
        let (data, response) = try await session.data(from: url(for: id))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(AssetResponse.self, from: data)
    }
}
