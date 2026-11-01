import Foundation
import Testing
@testable import BruaKit

/// Answers the icon's URL with its JSON, anything else with 404, and remembers what was asked for.
private final class EdgeStub: URLProtocol {
    nonisolated(unsafe) static var requests: [URL] = []

    static let icon = #"{"id":"icon","version":3,"url":"https://cdn.example/assets/icon","width":24,"height":24,"alt":"Settings","lang":"en","variants":[{"type":"image/png","url":"https://cdn.example/assets/icon/3/light@1x.png","scale":1}]}"#

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requests.append(url)
        let known = url.path.hasSuffix("/icon.json")
        let response = HTTPURLResponse(url: url, statusCode: known ? 200 : 404, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((known ? Self.icon : "Unknown asset").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func anIdIsReadFromTheEdgeWithTheLanguageInTheURLAndAnUnknownOneIsNil() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EdgeStub.self]
    let base = "https://cdn.example/assets/0f8fad5b-d9cb-469f-a165-70867728950e"
    let client = BruaClient(base: URL(string: base)!, lang: "nb", session: URLSession(configuration: configuration))

    let icon = try await client.asset("icon")
    let missing = try await client.asset("nothing-released")

    #expect(icon?.alt == "Settings")
    #expect(icon?.variants.count == 1)
    #expect(missing == nil)
    #expect(EdgeStub.requests.map(\.absoluteString) == ["\(base)/icon.json?lang=nb", "\(base)/nothing-released.json?lang=nb"])
}

@Test func withoutALanguageTheURLHasNoQuery() {
    let client = BruaClient(base: URL(string: "https://cdn.example/assets/org/")!)
    #expect(client.url(for: "icon").absoluteString == "https://cdn.example/assets/org/icon.json")
}
