import CoreGraphics
import Foundation

/// Coordinates refer to the full source after its preferred direction transform, with a top-left origin.
nonisolated struct ClipFraming: Codable, Equatable, Sendable {
    let scale: Double
    let centerX: Double
    let centerY: Double

    static let original = Self(scale: 1, centerX: 0.5, centerY: 0.5)

    /// Keep persisted input unchanged so validation can detect corrupt or noncanonical values.
    init(scale: Double, centerX: Double, centerY: Double) {
        self.scale = scale
        self.centerX = centerX
        self.centerY = centerY
    }

    /// Apply at UI input boundaries, never while decoding persisted values.
    var normalized: Self {
        let finiteScale = scale.isFinite ? scale : 1
        let scale = (min(max(finiteScale, 1), 4) * 10).rounded() / 10
        let edge = 1 / (2 * scale)
        return Self(scale: scale,
            centerX: Self.normalizedCenter(centerX, edge: edge),
            centerY: Self.normalizedCenter(centerY, edge: edge))
    }

    var isValid: Bool {
        scale.isFinite && centerX.isFinite && centerY.isFinite
            && (1...4).contains(scale) && self == normalized
    }

    var normalizedCropRect: CGRect {
        guard isValid else { return .null }
        let side = 1 / scale
        return CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
    }

    private static func normalizedCenter(_ value: Double, edge: Double) -> Double {
        let value = value.isFinite ? value : 0.5
        // A clamped boundary may have more than five decimals. Preserve it on subsequent normalization.
        if value <= edge { return edge }
        if value >= 1 - edge { return 1 - edge }
        return min(max((value * 100_000).rounded() / 100_000, edge), 1 - edge)
    }
}

nonisolated enum ClipFramingGeometry {
    /// The bounds retain the transform's origin; translate by its negative to make an upright zero-origin image.
    static func uprightBounds(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGRect {
        guard validSize(naturalSize),
              [preferredTransform.a, preferredTransform.b, preferredTransform.c,
               preferredTransform.d, preferredTransform.tx, preferredTransform.ty].allSatisfy(\.isFinite)
        else { return .null }
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
        return validBounds(bounds) ? bounds : .null
    }

    static func aspectFitRect(sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        guard validSize(sourceSize), validBounds(bounds) else { return .zero }
        let factor = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * factor, height: sourceSize.height * factor)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    /// Returns a top-left-origin crop in upright source coordinates, retaining the bounds' origin.
    /// Player letterboxing is excluded. Invalid persisted framing returns null instead of being repaired.
    static func cropRect(framing: ClipFraming, in uprightBounds: CGRect) -> CGRect {
        guard framing.isValid, validBounds(uprightBounds) else { return .null }
        let crop = framing.normalizedCropRect
        return CGRect(x: uprightBounds.minX + crop.minX * uprightBounds.width,
            y: uprightBounds.minY + crop.minY * uprightBounds.height,
            width: crop.width * uprightBounds.width, height: crop.height * uprightBounds.height)
    }

    private static func validSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func validBounds(_ bounds: CGRect) -> Bool {
        !bounds.isNull && !bounds.isInfinite && bounds.origin.x.isFinite && bounds.origin.y.isFinite && validSize(bounds.size)
    }
}
