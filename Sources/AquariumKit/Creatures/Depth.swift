/// The z depths at which items occur: Perl's `%depth` table. A lower z draws in front.
public enum Depth {
    // no gui yet
    public static let guiText = 0
    public static let gui = 1

    // under water
    public static let shark = 2
    public static let fishStart = 3
    public static let fishEnd = 20
    public static let seaweed = 21
    public static let castle = 22

    // waterline
    public static let waterLine3 = 2
    public static let waterGap3 = 3
    public static let waterLine2 = 4
    public static let waterGap2 = 5
    public static let waterLine1 = 6
    public static let waterGap1 = 7
    public static let waterLine0 = 8
    public static let waterGap0 = 9

    /// `$depth{'water_line' . $i}` for `i` in 0...3.
    public static func waterLine(_ i: Int) -> Int {
        switch i {
        case 0: waterLine0
        case 1: waterLine1
        case 2: waterLine2
        default: waterLine3
        }
    }
}
