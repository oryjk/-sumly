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
    #expect(model.windowPoints.count == 1)
    model.range = .quarter
    #expect(model.windowPoints.count == 2)
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

private struct HomeHistoryFixture: GoldHistoryServicing {
    var failing = false
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        if failing { throw URLError(.notConnectedToInternet) }
        return [GoldHistoryPoint(date: GoldDailyPrice.parseDay("1900-07-01")!, price: 19, granularity: .annual, source: "usgs-ds140"),
                GoldHistoryPoint(date: GoldDailyPrice.parseDay("2015-07-01")!, price: 1163, granularity: .annual, source: "usgs-ds140"),
                GoldHistoryPoint(date: GoldDailyPrice.parseDay("2016-01-04")!, price: 1074, granularity: .daily, source: "sina-xauusd")]
    }
}
@MainActor @Test func historyKeepsGranularityAndPinchStateAcrossQuoteRefresh() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .history
    await model.refresh()
    #expect(model.points.count == 3)
    #expect(model.points.first?.granularity == .annual)
    #expect(abs(model.points[0].price - 19 * 7 / 31.1034768) < 0.000001)
    #expect(model.fullDomain.lowerBound == GoldDailyPrice.parseDay("1900-01-01"))
    model.beginChartGesture()
    model.transformChart(scale: 10, anchor: 1, translation: 0)
    model.endChartGesture()
    let window = model.xDomain
    #expect(window.lowerBound > model.fullDomain.lowerBound)
    await model.refresh()
    #expect(model.xDomain == window)
    model.range = .month
    #expect(model.viewport == nil)
    #expect(model.selectedDate == nil)
}
@MainActor @Test func unavailableHistoryDoesNotPretendOneLiveQuoteIsCenturyOfHistory() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture(failing: true))
    model.range = .history
    await model.refresh()
    #expect(model.points.isEmpty)
    #expect(model.message?.contains("历史走势加载失败") == true)
}

@MainActor @Test func zoomedAnnualPointCanBeInspectedAcrossItsYear() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .history
    await model.refresh()
    model.beginChartGesture()
    model.transformChart(scale: 10000, anchor: 0, translation: 0)
    model.endChartGesture()
    model.selectChart(at: 0.1)
    #expect(model.selectedPoint?.date == GoldDailyPrice.parseDay("1900-07-01"))
}
private actor AdvancingRealtimeFixture: GoldRealtimeServicing {
    var end = Date.now.addingTimeInterval(-900)
    func advance() { end = end.addingTimeInterval(900) }
    func fetchRealtime() async throws -> [MarketChartPoint] {
        (0...240).map { MarketChartPoint(date: end.addingTimeInterval(Double($0 - 240) * 5), price: 900) }
    }
}
@MainActor @Test func rollingRealtimeWindowClampsOldZoomWithoutGoingBlank() async {
    let service = HomeMarketFixture()
    let realtime = AdvancingRealtimeFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: realtime)
    await model.refresh()
    model.beginChartGesture()
    model.transformChart(scale: 100, anchor: 0, translation: 0)
    model.endChartGesture()
    await realtime.advance()
    await model.refresh()
    #expect(model.xDomain.lowerBound >= model.fullDomain.lowerBound)
    #expect(model.xDomain.upperBound.timeIntervalSince(model.xDomain.lowerBound) == 30)
    #expect(model.visiblePoints.contains { model.xDomain.contains($0.date) })
}

@MainActor @Test func nonRealtimeChartUsesDayAlignedDatesAndCanLeavePreset() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .month
    await model.refresh()
    #expect(model.points.allSatisfy { Calendar.current.component(.hour, from: $0.date) == 12 && Calendar.current.component(.second, from: $0.date) == 0 })
    let preset = model.xDomain
    model.beginNavigatorGesture()
    model.moveNavigator(part: .window, fraction: -0.5)
    model.endChartGesture()
    #expect(model.xDomain.upperBound < preset.lowerBound)
    #expect(Calendar.current.dateComponents([.day], from: model.xDomain.lowerBound, to: model.xDomain.upperBound).day == Calendar.current.dateComponents([.day], from: preset.lowerBound, to: preset.upperBound).day)
    model.resetViewport()
    #expect(model.xDomain == preset)
}
@MainActor @Test func dailyZoomAndDateSelectionNeverCreateSecondScaleWindows() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .quarter
    await model.refresh()
    model.accessibleZoom(100000)
    #expect(Calendar.current.dateComponents([.day], from: model.xDomain.lowerBound, to: model.xDomain.upperBound).day! >= 1)
    #expect(Calendar.current.component(.hour, from: model.xDomain.lowerBound) == 12)
    #expect(Calendar.current.component(.second, from: model.xDomain.upperBound) == 0)
    #expect(model.axisDates.allSatisfy { Calendar.current.component(.hour, from: $0) == 12 })
}

