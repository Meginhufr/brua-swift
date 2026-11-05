#if canImport(SwiftUI)
import SwiftUI

/// Shows a Brua asset in SwiftUI: the variant follows dark mode, Reduce Motion and the display scale
/// as they change, alt text becomes the VoiceOver label, and decorative assets are hidden from VoiceOver.
/// Animations show their still; apps render animation types themselves (SPEC.md 7.2).
///
/// The asset's `objectFit` decides the shape: `contain` takes the asset's proportions, as an image with
/// `.aspectRatio(contentMode: .fit)`; `cover` fills the frame you give it and crops around the asset's
/// `objectPosition`, choosing a file sharp enough for the size it is drawn at. `objectFit:` and `objectPosition:`
/// override the asset's.
///
/// Like `AsyncImage`, it takes a placeholder, a placeholder and a failure view, or a closure that gets the phase
/// (`BruaImagePhase`). Whatever it returns is laid out where the picture goes, so a loading view takes the picture's
/// place; the success image comes resizable. Files load through the environment's `bruaImageLoader`, which caches
/// them on disk and in memory unless the app sets its own.
///
/// Given an id instead of an asset, the current release is read from the edge through a `BruaClient`, so a
/// merge reaches this image within a minute with no backend involved. A release the client has read before, and a
/// file the loader has in memory, draw on the first frame, so a cell scrolled back into view doesn't flash.
public struct BruaImage<Content: View>: View {
    private enum Source {
        case embedded(AssetResponse)
        case reference(String, BruaClient)
    }

    private let source: Source
    private let supportedTypes: [String]
    private let objectFit: String?
    private let objectPosition: String?
    private let content: (BruaImagePhase) -> Content

    @State private var state: BruaAssetState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.bruaImageLoader) private var loader

    /// The asset as your backend embedded it, with every phase drawn by `content`.
    public init(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes,
                objectFit: String? = nil, objectPosition: String? = nil,
                @ViewBuilder content: @escaping (BruaImagePhase) -> Content) {
        self.source = .embedded(asset)
        self.supportedTypes = supportedTypes
        self.objectFit = objectFit
        self.objectPosition = objectPosition
        self.content = content
        self._state = State(initialValue: BruaImageResolution.initial(embedded: asset, remembered: nil))
    }

    /// The asset with this id in its current release, with every phase drawn by `content`.
    public init(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes,
                objectFit: String? = nil, objectPosition: String? = nil,
                @ViewBuilder content: @escaping (BruaImagePhase) -> Content) {
        self.source = .reference(id, client)
        self.supportedTypes = supportedTypes
        self.objectFit = objectFit
        self.objectPosition = objectPosition
        self.content = content
        self._state = State(initialValue: BruaImageResolution.initial(embedded: nil, remembered: client.cachedAsset(id)))
    }

    private var referenceId: String? {
        if case .reference(let id, _) = source { id } else { nil }
    }

    public var body: some View {
        Group {
            switch state {
            case .loaded(let asset): picture(asset)
            case .loading: content(.empty)
            case .failed(let error): content(.failure(error))
            }
        }
        .task(id: referenceId) {
            guard case .reference(let id, let client) = source else { return }
            if let remembered = client.cachedAsset(id) { state = .loaded(remembered) }
            state = await BruaImageResolution.read(id, client: client)
        }
    }

    @ViewBuilder
    private func picture(_ asset: AssetResponse) -> some View {
        if BruaLayout.objectFit(of: asset, override: objectFit) == .cover {
            cover(asset)
        } else {
            contain(asset)
        }
    }

    /// The asset's own proportions, every phase filling them.
    private func contain(_ asset: AssetResponse) -> some View {
        GeometryReader { geometry in
            let box = geometry.size
            BruaFile(url: url(for: asset, width: box.width), asset: asset, loader: loader, content: content) { view, _ in
                view.frame(width: box.width, height: box.height)
            }
        }
        .aspectRatio(CGFloat(asset.width) / CGFloat(max(asset.height, 1)), contentMode: .fit)
    }

    /// The frame the view is given, filled: the picture drawn at the size that fills it and placed at the position, as
    /// CSS object-position places it, then clipped. SwiftUI's own `.fill` would always crop from the centre. Loading and
    /// failure views fill the frame.
    private func cover(_ asset: AssetResponse) -> some View {
        GeometryReader { geometry in
            let box = geometry.size
            let rect = BruaLayout.rect(for: asset, in: box, objectFit: ObjectFit.cover.rawValue, objectPosition: objectPosition)
            let width = BruaLayout.targetWidth(asset: asset, boxWidth: box.width, boxHeight: box.height, objectFit: ObjectFit.cover.rawValue)
            BruaFile(url: url(for: asset, width: width), asset: asset, loader: loader, content: content) { view, isImage in
                if isImage {
                    view.frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                        .frame(width: box.width, height: box.height, alignment: .topLeading)
                } else {
                    view.frame(width: box.width, height: box.height)
                }
            }
        }
        .clipped()
    }

    private func url(for asset: AssetResponse, width: CGFloat) -> URL {
        VariantSelector.url(for: asset, client: ClientState(
            supportedTypes: supportedTypes,
            colorScheme: colorScheme == .dark ? .dark : .light,
            reducedMotion: reduceMotion,
            scale: displayScale,
            targetWidth: width > 0 ? width : nil))
    }
}

