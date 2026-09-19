import Foundation

/// 持仓汇总（金额单位：元）。
struct HoldingsStats: Equatable, Sendable {
    var totalGrams: Double
    var totalCost: Double
    var totalValue: Double
    var profit: Double
    var profitPercent: Double
    /// false 表示实时「元/克」价不可用（如汇率缺失），估值与收益不应展示。
    var hasValuation: Bool

    static let empty = HoldingsStats(
        totalGrams: 0, totalCost: 0, totalValue: 0, profit: 0, profitPercent: 0, hasValuation: false
    )

    static func compute(
        records: some Sequence<(grams: Double, unitPrice: Double)>,
        cnyPerGram: Double
    ) -> HoldingsStats {
        var totalGrams = 0.0
        var totalCost = 0.0
        for record in records {
            totalGrams += record.grams
            totalCost += record.grams * record.unitPrice
        }
        guard totalGrams > 0, cnyPerGram > 0 else {
            return HoldingsStats(
                totalGrams: totalGrams, totalCost: totalCost,
                totalValue: 0, profit: 0, profitPercent: 0, hasValuation: false
            )
        }
        let totalValue = totalGrams * cnyPerGram
        let profit = totalValue - totalCost
        let profitPercent = totalCost > 0 ? profit / totalCost * 100 : 0
        return HoldingsStats(
            totalGrams: totalGrams, totalCost: totalCost, totalValue: totalValue,
            profit: profit, profitPercent: profitPercent, hasValuation: true
        )
    }
}
