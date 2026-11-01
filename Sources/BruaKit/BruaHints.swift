import Foundation

/// The headers an app sends to its own backend, which forwards them to the delivery API (SPEC.md 7.5).
public enum BruaHints {
    /// The contract version this SDK implements (SPEC.md 14).
    public static let contractVersion = "1"

    /// Adds Accept-Language, the color scheme and reduced motion hints, and the contract version.
    /// Leave `colorScheme` nil if the app follows the system appearance live, so the backend returns both schemes.
    public static func apply(to request: inout URLRequest, colorScheme: ClientState.ColorScheme?, reducedMotion: Bool,
                             preferredLanguages: [String] = Locale.preferredLanguages) {
        request.setValue(acceptLanguage(preferredLanguages), forHTTPHeaderField: "Accept-Language")
        if let colorScheme {
            request.setValue("\"\(colorScheme.rawValue)\"", forHTTPHeaderField: "Sec-CH-Prefers-Color-Scheme")
        }
        request.setValue(reducedMotion ? "\"reduce\"" : "\"no-preference\"", forHTTPHeaderField: "Sec-CH-Prefers-Reduced-Motion")
        request.setValue(contractVersion, forHTTPHeaderField: "Asset-Contract")
    }

    /// "nb-NO, en;q=0.9": the app's languages in order, with falling quality values.
    static func acceptLanguage(_ languages: [String]) -> String {
        languages.prefix(5).enumerated().map { index, language in
            index == 0 ? language : "\(language);q=\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), 1.0 - Double(index) * 0.1))"
        }.joined(separator: ", ")
    }
}
