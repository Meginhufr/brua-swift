import Foundation
import SwiftUI
import Testing
@testable import BruaKit

/// Answers `/ok.png` with a one-pixel PNG, `/broken.png` with bytes that aren't an image and anything else with 404,
/// counting the requests per path. Tests run in parallel, so each uses paths of its own.
private final class FileStub: URLProtocol {
    static let counts = Counter()
    // A 1×1 transparent PNG.
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg==")!

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.counts.add(url.path)
        let (status, body): (Int, Data) = url.path.hasSuffix("ok.png") ? (200, Self.png)
            : url.path.hasSuffix("broken.png") ? (200, Data("not an image".utf8)) : (404, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func add(_ key: String) { lock.withLock { values[key, default: 0] += 1 } }
    func count(_ key: String) -> Int { lock.withLock { values[key] ?? 0 } }
}

private func stubLoader() -> BruaDefaultImageLoader {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FileStub.self]
    return BruaDefaultImageLoader(session: URLSession(configuration: configuration))
}

@Test func theDefaultLoaderKeepsAFileInMemoryAndLoadsItOnceForEveryoneAskingAtOnce() async throws {
    let loader = stubLoader()
    let url = URL(string: "https://cdn.test/a/1/once-ok.png")!

    #expect(loader.cached(url) == nil)
    async let first = loader.load(url)
    async let second = loader.load(url)
    _ = try await (first, second)
    #expect(FileStub.counts.count(url.path) == 1)
    #expect(loader.cached(url) != nil, "the next frame draws it at once")

    _ = try await loader.load(url)
    #expect(FileStub.counts.count(url.path) == 1, "from memory, not the network")
}

@Test func theDefaultLoaderFailsOnAStatusAndOnAFileThatIsntAnImage() async {
    let loader = stubLoader()
    await #expect(throws: URLError.self) { try await loader.load(URL(string: "https://cdn.test/a/1/missing.png")!) }
    await #expect(throws: URLError.self) { try await loader.load(URL(string: "https://cdn.test/a/1/broken.png")!) }
}

@Test func aFileInMemoryIsTheFirstPhaseAndALoadedOneSucceedsOrSaysWhichFileFailed() async {
    let loader = stubLoader()
    let ok = URL(string: "https://cdn.test/a/1/phase-ok.png")!
    let missing = URL(string: "https://cdn.test/a/1/phase-missing.png")!

    #expect(BruaImageResolution.initial(file: ok, loader: loader).image == nil)
    #expect(await BruaImageResolution.load(file: ok, loader: loader).image != nil)
    #expect(BruaImageResolution.initial(file: ok, loader: loader).image != nil)

    guard case .failure(.file(let url, _)) = await BruaImageResolution.load(file: missing, loader: loader) else {
        Issue.record("a missing file is a file failure")
        return
    }
    #expect(url == missing)
}

@Test func anEmbeddedOrRememberedAssetIsLoadedAtOnceAndOtherwiseLoading() {
    let asset = AssetResponse(id: "a", version: 1, url: URL(string: "https://cdn.test/a/1")!, width: 1, height: 1, alt: "", lang: nil, variants: [])
    guard case .loaded = BruaImageResolution.initial(embedded: asset, remembered: nil),
          case .loaded = BruaImageResolution.initial(embedded: nil, remembered: asset),
          case .loading = BruaImageResolution.initial(embedded: nil, remembered: nil) else {
        Issue.record("the first state follows what is known")
        return
    }
}

@Test func anIdWithNothingReleasedIsNotReleasedAndAnUnreachableEdgeSaysSo() async {
    let released = client("phases.example")
    guard case .loaded = await BruaImageResolution.read("icon", client: released),
          case .failed(.notReleased) = await BruaImageResolution.read("nothing-released", client: released) else {
        Issue.record("a released id loads, an unknown one is not released")
        return
    }

    EdgeStub.failing.withLock { _ = $0.insert("down.example") }
    guard case .failed(.unreachable) = await BruaImageResolution.read("icon", client: client("down.example")) else {
        Issue.record("no connection and nothing known is unreachable")
        return
    }
}

@Test func fileURLsAreWhatBruaImageWouldChooseForTheBox() async {
    let brua = client("files.example")
    let urls = await brua.fileURLs(for: ["icon", "nothing-released"], state: ClientState(supportedTypes: ["image/png"], scale: 1), boxWidth: 24)

    #expect(urls == ["icon": URL(string: "https://cdn.example/assets/icon/3/light@1x.png")!])
}

/// The four ways to call BruaImage, as an app writes them: this only has to compile.
@MainActor
@Test func everyFormOfBruaImageCompiles() {
    let brua = client("forms.example")
    _ = BruaImage(id: "icon", client: brua)
    _ = BruaImage(id: "icon", client: brua) { ProgressView() }
    _ = BruaImage(id: "icon", client: brua) {
        ProgressView()
    } failure: { error in
        if case .notReleased = error { EmptyView() } else { Image(systemName: "photo") }
    }
    _ = BruaImage(id: "icon", client: brua) { phase in
        switch phase {
        case .empty: Color.gray
        case .success(let image): image
        case .failure: Image(systemName: "photo")
        }
    }
    _ = Color.clear.bruaImageLoader(BruaDefaultImageLoader.shared)
}
