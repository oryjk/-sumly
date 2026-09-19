import Foundation

/// 金价日线数据源抽象。
/// 新增来源（如直连新浪的备用实现）只需遵守本协议，上层（HomeViewModel / 视图）不感知。
protocol GoldPriceServicing: Sendable {
    /// 按日期升序返回日线序列。
    func fetchDailyPrices() async throws -> [GoldDailyPrice]
}

/// 实时报价数据源抽象；轮询节奏由上层编排。
protocol GoldQuoteServicing: Sendable {
    func fetchQuote() async throws -> GoldQuote
}
