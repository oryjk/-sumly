import Foundation
import SwiftData

/// 仅 Debug 的截图验证入口：始终使用独立内存容器，不向真实账本写入示例。
@MainActor enum HoldingsDesignPreview {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--holdings-design-preview")
        #else
        false
        #endif
    }
    static func makeModel() -> HoldingsViewModel {
        #if DEBUG
        if isEnabled { return HoldingsViewModel(quoteService: QuoteFixture()) }
        #endif
        return HoldingsViewModel()
    }
    static func container() throws -> ModelContainer {
        let result = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #if DEBUG
        let first = HoldingRecord(grams: 2, unitPriceCNY: 6, timestamp: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12))!)
        let second = HoldingRecord(grams: 6, unitPriceCNY: 800.0 / 6, timestamp: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!)
        second.brand = "周生生"
        result.mainContext.insert(first); result.mainContext.insert(second)
        try result.mainContext.save()
        #endif
        return result
    }
    #if DEBUG
    private struct QuoteFixture: GoldQuoteServicing {
        func fetchQuote() async throws -> GoldQuote {
            GoldQuote(symbol: "AU9999", price: 942.27, open: 940, high: 943, low: 939, prevClose: 940, usdCNY: 0, cnyPerGram: 942.27, asOf: .now)
        }
    }
    #endif
}
