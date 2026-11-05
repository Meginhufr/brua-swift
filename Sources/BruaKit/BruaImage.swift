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
/// Given an id instead of an asset, the current release is read from the edge through a `BruaClient`, so a
/// merge reaches this image within a minute with no backend involved. A release the client has read before draws
/// on the first frame, so a cell scrolled back into view doesn't flash its placeholder, and it stays when a newer
/// one can't be read; the placeholder shows until the first release has loaded, and when nothing is released.
public struct BruaImage<Placeholder: View>: View {
    private enum Source {
        case embedded(AssetResponse)
        case reference(String, BruaClient)
    }

    private let source: Source
    private let supportedTypes: [String]
    private let objectFit: String?
    private let objectPosition: String?
    private let placeholder: Placeholder

    @State private var loaded: AssetResponse?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// The asset as your backend embedded it: a snapshot of one release.
    public init(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes,
                objectFit: String? = nil, objectPosition: String? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.source = .embedded(asset)
        self.supportedTypes = supportedTypes
        self.objectFit = objectFit
        self.objectPosition = objectPosition
        self.placeholder = placeholder()
    }

    /// The asset with this id, in its current release.
    public init(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes,
                objectFit: String? = nil, objectPosition: String? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.source = .reference(id, client)
        self.supportedTypes = supportedTypes
        self.objectFit = objectFit
        self.objectPosition = objectPosition
        self.placeholder = placeholder()
        self._loaded = State(initialValue: client.cachedAsset(id))
    }

    private var asset: AssetResponse? {
        switch source {
        case .embedded(let asset): asset
        case .reference: loaded
        }
    }

    private var referenceId: String? {
        if case .reference(let id, _) = source { id } else { nil }
    }

    public var body: some View {
        Group {
            if let asset {
                picture(asset)
            } else {
                placeholder
            }
        }
        .task(id: referenceId) {
            guard case .reference(let id, let client) = source else { return }
            loaded = client.cachedAsset(id)
            // The client keeps the last known release when the edge can't be reached, so nil here means nothing
            // is released under the id, or nothing has ever been read of it.
            loaded = try? await client.asset(id)
        }
    }

    private func picture(_ asset: AssetResponse) -> some View {
        Group {
            if BruaLayout.objectFit(of: asset, override: objectFit) == .cover {
                cover(asset)
            } else {
                contain(asset)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(asset.alt))
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(asset.isDecorative)
    }

    /// The asset's own proportions, the picture fitted in them.
    private func contain(_ asset: AssetResponse) -> some View {
        GeometryReader { geometry in
            AsyncImage(url: url(for: asset, width: geometry.size.width)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    placeholder
                }
            }
        }
        .aspectRatio(CGFloat(asset.width) / CGFloat(max(asset.height, 1)), contentMode: .fit)
    }

    /// The frame the view is given, filled: the picture drawn at the size that fills it and placed at the position, as
    /// CSS object-position places it, then clipped. SwiftUI's own `.fill` would always crop from the centre.
    private func cover(_ asset: AssetResponse) -> some View {
        GeometryReader { geometry in
            let box = geometry.size
            let rect = BruaLayout.rect(for: asset, in: box, objectFit: ObjectFit.cover.rawValue, objectPosition: objectPosition)
            let width = BruaLayout.targetWidth(asset: asset, boxWidth: box.width, boxHeight: box.height, objectFit: ObjectFit.cover.rawValue)
            AsyncImage(url: url(for: asset, width: width)) { phase in
                if let image = phase.image {
                    image.resizable().frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                } else {
                    placeholder.frame(width: box.width, height: box.height)
                }
            }
            .frame(width: box.width, height: box.height, alignment: .topLeading)
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

public extension BruaImage where Placeholder == Color {
    init(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes, objectFit: String? = nil, objectPosition: String? = nil) {
        self.init(asset, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { Color.secondary.opacity(0.1) }
    }

    init(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes, objectFit: String? = nil, objectPosition: String? = nil) {
        self.init(id: id, client: client, supportedTypes: supportedTypes, objectFit: objectFit, objectPosition: objectPosition) { Color.secondary.opacity(0.1) }
    }
}
#endif
