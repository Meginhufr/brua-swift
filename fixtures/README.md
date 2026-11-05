# Selection and sizing fixtures

The shared test cases for the variant selection rule (`SPEC.md` 7.3 and 8). Every implementation runs all of them: the web SDK and edge Worker (`sdk/web`), the Swift SDK (`sdk/swift`), the .NET SDK (`sdk/dotnet`) and the Kotlin SDK (`sdk/kotlin`). A change to the rule is a fixture change first.

Each file in `selection/` has:

- `asset`: an `AssetResponse`.
- `client`: the client's state: `supportedTypes` in order of preference, `colorScheme` (`light` or `dark`), `reducedMotion`, the display `scale`, and an optional `targetWidth` in CSS pixels.
- `expected`: the URL the client must load.

## The rule

1. **Usable:** keep variants whose `type` is in `supportedTypes` and whose known fields only hold known values (`prefersColorScheme`: `light`, `dark`; `prefersReducedMotion`: `reduce`). A value a client doesn't know means the variant isn't for it (`SPEC.md` 14).
2. **Motion:** with reduced motion, keep the variants marked `reduce` if there are any. Without it, drop them if anything else remains.
3. **Color scheme:** keep the variants for the client's scheme; if there are none, those without a scheme; if none either, the light ones.
4. **Language:** keep the variants in the asset's `lang`; if there are none, those without a language.
5. **Type:** keep the client's most preferred type among what's left.
6. **Size:** for `scale`, the smallest at or above the display scale, else the largest. For `pixelWidth`, the smallest at or above `targetWidth × scale`, else the largest; without a target, the largest.
7. If nothing is left, the asset's `url`.

## Sizing

The fixtures in `sizing/` are for the step before the rule: how wide a picture is drawn in its box, which the
components pass to the rule as `targetWidth` (`docs/superpowers/specs/2026-11-05-object-fit-design.md`). Each has:

- `asset`: the asset's `width`, `height` and, when it has one, `objectFit`.
- `box`: the layout box's `width` and, once it is known, `height`, in CSS pixels or points.
- `objectFit`: the call site's override, when it gives one.
- `expected`: the width the picture is drawn at.

The fit is the override, else the asset's `objectFit`, else `contain`. With `contain`, or without a box height above
zero, it is the box width. With `cover` it is the larger of the box width and the box height times the asset's
`width / height`: a cover picture is drawn larger than its box in one direction, and needs a file for that size.
