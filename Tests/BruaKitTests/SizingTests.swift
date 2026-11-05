import CoreGraphics
import Foundation
import Testing
@testable import BruaKit

/// The fixtures give only the asset's size and fit; the rest of the contract isn't part of the rule.
private struct SizingFixture: Decodable {
    struct Asset: Decodable { let width: Int; let height: Int; let objectFit: String? }
    struct Box: Decodable { let width: Double; let height: Double? }
    let description: String
    let asset: Asset
    let box: Box
    let objectFit: String?
    let expected: Double
}

private let sizingDirectory: URL = {
    let tests = URL(filePath: #filePath).deletingLastPathComponent()
    return ["../../fixtures/sizing", "../../../../fixtures/sizing"]
        .map { tests.appending(path: $0).standardized }
        .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }!
}()

private func sizingNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: sizingDirectory.path(percentEncoded: false)).filter { $0.hasSuffix(".json") }.sorted()
}

private func asset(width: Int, height: Int, objectFit: String? = nil, objectPosition: String? = nil) -> AssetResponse {
    AssetResponse(id: "a", version: 1, url: URL(string: "https://cdn.test/a/1")!, width: width, height: height, alt: "", lang: nil, variants: [],
                  objectFit: objectFit, objectPosition: objectPosition)
}

@Test("Every shared sizing fixture draws at the expected width", arguments: try sizingNames())
func sizing(_ name: String) throws {
    let fixture = try JSONDecoder().decode(SizingFixture.self, from: Data(contentsOf: sizingDirectory.appending(path: name)))
    let given = asset(width: fixture.asset.width, height: fixture.asset.height, objectFit: fixture.asset.objectFit)
    #expect(BruaLayout.targetWidth(asset: given, boxWidth: fixture.box.width, boxHeight: fixture.box.height, objectFit: fixture.objectFit) == fixture.expected,
            "\(fixture.description)")
}

@Test func coverFillsTheBoxAndKeepsThePositionsPointInView() {
    // A 4:3 photo in a square: drawn 400 × 300 in a 300 × 300 box, 100 points to crop across.
    let photo = asset(width: 960, height: 720, objectFit: "cover", objectPosition: "25% 50%")
    let rect = BruaLayout.rect(for: photo, in: CGSize(width: 300, height: 300))
    #expect(rect == CGRect(x: -25, y: 0, width: 400, height: 300))
    #expect(BruaLayout.rect(for: photo, in: CGSize(width: 300, height: 300), objectPosition: "100% 50%").minX == -100, "the right edge kept in view")
}

@Test func containFitsTheBoxAndAnUnknownPositionIsTheCentre() {
    let photo = asset(width: 960, height: 720, objectFit: "contain", objectPosition: "top")
    #expect(BruaLayout.rect(for: photo, in: CGSize(width: 300, height: 300)) == CGRect(x: 0, y: 37.5, width: 300, height: 225))
    #expect(BruaLayout.objectFit(of: asset(width: 1, height: 1, objectFit: "fill")) == .contain)
}
