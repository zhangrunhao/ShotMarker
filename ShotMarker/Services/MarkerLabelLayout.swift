import CoreGraphics
import Foundation

nonisolated enum MarkerLabelLayout {
    static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard isValid(contentSize), isValid(bounds.size) else {
            return bounds
        }

        let scale = min(
            bounds.width / contentSize.width,
            bounds.height / contentSize.height,
        )
        let fittedSize = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale,
        )
        return CGRect(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height,
        )
    }

    static func clampedOrigin(
        for normalizedCenter: CGPoint,
        labelSize: CGSize,
        in frame: CGRect,
    ) -> CGPoint {
        guard isValid(frame.size) else {
            return frame.origin
        }

        let center = CGPoint(
            x: frame.minX + clampedUnit(normalizedCenter.x) * frame.width,
            y: frame.minY + clampedUnit(normalizedCenter.y) * frame.height,
        )
        return CGPoint(
            x: clampedOrigin(
                center: center.x,
                labelLength: max(labelSize.width, 0),
                minimum: frame.minX,
                maximum: frame.maxX,
            ),
            y: clampedOrigin(
                center: center.y,
                labelLength: max(labelSize.height, 0),
                minimum: frame.minY,
                maximum: frame.maxY,
            ),
        )
    }

    static func previewCenter(
        for normalizedCenter: CGPoint,
        labelSize: CGSize,
        in frame: CGRect,
    ) -> CGPoint {
        let origin = clampedOrigin(
            for: normalizedCenter,
            labelSize: labelSize,
            in: frame,
        )
        return CGPoint(
            x: origin.x + max(labelSize.width, 0) / 2,
            y: origin.y + max(labelSize.height, 0) / 2,
        )
    }

    static func normalizedCenter(
        forPreviewPoint point: CGPoint,
        labelSize: CGSize,
        in frame: CGRect,
    ) -> CGPoint {
        guard isValid(frame.size) else {
            return CGPoint(
                x: CGFloat(MarkerLabelStyle.default.normalizedCenterX),
                y: CGFloat(MarkerLabelStyle.default.normalizedCenterY),
            )
        }

        let proposed = CGPoint(
            x: (point.x - frame.minX) / frame.width,
            y: (point.y - frame.minY) / frame.height,
        )
        let clampedCenter = previewCenter(
            for: proposed,
            labelSize: labelSize,
            in: frame,
        )
        return CGPoint(
            x: (clampedCenter.x - frame.minX) / frame.width,
            y: (clampedCenter.y - frame.minY) / frame.height,
        )
    }

    static func coreImageOrigin(
        for normalizedCenter: CGPoint,
        labelSize: CGSize,
        in imageExtent: CGRect,
    ) -> CGPoint {
        let localFrame = CGRect(origin: .zero, size: imageExtent.size)
        let topLeftOrigin = clampedOrigin(
            for: normalizedCenter,
            labelSize: labelSize,
            in: localFrame,
        )
        return CGPoint(
            x: imageExtent.minX + topLeftOrigin.x,
            y: imageExtent.maxY - topLeftOrigin.y - max(labelSize.height, 0),
        )
    }

    private static func clampedOrigin(
        center: CGFloat,
        labelLength: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
    ) -> CGFloat {
        guard labelLength < maximum - minimum else {
            return (minimum + maximum - labelLength) / 2
        }

        return min(max(center - labelLength / 2, minimum), maximum - labelLength)
    }

    private static func clampedUnit(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }

        return min(max(value, 0), 1)
    }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
    }
}