/// One file of a known asset: drawn from the loader's memory on the first frame when it is there, else loaded; while
/// another file of the same asset loads (dark mode switched on, a wider box), the one before stays on screen.
private struct BruaFile<Content: View, Placed: View>: View {
    let url: URL
    let asset: AssetResponse
    let loader: any BruaImageLoader
    let content: (BruaImagePhase) -> Content
    let place: (Content, Bool) -> Placed

    @State private var phase: BruaImagePhase

    init(url: URL, asset: AssetResponse, loader: any BruaImageLoader, content: @escaping (BruaImagePhase) -> Content,
         @ViewBuilder place: @escaping (Content, Bool) -> Placed) {
        self.url = url
        self.asset = asset
        self.loader = loader
        self.content = content
        self.place = place
        self._phase = State(initialValue: BruaImageResolution.initial(file: url, loader: loader))
    }

    var body: some View {
        let isImage = phase.image != nil
        place(content(phase), isImage)
            .modifier(AltText(asset: asset, shown: isImage))
            .task(id: url) {
                let first = BruaImageResolution.initial(file: url, loader: loader)
                if first.image != nil || phase.image == nil { phase = first }
                phase = await BruaImageResolution.load(file: url, loader: loader)
            }
    }
}

/// The alt text as the VoiceOver label once the picture shows, and a decorative asset hidden; the call site's loading
/// and failure views are read as they are.
private struct AltText: ViewModifier {
    let asset: AssetResponse
    let shown: Bool

    func body(content: Content) -> some View {
        if shown {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(asset.alt))
                .accessibilityAddTraits(.isImage)
                .accessibilityHidden(asset.isDecorative)
        } else {
            content
        }
    }
}

public extension BruaImage {
    /// The embedded asset, with a placeholder while loading and a failure view.
    init<Placeholder: View, Failure: View>(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes,
                                           objectFit: String? = nil, objectPosition: String? = nil,
                                           @ViewBuilder placeholder: () -> Placeholder,
                                           @ViewBuilder failure: @escaping (BruaImageError) -> Failure)
    where Content == BruaPhaseContent<Placeholder, Failure> {
        let placeholder = placeholder()
        self.init(asset, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { phase in
            BruaPhaseContent(phase: phase, placeholder: placeholder, failure: failure)
        }
    }

    /// The asset with this id, with a placeholder while loading and a failure view.
    init<Placeholder: View, Failure: View>(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes,
                                           objectFit: String? = nil, objectPosition: String? = nil,
                                           @ViewBuilder placeholder: () -> Placeholder,
                                           @ViewBuilder failure: @escaping (BruaImageError) -> Failure)
    where Content == BruaPhaseContent<Placeholder, Failure> {
        let placeholder = placeholder()
        self.init(id: id, client: client, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { phase in
            BruaPhaseContent(phase: phase, placeholder: placeholder, failure: failure)
        }
    }

    /// The embedded asset, with one view while loading and on failure.
    init<Placeholder: View>(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes,
                            objectFit: String? = nil, objectPosition: String? = nil,
                            @ViewBuilder placeholder: () -> Placeholder)
    where Content == BruaPhaseContent<Placeholder, Placeholder> {
        let placeholder = placeholder()
        self.init(asset, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { phase in
            BruaPhaseContent(phase: phase, placeholder: placeholder, failure: { _ in placeholder })
        }
    }

    /// The asset with this id, with one view while loading and on failure.
    init<Placeholder: View>(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes,
                            objectFit: String? = nil, objectPosition: String? = nil,
                            @ViewBuilder placeholder: () -> Placeholder)
    where Content == BruaPhaseContent<Placeholder, Placeholder> {
        let placeholder = placeholder()
        self.init(id: id, client: client, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { phase in
            BruaPhaseContent(phase: phase, placeholder: placeholder, failure: { _ in placeholder })
        }
    }
}

public extension BruaImage where Content == BruaPhaseContent<Color, Color> {
    /// The embedded asset, with a light grey box while loading and on failure.
    init(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes, objectFit: String? = nil, objectPosition: String? = nil) {
        self.init(asset, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { Color.secondary.opacity(0.1) }
    }

    /// The asset with this id, with a light grey box while loading and on failure.
    init(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes, objectFit: String? = nil, objectPosition: String? = nil) {
        self.init(id: id, client: client, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { Color.secondary.opacity(0.1) }
    }
}
#endif
