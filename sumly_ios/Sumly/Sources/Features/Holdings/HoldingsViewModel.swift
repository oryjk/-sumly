import Foundation
import Observation

/// 持仓页状态：实时「元/克」价轮询与汇总统计。
/// 记录的增删走 SwiftData（视图持有 modelContext），这里只负责行情与计算。
@MainActor
@Observable
final class HoldingsViewModel {
    /// 实时报价轮询间隔，与行情页一致。
    static let quotePollInterval: Duration = .seconds(3)

    private(set) var quote: GoldQuote?

    private let quoteService: (any GoldQuoteServicing)?

    init(quoteService: (any GoldQuoteServicing)? = BackendGoldPriceService(instrumentID: "au9999")) {
        self.quoteService = quoteService
    }

    /// 页面入口：立即取一次报价，随后每 3 秒轮询；视图销毁自动取消。
    func start() async {
        await pollQuote()
        guard quoteService != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.quotePollInterval)
            guard !Task.isCancelled else { return }
            await pollQuote()
        }
    }

    /// 拉一次实时报价；失败静默保留旧值。
    func pollQuote() async {
        guard let quoteService, let fetched = try? await quoteService.fetchQuote() else { return }
        quote = fetched
    }

    func stats(for records: [HoldingRecord]) -> HoldingsStats {
        HoldingsStats.compute(
            records: records.filter { $0.disposition == "holding" }.map { (grams: $0.grams, unitPrice: $0.unitPriceCNY) },
            cnyPerGram: quote?.cnyPerGram ?? 0
        )
    }

    /// 单条记录的当前收益 = 克数 ×（当前元/克 − 买入元/克）；估值不可用时返回 nil。
    func recordProfit(_ record: HoldingRecord) -> Double? {
        guard let quote, quote.cnyPerGram > 0 else { return nil }
        return record.grams * (quote.cnyPerGram - record.unitPriceCNY)
    }
}
