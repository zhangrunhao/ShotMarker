import Foundation

/// Position and size on the final output canvas, with a top-left origin.
nonisolated struct MarkerLabelPlacement: Codable, Equatable, Sendable {
    let fontSizeRatio: Double
    let normalizedCenterX: Double
    let normalizedCenterY: Double

    init(fontSizeRatio: Double, normalizedCenterX: Double, normalizedCenterY: Double) {
        self.fontSizeRatio = fontSizeRatio
        self.normalizedCenterX = normalizedCenterX
        self.normalizedCenterY = normalizedCenterY
    }

    init(style: MarkerLabelStyle) {
        self.init(fontSizeRatio: style.fontSizeRatio, normalizedCenterX: style.normalizedCenterX,
            normalizedCenterY: style.normalizedCenterY)
    }

    var isValid: Bool {
        fontSizeRatio.isFinite && normalizedCenterX.isFinite && normalizedCenterY.isFinite
            && MarkerLabelStyle.fontSizeRatioRange.contains(fontSizeRatio)
            && MarkerLabelStyle.normalizedCenterRange.contains(normalizedCenterX)
            && MarkerLabelStyle.normalizedCenterRange.contains(normalizedCenterY)
    }

    /// Normalize only user input; decoding preserves valid saved precision.
    var normalized: Self {
        let style = applying(to: .default).normalized
        return Self(fontSizeRatio: style.fontSizeRatio,
            normalizedCenterX: (style.normalizedCenterX * 100_000).rounded() / 100_000,
            normalizedCenterY: (style.normalizedCenterY * 100_000).rounded() / 100_000)
    }

    func applying(to style: MarkerLabelStyle) -> MarkerLabelStyle {
        var result = style
        result.fontSizeRatio = fontSizeRatio
        result.normalizedCenterX = normalizedCenterX
        result.normalizedCenterY = normalizedCenterY
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case fontSizeRatio, normalizedCenterX, normalizedCenterY
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontSizeRatio = try values.decode(Double.self, forKey: .fontSizeRatio)
        normalizedCenterX = try values.decode(Double.self, forKey: .normalizedCenterX)
        normalizedCenterY = try values.decode(Double.self, forKey: .normalizedCenterY)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid marker label placement"))
        }
    }
}
