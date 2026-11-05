import CoreGraphics
import Foundation

/// How a picture fills its box, as CSS object-fit names it.
public enum ObjectFit: String, Sendable {
    /// The whole picture, with space around it in a box of another shape.
    case contain
    /// The box filled, the rest of the picture cropped.
    case cover
}

/// How a picture fills its box and where it is drawn, the same on every platform (fixtures/sizing). `targetWidth` is
/// the step before the selection rule, so a cover picture gets a file sharp enough for the size it is drawn at;
/// `rect` is where to draw it, for SwiftUI's `BruaImage` and for UIKit views alike.
public enum BruaLayout {
    /// The fit to draw with: the override, else the asset's, else contain. Unknown values are contain.
    public static func objectFit(of asset: AssetResponse, override: String? = nil) -> ObjectFit {
        (override ?? asset.objectFit) == "cover" ? .cover : .contain
    }

    /// Where the picture sits in its box, as fractions from 0 to 1: the override, else the asset's, else the centre.
    public static func objectPosition(of asset: AssetResponse, override: String? = nil) -> CGPoint {
        parse(override ?? asset.objectPosition) ?? CGPoint(x: 0.5, y: 0.5)
    }

    /// How wide the picture is drawn in a box of this size, in points, for `ClientState.targetWidth`. Contain, or a box
    /// without a height yet, draws it at the box width; cover at the larger of the box width and the box height times
    /// the asset's proportions.
    public static func targetWidth(asset: AssetResponse, boxWidth: Double, boxHeight: Double? = nil, objectFit override: String? = nil) -> Double {
        guard objectFit(of: asset, override: override) == .cover, let boxHeight, boxHeight > 0, asset.height > 0 else { return boxWidth }
        return max(boxWidth, boxHeight * Double(asset.width) / Double(asset.height))
    }

    /// Where to draw the picture in a box of this size: scaled to fill it (cover) or to fit in it (contain), and placed
    /// at the position as CSS places it, so cover shows no gap and keeps the position's point in view.
    public static func rect(for asset: AssetResponse, in box: CGSize, objectFit override: String? = nil, objectPosition: String? = nil) -> CGRect {
        guard asset.width > 0, asset.height > 0, box.width > 0, box.height > 0 else { return CGRect(origin: .zero, size: box) }
        let scaleX = box.width / CGFloat(asset.width), scaleY = box.height / CGFloat(asset.height)
        let scale = objectFit(of: asset, override: override) == .cover ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let size = CGSize(width: CGFloat(asset.width) * scale, height: CGFloat(asset.height) * scale)
        let position = self.objectPosition(of: asset, override: objectPosition)
        return CGRect(x: (box.width - size.width) * position.x, y: (box.height - size.height) * position.y, width: size.width, height: size.height)
    }

    /// "50% 35%" as fractions, or nil when it isn't two whole percentages from 0 to 100.
    private static func parse(_ position: String?) -> CGPoint? {
        guard let parts = position?.split(separator: " "), parts.count == 2 else { return nil }
        let values = parts.compactMap { part -> Int? in
            guard part.hasSuffix("%"), let value = Int(part.dropLast()), (0...100).contains(value) else { return nil }
            return value
        }
        return values.count == 2 ? CGPoint(x: CGFloat(values[0]) / 100, y: CGFloat(values[1]) / 100) : nil
    }
}
