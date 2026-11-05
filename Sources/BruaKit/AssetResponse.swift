import Foundation

/// The asset contract (SPEC.md 5): the HTML picture model as JSON. Decodes with synthesized `Codable`.
public struct AssetResponse: Codable, Hashable, Sendable {
    public let id: String
    public let version: Int
    public let url: URL
    public let width: Int
    public let height: Int
    /// Empty for decorative assets, which VoiceOver skips.
    public let alt: String
    public let lang: String?
    public let variants: [AssetVariant]
    /// How a layout's box of another shape holds the asset, as CSS object-fit: "contain" or "cover".
    public let objectFit: String?
    /// Where it sits in the box, as CSS object-position: "50% 35%", the point a cover crop keeps in view.
    public let objectPosition: String?

    public init(id: String, version: Int, url: URL, width: Int, height: Int, alt: String, lang: String?, variants: [AssetVariant],
                objectFit: String? = nil, objectPosition: String? = nil) {
        self.id = id
        self.version = version
        self.url = url
        self.width = width
        self.height = height
        self.alt = alt
        self.lang = lang
        self.variants = variants
        self.objectFit = objectFit
        self.objectPosition = objectPosition
    }

    public var isDecorative: Bool { alt.isEmpty }
}

/// Value fields are strings, not enums, so a value added to the API later never breaks decoding (SPEC.md 14).
public struct AssetVariant: Codable, Hashable, Sendable {
    public let type: String
    public let url: URL
    public let prefersColorScheme: String?
    public let prefersReducedMotion: String?
    public let lang: String?
    public let scale: Int?
    public let pixelWidth: Int?

    public init(type: String, url: URL, prefersColorScheme: String? = nil, prefersReducedMotion: String? = nil,
                lang: String? = nil, scale: Int? = nil, pixelWidth: Int? = nil) {
        self.type = type
        self.url = url
        self.prefersColorScheme = prefersColorScheme
        self.prefersReducedMotion = prefersReducedMotion
        self.lang = lang
        self.scale = scale
        self.pixelWidth = pixelWidth
    }
}
