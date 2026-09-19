import Foundation

/// 单个交易日的国际金价（伦敦金 XAU/USD）OHLC，价格单位：美元/盎司。
struct GoldDailyPrice: Identifiable, Hashable, Sendable {
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    var id: Date { date }

    /// "yyyy-MM-dd" → 当地时区当天正午：任何时区下日期展示不漂移，也不会踩到夏令时边界。
    static func parseDay(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}
