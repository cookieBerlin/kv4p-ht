import Foundation

/// Where the squelch mark stands on the bars of the S-meter (ADR-0050): level n at the end of bar n, as a signal of
/// S n lights n bars.
public enum SquelchMark {
    public static let levels = 0...8

    /// The end of the bar of a level, from the start of the bars. `width` is that of all bars, `spacing` the gap
    /// between two of them.
    public static func position(of level: Int, width: Double, spacing: Double) -> Double {
        (width + spacing) * Double(level) / Double(RadioViewModel.sMeterBarCount) - spacing
    }

    /// The level nearest to a position; beyond the levels, the first or the last one.
    public static func level(at position: Double, width: Double, spacing: Double) -> Int {
        let bars = (position + spacing) * Double(RadioViewModel.sMeterBarCount) / (width + spacing)
        return min(max(Int(bars.rounded()), levels.lowerBound), levels.upperBound)
    }
}
