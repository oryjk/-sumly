import Foundation

enum ChartPriceScale: String, CaseIterable {
    case linear = "线性"
    case logarithmic = "对数"
    func value(_ price: Double) -> Double? {
        guard price.isFinite, price > 0 else { return nil }
        return self == .linear ? price : log10(price)
    }
    func domain(_ prices: [Double]) -> ClosedRange<Double> {
        let values = prices.compactMap(value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let center = low / 2 + high / 2
        let padding = max((high - low) * 0.25, self == .linear ? 0.5 : 0.01)
        return (low - padding)...max(high + padding, center + padding)
    }
}
