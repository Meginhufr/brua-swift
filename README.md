# BruaKit

Brua for iOS and macOS: `AssetResponse` models, the variant selection rule, request hints and a SwiftUI view. iOS 16 and macOS 13 or later.

Add it with Swift Package Manager, in Xcode (File → Add Package Dependencies…) or in `Package.swift`:

```swift
.package(url: "https://github.com/Meginhufr/brua-swift", from: "0.1.0")
```

```swift
import BruaKit

// Your backend passes asset ids on; the app reads each asset's current release from the edge, with no key.
// One client per app, with your organization's asset prefix. URLSession's cache keeps each asset for the
// edge's minute, and a merge in Brua reaches the screen within that minute with no release of yours.
let brua = BruaClient(base: URL(string: "https://cdn.brua.dev/assets/<your organization id>")!)

// Follows dark mode, Reduce Motion and the display scale; alt text is the VoiceOver label.
// The placeholder shows until the asset has loaded, and when nothing is released under the id.
BruaImage(id: theme.thumbnailId, client: brua)
    .frame(width: 160)

// Or a snapshot your backend embedded in its own JSON, decoded with your other models.
struct GiftTheme: Decodable {
    let title: String
    let thumbnail: AssetResponse
}

BruaImage(theme.thumbnail)
    .frame(width: 160)

// Or choose the URL yourself, for example for a custom image loader.
let url = VariantSelector.url(for: theme.thumbnail, client: ClientState(colorScheme: .dark, scale: 3, targetWidth: 160))

// Send the hints with requests to your backend, which forwards them to the delivery API.
var request = URLRequest(url: backendURL)
BruaHints.apply(to: &request, colorScheme: nil, reducedMotion: UIAccessibility.isReduceMotionEnabled)
```

Pass `colorScheme: nil` if the app follows the system appearance live: the backend then returns both schemes and `BruaImage` switches without a new request (`SPEC.md` 5.6).

Animations show their still. To play Lottie or Rive, add their type to `supportedTypes` and render those variants with the animation library.

Tests run the shared fixtures in `fixtures/selection`: `swift test`.
