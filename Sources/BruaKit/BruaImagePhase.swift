#if canImport(SwiftUI)
import SwiftUI

/// Where a `BruaImage` is, as `AsyncImage` names it (docs/superpowers/specs/2026-11-05-brua-image-phases-design.md).
public enum BruaImagePhase {
    /// The asset's JSON or its file is loading; there is nothing to show yet.
    case empty
    /// The file is here, already resizable; `BruaImage` frames it for the asset's fit.
    case success(Image)
    /// Why there is no picture.
    case failure(BruaImageError)

    /// The image when the phase is `success`.
    public var image: Image? {
        if case .success(let image) = self { image } else { nil }
    }

    /// The reason when the phase is `failure`.
    public var error: BruaImageError? {
        if case .failure(let error) = self { error } else { nil }
    }
}

/// Why a `BruaImage` has no picture. The same reasons on every platform's SDK.
public enum BruaImageError: Error {
    /// Nothing is released under the id: the edge answered 404. Usually a call site draws nothing.
    case notReleased
    /// The edge can't be reached and no release of the id is known.
    case unreachable(any Error)
    /// The asset is known, but its file failed to load or decode.
    case file(URL, any Error)
}

/// The loading and failure views of the simpler `BruaImage` initializers, with the success image as it is.
public struct BruaPhaseContent<Placeholder: View, Failure: View>: View {
    let phase: BruaImagePhase
    let placeholder: Placeholder
    let failure: (BruaImageError) -> Failure

    public var body: some View {
        switch phase {
        case .empty: placeholder
        case .success(let image): image
        case .failure(let error): failure(error)
        }
    }
}

/// How far a `BruaImage` has got with the asset itself, before its file.
enum BruaAssetState {
    case loading
    case loaded(AssetResponse)
    case failed(BruaImageError)
}

/// The phase logic, apart from the view so it can be tested without SwiftUI.
enum BruaImageResolution {
    /// Before anything is read: the asset when it is embedded or remembered, else loading.
    static func initial(embedded: AssetResponse?, remembered: AssetResponse?) -> BruaAssetState {
        if let asset = embedded ?? remembered { .loaded(asset) } else { .loading }
    }

    /// The current release of the id. The client keeps the last known release when the edge can't be reached, so a
    /// thrown error means none is known.
    static func read(_ id: String, client: BruaClient) async -> BruaAssetState {
        do {
            if let asset = try await client.asset(id) { return .loaded(asset) }
            return .failed(.notReleased)
        } catch {
            return .failed(.unreachable(error))
        }
    }

    /// The file's phase on the first frame: a file in the loader's memory draws at once.
    static func initial(file url: URL, loader: any BruaImageLoader) -> BruaImagePhase {
        if let image = loader.cached(url) { .success(image.resizable()) } else { .empty }
    }

    /// The file once loaded, or why it couldn't be.
    static func load(file url: URL, loader: any BruaImageLoader) async -> BruaImagePhase {
        do {
            return .success(try await loader.load(url).resizable())
        } catch {
            return .failure(.file(url, error))
        }
    }
}
#endif
