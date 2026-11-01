import Foundation

/// What the selection rule needs to know about the device and the view.
public struct ClientState: Codable, Hashable, Sendable {
    public enum ColorScheme: String, Codable, Sendable { case light, dark }

    /// Media types this app can render, most preferred first.
    public var supportedTypes: [String]
    public var colorScheme: ColorScheme
    public var reducedMotion: Bool
    /// Device pixels per point.
    public var scale: Double
    /// Displayed width in points, for flexible assets.
    public var targetWidth: Double?

    public init(supportedTypes: [String] = ClientState.defaultTypes, colorScheme: ColorScheme = .light,
                reducedMotion: Bool = false, scale: Double = 1, targetWidth: Double? = nil) {
        self.supportedTypes = supportedTypes
        self.colorScheme = colorScheme
        self.reducedMotion = reducedMotion
        self.scale = scale
        self.targetWidth = targetWidth
    }

    /// Formats Apple's image decoders handle on the supported OS versions; animation types are added by apps
    /// that register a renderer for them.
    public static let defaultTypes = ["image/avif", "image/webp", "image/png", "image/jpeg"]
}

/// The variant selection rule (SPEC.md 7.3), tested against the shared fixtures in `fixtures/selection`.
public enum VariantSelector {
    private static let knownColorSchemes: Set<String> = ["light", "dark"]
    private static let knownReducedMotion: Set<String> = ["reduce"]

    /// The URL to load: the chosen variant's, or the asset's single URL when no variant fits.
    public static func url(for asset: AssetResponse, client: ClientState) -> URL {
        variant(for: asset, client: client)?.url ?? asset.url
    }

    public static func variant(for asset: AssetResponse, client: ClientState) -> AssetVariant? {
        // 1. Usable: a supported type, and no value this client doesn't know.
        var candidates = asset.variants.filter { variant in
            client.supportedTypes.contains(variant.type)
                && (variant.prefersColorScheme.map(knownColorSchemes.contains) ?? true)
                && (variant.prefersReducedMotion.map(knownReducedMotion.contains) ?? true)
        }

        // 2. Motion.
        let reduced = candidates.filter { $0.prefersReducedMotion == "reduce" }
        let moving = candidates.filter { $0.prefersReducedMotion == nil }
        if client.reducedMotion {
            if !reduced.isEmpty { candidates = reduced }
        } else if !moving.isEmpty {
            candidates = moving
        }

        // 3. Color scheme.
        candidates = firstNonEmpty(
            candidates.filter { $0.prefersColorScheme == client.colorScheme.rawValue },
            candidates.filter { $0.prefersColorScheme == nil },
            candidates.filter { $0.prefersColorScheme == "light" },
            candidates)

        // 4. Language.
        candidates = firstNonEmpty(
            candidates.filter { $0.lang != nil && $0.lang == asset.lang },
            candidates.filter { $0.lang == nil },
            candidates)

        // 5. Type.
        guard let type = client.supportedTypes.first(where: { type in candidates.contains { $0.type == type } }) else { return nil }
        candidates = candidates.filter { $0.type == type }

        // 6. Size.
        if candidates.contains(where: { $0.scale != nil }) {
            return pickAtLeast(candidates, value: { Double($0.scale ?? 1) }, target: client.scale)
        }
        if candidates.contains(where: { $0.pixelWidth != nil }) {
            let need = client.targetWidth.map { $0 * client.scale } ?? .infinity
            return pickAtLeast(candidates, value: { Double($0.pixelWidth ?? 0) }, target: need)
        }
        return candidates.first
    }

    private static func firstNonEmpty(_ lists: [AssetVariant]...) -> [AssetVariant] {
        lists.first { !$0.isEmpty } ?? []
    }

    /// The smallest value at or above `target`, else the largest.
    private static func pickAtLeast(_ variants: [AssetVariant], value: (AssetVariant) -> Double, target: Double) -> AssetVariant? {
        let sorted = variants.sorted { value($0) < value($1) }
        return sorted.first { value($0) >= target } ?? sorted.last
    }
}
