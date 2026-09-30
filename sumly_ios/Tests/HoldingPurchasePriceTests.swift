import Foundation
import Testing
@testable import Sumly

@MainActor struct HoldingPurchasePriceTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func day(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))! }
    private func bar(_ day: Int, _ close: Double) -> GoldDailyPrice { .init(date: self.day(day), open: close, high: close, low: close, close: close) }
    private func quote(_ price: Double = 900, fx: Double = 7) -> GoldQuote {
        .init(symbol: "AU9999", price: price, open: price, high: price, low: price, prevClose: price, usdCNY: fx, cnyPerGram: price, asOf: day(30))
    }

    @Test func historicalEntryAndDateChangesUseThatDaysClose() async {
        let source = PurchasePriceFixture(prices: [bar(22, 800), bar(23, 810)], quote: quote())
        let model = HoldingPurchasePriceModel(date: day(22), basis: .domestic, initialPrice: 900, service: source)
        #expect(model.priceText.isEmpty)
        await model.load(now: day(30))
        #expect(model.validPrice == 800)
        model.selectDate(day(23))
        #expect(model.validPrice == nil)
        await model.load(now: day(30))
        #expect(model.validPrice == 810)
        model.selectDate(day(30))
        await model.load(now: day(30))
        #expect(model.validPrice == 900)
    }

    @Test func missingDayDoesNotUseAnotherDaysCloseOrTodaysPrice() async {
        let source = PurchasePriceFixture(prices: [bar(25, 800)], quote: quote())
        let model = HoldingPurchasePriceModel(date: day(26), basis: .domestic, initialPrice: 900, service: source)
        await model.load(now: day(30))
        #expect(model.reference == nil)
        #expect(model.validPrice == nil)
        #expect(model.issue == .missingDay)
    }

    @Test func internationalCloseIsConvertedToCNYPerGramWithExplicitFX() async {
        let source = PurchasePriceFixture(prices: [bar(22, 3110.34768)], quote: quote(fx: 7))
        let model = HoldingPurchasePriceModel(date: day(22), basis: .international, service: source)
        await model.load(now: day(30))
        #expect(model.validPrice == 700)
        #expect(model.reference?.exchangeRate == 7)
        let missingFX = HoldingPurchasePriceModel(date: day(22), basis: .international,
            service: PurchasePriceFixture(prices: [bar(22, 3110.34768)], quote: quote(fx: 0)))
        await missingFX.load(now: day(30))
        #expect(missingFX.validPrice == nil)
        #expect(missingFX.issue == .missingExchangeRate)
    }

    @Test func manualPriceSurvivesDateChangesUntilReferenceIsChosen() async {
        let model = HoldingPurchasePriceModel(date: day(22), basis: .domestic,
            service: PurchasePriceFixture(prices: [bar(22, 800), bar(23, 810)], quote: quote()))
        await model.load(now: day(30))
        model.editPrice("750")
        model.selectDate(day(23))
        await model.load(now: day(30))
        #expect(model.validPrice == 750)
        #expect(model.reference?.price == 810)
        model.useReference()
        #expect(model.validPrice == 810)
        model.editPrice("")
        #expect(model.validPrice == nil)
    }

    @Test func lateQuoteCannotOverwriteNewDateReference() async {
        let source = DeferredPurchaseQuote(prices: [bar(22, 800)])
        let model = HoldingPurchasePriceModel(date: day(30), basis: .domestic, service: source)
        let task = Task { await model.load(now: day(30)) }
        await source.waitForRequest()
        model.selectDate(day(22))
        await model.load(now: day(30))
        await source.finish(quote())
        await task.value
        #expect(model.validPrice == 800)
        #expect(model.reference?.date == calendar.startOfDay(for: day(22)))
    }

    @Test func lateResponseDoesNotReplaceManualInput() async {
        let source = DeferredPurchaseQuote(prices: [])
        let model = HoldingPurchasePriceModel(date: day(30), basis: .domestic, service: source)
        let task = Task { await model.load(now: day(30)) }
        await source.waitForRequest()
        model.editPrice("650")
        await source.finish(quote())
        await task.value
        #expect(model.validPrice == 650)
        #expect(model.reference?.price == 900)
    }
}

private struct PurchasePriceFixture: GoldPriceServicing, GoldQuoteServicing {
    let prices: [GoldDailyPrice]
    let quote: GoldQuote
    func fetchDailyPrices() async throws -> [GoldDailyPrice] { prices }
    func cachedDailyPrices() async -> [GoldDailyPrice]? { prices }
    func fetchQuote() async throws -> GoldQuote { quote }
}

private actor DeferredPurchaseQuote: GoldPriceServicing, GoldQuoteServicing {
    let prices: [GoldDailyPrice]
    private var response: CheckedContinuation<GoldQuote, Never>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    init(prices: [GoldDailyPrice]) { self.prices = prices }
    func cachedDailyPrices() async -> [GoldDailyPrice]? { prices }
    func fetchDailyPrices() async throws -> [GoldDailyPrice] { prices }
    func fetchQuote() async throws -> GoldQuote {
        await withCheckedContinuation { continuation in
            response = continuation
            requestWaiter?.resume(); requestWaiter = nil
        }
    }
    func waitForRequest() async {
        if response != nil { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }
    func finish(_ quote: GoldQuote) { response?.resume(returning: quote); response = nil }
}