private struct ClosedDayHistoryFixture: GoldHistoryServicing {
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        [-2, -1, 0].map { offset in
            GoldHistoryPoint(date: Calendar.current.date(byAdding: .day, value: offset, to: ChartViewport.noon(.now))!, price: Double(3000 + offset), granularity: .daily, source: "test")
        }
    }
}
@MainActor @Test func nonRealtimeChartStopsYesterdayAndNeverAppendsLiveQuote() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: ClosedDayHistoryFixture())
    for range in [MarketRange.month, .quarter, .history] {
        model.range = range
        await model.refresh()
        let yesterday = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        #expect(model.points.count == 2)
        #expect(model.points.last?.date == yesterday)
        #expect(model.fullDomain.upperBound == yesterday)
        #expect(model.points.allSatisfy { $0.granularity == .daily })
    }
}

private struct YesterdayOnlyFixture: GoldPriceServicing {
    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        let yesterday = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        return [GoldDailyPrice(date: yesterday, open: 3000, high: 3000, low: 3000, close: 3000)]
    }
}
@MainActor @Test func singleYesterdayObservationNeverExtendsDomainIntoToday() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: YesterdayOnlyFixture(), quoteService: service, realtimeService: service, historyService: HomeHistoryFixture(failing: true))
    model.range = .month
    await model.refresh()
    let yesterday = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
    #expect(model.fullDomain.upperBound == yesterday)
    #expect(model.fullDomain.lowerBound < yesterday)
    #expect(model.xDomain.upperBound == yesterday)
}

private struct LargeHomeHistoryFixture: GoldHistoryServicing {
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        let end = ChartViewport.noon(.now)
        return (1...5308).map { day in
            GoldHistoryPoint(date: end.addingTimeInterval(Double(-day) * 86400), price: Double(2000 + day % 100), granularity: .daily, source: "fixture")
        }
    }
}

@MainActor @Test func historicalViewportReadsStayWithinInteractionBudget() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: LargeHomeHistoryFixture())
    model.range = .month
    await model.refresh()
    let start = ContinuousClock.now
    var count = 0
    // Repeated SwiftUI body, axis and navigator reads while switching/panning.
    for _ in 0..<20 {
        count += model.visiblePoints.count + model.windowPoints.count + model.axisDates.count
        _ = model.fullDomain
        _ = model.canReset
    }
    let elapsed = start.duration(to: .now)
    print("HOME_PERF repeated viewport reads: \(elapsed)")
    #expect(count > 0)
    #expect(elapsed < .milliseconds(500))
}

private actor MutableHomeHistoryFixture: GoldHistoryServicing, GoldQuoteServicing {
    let date = ChartViewport.noon(Date.now.addingTimeInterval(-86400))
    var value = 2000.0
    var fx = 7.0
    func change(value: Double, fx: Double) { self.value = value; self.fx = fx }
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        [GoldHistoryPoint(date: date, price: value, granularity: .daily, source: "fixture")]
    }
    func fetchQuote() async throws -> GoldQuote {
        GoldQuote(symbol: "XAUUSD", price: value, open: value, high: value, low: value,
                  prevClose: value, usdCNY: fx, cnyPerGram: value * fx / 31.1034768, asOf: .now)
    }
}

@MainActor @Test func preparedHistoryReflectsCorrectionsFXAndCacheClear() async {
    let daily = HomeMarketFixture()
    let history = MutableHomeHistoryFixture()
    let model = MarketHomeViewModel(dailyService: daily, quoteService: history, realtimeService: daily, historyService: history)
    model.range = .month
    await model.refresh()
    #expect(abs(model.points[0].price - 2000 * 7 / 31.1034768) < 0.000001)
    await history.change(value: 2200, fx: 7)
    await model.refresh()
    #expect(abs(model.points[0].price - 2200 * 7 / 31.1034768) < 0.000001)
    await history.change(value: 2200, fx: 8)
    await model.refresh()
    #expect(abs(model.points[0].price - 2200 * 8 / 31.1034768) < 0.000001)
    model.clearMarketCache()
    #expect(model.points.isEmpty)
    await model.refresh()
    #expect(abs(model.points[0].price - 2200 * 8 / 31.1034768) < 0.000001)
}
