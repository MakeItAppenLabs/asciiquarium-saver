import Foundation

/// The special creatures, in Perl `init_random_objects` order.
public enum SpecialKind: String, Codable, CaseIterable, Sendable {
    case ship, whale, monster, bigFish, shark, fishhook
    case swan, ducks, dolphins, submarine, swordfish, jellyfish
}

/// Which art set the fish, monster and big fish are drawn from.
public enum CreatureSet: String, Codable, Sendable {
    case full, classic
}

public enum TextSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public var pointSize: Double {
        switch self {
        case .small: 11.5
        case .medium: 15.5
        case .large: 23.0
        }
    }
}

public enum Background: Codable, Hashable, Sendable {
    case solid(RGB)
    case gradient(top: RGB, bottom: RGB)
}

public struct AquariumSettings: Codable, Hashable, Sendable {
    public static let fishAmountRange: ClosedRange<Double> = 0.25...3.0

    public var fishAmount: Double
    public var creatureSet: CreatureSet
    public var enabledSpecials: Set<SpecialKind>
    public var background: Background
    public var textSize: TextSize

    public init(
        fishAmount: Double = 1.0,
        creatureSet: CreatureSet = .full,
        enabledSpecials: Set<SpecialKind> = Set(SpecialKind.allCases),
        background: Background = .solid(.black),
        textSize: TextSize = .medium
    ) {
        self.fishAmount = Self.clamp(fishAmount)
        self.creatureSet = creatureSet
        self.enabledSpecials = enabledSpecials
        self.background = background
        self.textSize = textSize
    }

    public static let defaults = AquariumSettings()

    public static let defaultGradient = Background.gradient(
        top: RGB(r: 0.02, g: 0.06, b: 0.16),
        bottom: .black
    )

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaults.fishAmount }
        return min(max(value, fishAmountRange.lowerBound), fishAmountRange.upperBound)
    }

    // MARK: Slider mapping

    /// Slider position 0...1 to fish amount: 0 is 0.25, 0.5 is 1.0, 1 is 3.0, linear between.
    public static func fishAmount(sliderPosition p: Double) -> Double {
        let p = min(max(p, 0), 1)
        if p <= 0.5 { return 0.25 + (p / 0.5) * 0.75 }
        return 1.0 + ((p - 0.5) / 0.5) * 2.0
    }

    /// The inverse of `fishAmount(sliderPosition:)`.
    public static func sliderPosition(fishAmount amount: Double) -> Double {
        let a = clamp(amount)
        if a <= 1.0 { return (a - 0.25) / 0.75 * 0.5 }
        return 0.5 + (a - 1.0) / 2.0 * 0.5
    }

    // MARK: Persistence

    private enum CodingKeys: String, CodingKey {
        case fishAmount, creatureSet, enabledSpecials, background, textSize
    }

    /// Decodes each field on its own, so a missing or unrecognised value falls back to that
    /// field's default and the rest of the stored settings survive.
    public init(from decoder: Decoder) throws {
        let d = Self.defaults
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = d
            return
        }
        let amount = (try? c.decodeIfPresent(Double.self, forKey: .fishAmount)) ?? nil
        let set = (try? c.decodeIfPresent(CreatureSet.self, forKey: .creatureSet)) ?? nil
        let specials = (try? c.decodeIfPresent([String].self, forKey: .enabledSpecials)) ?? nil
        let background = (try? c.decodeIfPresent(Background.self, forKey: .background)) ?? nil
        let size = (try? c.decodeIfPresent(TextSize.self, forKey: .textSize)) ?? nil
        self.init(
            fishAmount: amount ?? d.fishAmount,
            creatureSet: set ?? d.creatureSet,
            enabledSpecials: specials.map { Set($0.compactMap(SpecialKind.init(rawValue:))) } ?? d.enabledSpecials,
            background: background ?? d.background,
            textSize: size ?? d.textSize
        )
    }

    /// Settings from stored JSON. Missing or corrupt data gives the defaults.
    public static func decode(_ data: Data?) -> AquariumSettings {
        guard let data, let settings = try? JSONDecoder().decode(AquariumSettings.self, from: data) else {
            return defaults
        }
        return settings
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }
}
