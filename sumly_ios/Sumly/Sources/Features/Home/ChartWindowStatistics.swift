import Foundation

/// Actual observations in the viewport, independent of the chart's price scale.
struct ChartWindowStatistics: Equatable {
    private(set) var first: MarketChartPoint?
    private(set) var last: MarketChartPoint?
    private(set) var high: MarketChartPoint?
    private(set) var low: MarketChartPoint?
    private(set) var change: Double?
    private(set) var percent: Double?

    init(points: some Sequence<MarketChartPoint>) {
        var count = 0
        for point in points where point.price.isFinite && point.price > 0 {
            count += 1
            if first == nil || point.date < first!.date { first = point }
            if last == nil || point.date > last!.date { last = point }
            if high == nil || point.price > high!.price || (point.price == high!.price && point.date < high!.date) { high = point }
            if low == nil || point.price < low!.price || (point.price == low!.price && point.date < low!.date) { low = point }
        }
        if count >= 2, let first, let last {
            let amount = last.price - first.price
            let percentage = amount / first.price * 100
            if amount.isFinite && percentage.isFinite { change = amount; percent = percentage }
        }
    }
}

/// Keep the 26-point badges inside the plot and apart, even near a clipped edge.
enum ChartExtremaLabelLayout {
    static func y(point: Double, other: Double?, height: Double, above: Bool) -> Double {
        func clamp(_ value: Double) -> Double { min(max(value, 14), max(14, height - 14)) }
        var position = clamp(point + (above ? -22 : 22))
        if let other {
            let otherPosition = clamp(other + (above ? 22 : -22))
            position = above ? min(position, otherPosition - 32) : max(position, otherPosition + 32)
        }
        return clamp(position)
    }
}
