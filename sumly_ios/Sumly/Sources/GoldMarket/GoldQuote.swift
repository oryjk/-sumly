import Foundation

/// 伦敦金实时报价（后端 `/market/gold/quote`），价格单位：美元/盎司。
struct GoldQuote: Hashable, Sendable {
    let symbol: String
    let price: Double
    let open: Double
    let high: Double
    let low: Double
    let prevClose: Double
    /// 美元兑人民币汇率（买/卖中间价）；0 表示不可用。
    let usdCNY: Double
    /// 每克人民币价；0 表示不可用（估值侧按不可用处理）。
    let cnyPerGram: Double
    let asOf: Date

    /// 当日涨跌 = 最新价 − 昨收。
    var change: Double { price - prevClose }

    /// 当日涨跌幅（百分数）。
    var changePercent: Double {
        prevClose > 0 ? change / prevClose * 100 : 0
    }
}
