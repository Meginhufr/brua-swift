import Foundation
import Testing
@testable import BruaKit

private struct Fixture: Decodable {
    let description: String
    let asset: AssetResponse
    let client: ClientState
    let expected: URL
}

/// The shared fixtures: beside the package in its own repository, two levels further up in the platform's.
private let fixturesDirectory: URL = {
    let tests = URL(filePath: #filePath).deletingLastPathComponent()
    return ["../../fixtures/selection", "../../../../fixtures/selection"]
        .map { tests.appending(path: $0).standardized }
        .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }!
}()

private func fixtureNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: fixturesDirectory.path(percentEncoded: false))
        .filter { $0.hasSuffix(".json") }
        .sorted()
}

@Test("Every shared fixture selects the expected URL", arguments: try fixtureNames())
func fixture(_ name: String) throws {
    let data = try Data(contentsOf: fixturesDirectory.appending(path: name))
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    #expect(VariantSelector.url(for: fixture.asset, client: fixture.client) == fixture.expected, "\(fixture.description)")
}

@Test func fieldsAddedToTheContractLaterAreIgnored() throws {
    let json = #"{"id":"a","version":1,"url":"https://cdn.test/a/1","width":1,"height":1,"alt":"","futureField":true,"variants":[{"type":"image/png","url":"https://cdn.test/a/1/1.png","newSelector":"x"}]}"#
    let asset = try JSONDecoder().decode(AssetResponse.self, from: Data(json.utf8))
    #expect(asset.isDecorative)
    #expect(asset.variants.count == 1)
}

@Test func hintsUseQuotedValuesAndDecreasingQuality() {
    var request = URLRequest(url: URL(string: "https://api.example.com")!)
    BruaHints.apply(to: &request, colorScheme: .dark, reducedMotion: true, preferredLanguages: ["nb-NO", "en"])
    #expect(request.value(forHTTPHeaderField: "Accept-Language") == "nb-NO, en;q=0.9")
    #expect(request.value(forHTTPHeaderField: "Sec-CH-Prefers-Color-Scheme") == "\"dark\"")
    #expect(request.value(forHTTPHeaderField: "Sec-CH-Prefers-Reduced-Motion") == "\"reduce\"")
    #expect(request.value(forHTTPHeaderField: "Asset-Contract") == "1")
}
