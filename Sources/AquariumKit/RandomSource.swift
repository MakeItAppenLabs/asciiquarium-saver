/// A seedable SplitMix64 generator, so animation runs can be reproduced in tests.
public final class RandomSource {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// The next raw 64-bit output.
    public func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<n`, like Perl's `int(rand(n))`. Returns 0 when `n <= 0`.
    public func int(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        return Int(next() % UInt64(n))
    }

    /// A value in `[0, 1)`.
    public func double() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
