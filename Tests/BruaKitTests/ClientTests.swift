import Foundation
import Testing
@testable import BruaKit

/// A value behind a lock, for state the stub and the tests share across threads.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T { lock.withLock { body(&value) } }
}

/// Answers `/icon.json` with the icon's JSON and anything else with 404, and fails as a lost connection on the
/// hosts in `failing`. Remembers what was asked for per host, since tests run in parallel.
private final class EdgeStub: URLProtocol {
    static let requests = Locked<[String: [URL]]>([:])
    static let failing = Locked<Set<String>>([])

    static let icon = #"{"id":"icon","version":3,"url":"https://cdn.example/assets/icon","width":24,"height":24,"alt":"Settings","lang":"en","variants":[{"type":"image/png","url":"https://cdn.example/assets/icon/3/light@1x.png","scale":1}]}"#

    static func requests(to host: String) -> [URL] { requests.withLock { $0[host] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requests.withLock { $0[url.host!, default: []].append(url) }
        if Self.failing.withLock({ $0.contains(url.host!) }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let known = url.path.hasSuffix("/icon.json")
        let response = HTTPURLResponse(url: url, statusCode: known ? 200 : 404, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json", "Cache-Control": "public, max-age=60"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((known ? Self.icon : "Unknown asset").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A clock the test moves by hand.
private final class Clock: @unchecked Sendable {
    private let time = Locked(Date(timeIntervalSince1970: 1_800_000_000))
    var now: Date { time.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { time.withLock { $0 += seconds } }
}

private func client(_ host: String, lang: String? = "nb", clock: Clock = Clock(), languages: [String] = ["nb-NO", "en"]) -> BruaClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EdgeStub.self]
    return BruaClient(base: URL(string: "https://\(host)/assets/0f8fad5b-d9cb-469f-a165-70867728950e")!, lang: lang,
                      session: URLSession(configuration: configuration), preferredLanguages: { languages }, now: { clock.now })
}

@Test func anIdIsReadFromTheEdgeWithTheLanguageInTheURLAndAnUnknownOneIsNil() async throws {
    let brua = client("read.example")

    let icon = try await brua.asset("icon")
    let missing = try await brua.asset("nothing-released")

    #expect(icon?.alt == "Settings")
    #expect(icon?.variants.count == 1)
    #expect(missing == nil)
    let base = "https://read.example/assets/0f8fad5b-d9cb-469f-a165-70867728950e"
    #expect(EdgeStub.requests(to: "read.example").map(\.absoluteString) == ["\(base)/icon.json?lang=nb", "\(base)/nothing-released.json?lang=nb"])
}

@Test func withoutALanguageTheURLCarriesTheDevicesLanguagesSoEachHasItsOwnCacheEntry() throws {
    let nb = client("lang.example", lang: nil, languages: ["nb-NO", "en"]).url(for: "icon")
    let en = client("lang.example", lang: nil, languages: ["en-US", "nb"]).url(for: "icon")

    let query = try #require(URLComponents(url: nb, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query == [URLQueryItem(name: "lang", value: "nb-NO, en;q=0.9")])
    #expect(nb != en)
}

@Test func aReleaseUnderAMinuteOldIsAnsweredFromMemoryAndOneOlderIsReadAgain() async throws {
    let clock = Clock()
    let brua = client("fresh.example", clock: clock)

    #expect(brua.cachedAsset("icon") == nil)
    _ = try await brua.asset("icon")
    clock.advance(30)
    _ = try await brua.asset("icon")
    #expect(EdgeStub.requests(to: "fresh.example").count == 1)
    #expect(brua.cachedAsset("icon")?.alt == "Settings")

    clock.advance(31)
    _ = try await brua.asset("icon")
    #expect(EdgeStub.requests(to: "fresh.example").count == 2)
}

@Test func anIdWithNothingReleasedIsRememberedForTheMinuteToo() async throws {
    let brua = client("missing.example")

    _ = try await brua.asset("nothing-released")
    _ = try await brua.asset("nothing-released")

    #expect(EdgeStub.requests(to: "missing.example").count == 1)
}

@Test func readsOfOneIdAtTheSameTimeShareOneRequest() async throws {
    let brua = client("shared.example")

    async let first = brua.asset("icon")
    async let second = brua.asset("icon")
    let (a, b) = try await (first, second)

    #expect(a == b)
    #expect(EdgeStub.requests(to: "shared.example").count == 1)
}

@Test func aStaleReleaseIsServedWhenTheRefreshFails() async throws {
    let clock = Clock()
    let brua = client("flaky.example", clock: clock)
    _ = try await brua.asset("icon")

    EdgeStub.failing.withLock { _ = $0.insert("flaky.example") }
    clock.advance(120)
    let kept = try await brua.asset("icon")

    #expect(kept?.alt == "Settings")
    #expect(EdgeStub.requests(to: "flaky.example").count == 2)
}

@Test func withNoReleaseKnownAFailedReadThrows() async {
    EdgeStub.failing.withLock { _ = $0.insert("offline.example") }
    let brua = client("offline.example")

    await #expect(throws: URLError.self) { try await brua.asset("icon") }
}

@Test func prefetchReadsEveryIdOnceSoTheyAreInMemory() async {
    let brua = client("prefetch.example")

    await brua.prefetch(["icon", "icon", "nothing-released"])

    #expect(brua.cachedAsset("icon")?.alt == "Settings")
    #expect(EdgeStub.requests(to: "prefetch.example").count == 2)
}

@Test func copiesOfAClientShareWhatItRemembers() async throws {
    let brua = client("copies.example")
    let copy = brua

    _ = try await brua.asset("icon")

    #expect(copy.cachedAsset("icon")?.alt == "Settings")
}
