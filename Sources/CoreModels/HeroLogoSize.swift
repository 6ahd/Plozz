import Foundation

/// Eleven layout-only steps from the existing logo size to 1.5 times that size.
public struct HeroLogoSize: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int
    public static let steps = 0...10
    public static let `default` = HeroLogoSize(rawValue: 0)
    public static let allSizes = steps.map { HeroLogoSize(rawValue: $0) }

    public init(rawValue: Int) {
        self.rawValue = min(max(rawValue, Self.steps.lowerBound), Self.steps.upperBound)
    }

    public var scale: Double { 1 + Double(rawValue) * 0.05 }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
