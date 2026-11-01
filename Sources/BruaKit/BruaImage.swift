#if canImport(SwiftUI)
import SwiftUI

/// Shows a Brua asset in SwiftUI: the variant follows dark mode, Reduce Motion and the display scale
/// as they change, alt text becomes the VoiceOver label, and decorative assets are hidden from VoiceOver.
/// Animations show their still; apps render animation types themselves (SPEC.md 7.2).
///
/// Given an id instead of an asset, the current release is read from the edge through a `BruaClient`, so a
/// merge reaches this image within a minute with no backend involved; the placeholder shows until it has
/// loaded, and when nothing is released under the id.
public struct BruaImage<Placeholder: View>: View {
    private enum Source {
        case embedded(AssetResponse)
        case reference(String, BruaClient)
    }

    private let source: Source
    private let supportedTypes: [String]
    private let placeholder: Placeholder

    @State private var loaded: AssetResponse?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// The asset as your backend embedded it: a snapshot of one release.
    public init(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes,
                @ViewBuilder placeholder: () -> Placeholder) {
        self.source = .embedded(asset)
        self.supportedTypes = supportedTypes
        self.placeholder = placeholder()
    }

    /// The asset with this id, in its current release.
    public init(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes,
                @ViewBuilder placeholder: () -> Placeholder) {
        self.source = .reference(id, client)
        self.supportedTypes = supportedTypes
        self.placeholder = placeholder()
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
            loaded = try? await client.asset(id)
        }
    }

    private func picture(_ asset: AssetResponse) -> some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(asset.alt))
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(asset.isDecorative)
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
    init(_ asset: AssetResponse, supportedTypes: [String] = ClientState.defaultTypes) {
        self.init(asset, supportedTypes: supportedTypes) { Color.secondary.opacity(0.1) }
    }

    init(id: String, client: BruaClient, supportedTypes: [String] = ClientState.defaultTypes) {
        self.init(id: id, client: client, supportedTypes: supportedTypes) { Color.secondary.opacity(0.1) }
    }
}
#endif
