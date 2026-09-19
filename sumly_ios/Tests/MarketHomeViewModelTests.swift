import Foundation
import Testing
@testable import Sumly

private struct HomeMarketFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing {
    var failing = false
    var usdCNY = 7.0
    func fetchQuote() async throws -> GoldQuote {
        if failing { throw URLError(.notConnectedToInternet) }
        return GoldQuote(symbol: "XAUUSD", price: 3100, open: 3000, high: 3150, low: 2900,
                         prevClose: 3000, usdCNY: usdCNY, cnyPerGram: usdCNY > 0 ? 697.67 : 0, asOf: .now)
    }
    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        if failing { throw URLError(.notConnectedToInternet) }
        return [5, 45, 120].map { days in
            GoldDailyPrice(date: Calendar.current.date(byAdding: .day, value: -days, to: .now)!,
                           open: 3000, high: 3100, low: 2900, close: 3000)
        }
    }
    func fetchRealtime() async throws -> [MarketChartPoint] {
        if failing { throw URLError(.notConnectedToInternet) }
        return [MarketChartPoint(date: .now.addingTimeInterval(-60), price: 675.25)]
    }
}

@MainActor @Test func homeKeepsRealtimeSamplePriceWithoutReconversionOrExtraQuote() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    await model.refresh()
    #expect(model.price == 697.67)
    #expect(model.points.count == 1)
    #expect(model.points[0].price == 675.25)
}

@MainActor @Test func homeRangesUseRealDailyDates() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    await model.refresh()
    model.range = .month
    #expect(model.points.count == 2)
    model.range = .quarter
    #expect(model.points.count == 3)
}

@MainActor @Test func homeNetworkFailureDoesNotDisplayReferencePrice() async {
    let service = HomeMarketFixture(failing: true)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    await model.refresh()
    #expect(model.price == nil)
    #expect(model.points.isEmpty)
    #expect(model.message != nil)
}

@MainActor @Test func homeMissingFXDoesNotShowZeroAsGoldPrice() async {
    let service = HomeMarketFixture(usdCNY: 0)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    await model.refresh()
    #expect(model.price == nil)
    #expect(model.points.count == 1) // 已采集的人民币报价不依赖当前汇率。
    #expect(model.message != nil)
}

@Test func realtimeWindowKeepsFiveSecondSamplesAndExcludesWholeDayHistory() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let samples = (0..<300).map {
        MarketChartPoint(date: now.addingTimeInterval(Double(-$0 * 5)), price: Double(900 + $0))
    }
    let window = MarketHomeViewModel.realtimeWindow(samples, now: now)
    #expect(window.count == 241)
    #expect(window.first?.date == now.addingTimeInterval(-1200))
    #expect(window.last?.price == 900)
    #expect(window.last?.date == now)
}

@Test func realtimeWindowDoesNotSynthesizeMissingSamples() {
    let now = Date.now
    let points = [MarketChartPoint(date: now.addingTimeInterval(-120), price: 938),
                  MarketChartPoint(date: now, price: 939)]
    #expect(MarketHomeViewModel.realtimeWindow(points, now: now) == points)
}

@Test func realtimeYAxisDoesNotAmplifyTinyMovements() {
    let points = [MarketChartPoint(date: .now, price: 938.2), MarketChartPoint(date: .now, price: 938.21)]
    let domain = MarketHomeViewModel.chartDomain(points)
    #expect(domain.upperBound - domain.lowerBound >= 1)
    #expect(domain == MarketHomeViewModel.chartDomain([MarketChartPoint(date: .now, price: 938.22)]))
}

@MainActor @Test func chartSelectionUsesSamplePriceAndClearsOnRangeChange() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    await model.refresh()
    model.selectedDate = model.points.first?.date
    #expect(model.selectedPoint?.price == 675.25)
    model.range = .month
    #expect(model.selectedPoint == nil)
}

@Test func flatPriceDomainAlwaysHasOneYuanOfRoom() {
    for value in [938.0, 938.1, 938.25, 938.5, 938.75] {
        let domain = MarketHomeViewModel.chartDomain([MarketChartPoint(date: .now, price: value)])
        #expect(domain.upperBound - domain.lowerBound >= 1)
    }
}

@MainActor @Test func initialLoadingEndsOnSuccessAndFailure() async {
    for failing in [false, true] {
        let service = HomeMarketFixture(failing: failing)
        let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
        #expect(model.showsInitialLoading)
        await model.refresh()
        #expect(!model.showsInitialLoading)
        if failing { #expect(model.message != nil) }
    }
}

@Test func realtimeWindowRemainsAtLastAvailableQuoteDuringClosure() {
    let last = Date(timeIntervalSince1970: 1_789_764_840)
    let points = (0...300).map { MarketChartPoint(date: last.addingTimeInterval(Double($0 - 300) * 5), price: 942.8) }
    let result = MarketHomeViewModel.realtimeWindow(points, now: last.addingTimeInterval(48 * 3600))
    #expect(result.count == 241)
    #expect(result.first?.date == last.addingTimeInterval(-1200))
    #expect(result.last?.date == last)
}
