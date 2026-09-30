import Foundation
import SwiftData
import Testing
@testable import Sumly

@MainActor struct HoldingCalendarValuationTests {
    private func event(_ kind: String, grams: Double, cost: Double, fees: Double = 0, proceeds: Double = 0, purchase: UUID = UUID()) -> HoldingCalendarEvent {
        .init(id: UUID().uuidString, purchaseID: purchase, date: .now, kind: kind, grams: grams, cost: cost, fees: fees, proceeds: proceeds, title: "黄金")
    }

    @Test func purchaseValuationIncludesFeesAndTracksLatestQuote() {
        let events = [event("buy", grams: 40, cost: 18_200, fees: 200)]
        let first = HoldingCalendarLogic.stats(events, quote: 900).purchases
        #expect(first.value == 36_000)
        #expect(first.profit == 17_800)
        #expect(abs((first.profitPercent ?? 0) - 97.8021978022) < 0.000001)
        #expect(first.average == 450)
        #expect(HoldingCalendarLogic.stats(events, quote: 800).purchases.profit == 13_800)
    }

    @Test func salesUseActualProceedsAndGiftsHaveTheirOwnValuation() {
        let events = [event("sold", grams: 2, cost: 220, fees: 20, proceeds: 300),
                      event("gift", grams: 3, cost: 330, fees: 30)]
        let stats = HoldingCalendarLogic.stats(events, quote: 200)
        #expect(stats.purchases.count == 0)
        #expect(stats.sales.grams == 2)
        #expect(stats.sales.proceeds == 300)
        #expect(stats.sales.profit == 80)
        #expect(abs((stats.sales.profitPercent ?? 0) - 36.3636363636) < 0.000001)
        #expect(stats.sales.saleAverage == 150)
        #expect(stats.gifts.grams == 3)
        #expect(stats.gifts.cost == 330)
        #expect(stats.gifts.value == 600)
        #expect(stats.gifts.profit == nil)
    }

    @Test(arguments: [Double?.none, .some(0), .some(-1), .some(.nan), .some(.infinity)])
    func missingOrInvalidQuoteDoesNotInventZeroReturns(_ quote: Double?) {
        let stats = HoldingCalendarLogic.stats([event("buy", grams: 2, cost: 220),
            event("sold", grams: 1, cost: 110, proceeds: 90), event("gift", grams: 1, cost: 110)], quote: quote)
        #expect(stats.purchases.value == nil)
        #expect(stats.purchases.profit == nil)
        #expect(stats.purchases.profitPercent == nil)
        #expect(stats.gifts.value == nil)
        #expect(stats.sales.profit == -20)
        #expect(abs((stats.sales.profitPercent ?? 0) + 18.1818181818) < 0.000001)
    }

    @Test func zeroCostHasValueButNoPercentageAndSplitPurchasesCountOnce() {
        let purchase = UUID()
        let stats = HoldingCalendarLogic.stats([event("buy", grams: 2, cost: 0, purchase: purchase),
            event("buy", grams: 3, cost: 0, purchase: purchase)], quote: 100).purchases
        #expect(stats.count == 1)
        #expect(stats.grams == 5)
        #expect(stats.value == 500)
        #expect(stats.profit == 500)
        #expect(stats.profitPercent == nil)
        #expect(HoldingCalendarLogic.stats([], quote: 100).purchases.value == nil)
    }

    @Test func partialDisposalsUseTheirOwnDatesAndPreservePurchaseCost() throws {
        let calendar = Calendar(identifier: .gregorian)
        let buyDate = calendar.date(from: DateComponents(year: 2025, month: 9, day: 15, hour: 12))!
        let saleDate = calendar.date(from: DateComponents(year: 2025, month: 9, day: 19, hour: 12))!
        let giftDate = calendar.date(from: DateComponents(year: 2025, month: 9, day: 20, hour: 12))!
        let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let record = HoldingRecord(grams: 6, unitPriceCNY: 100, timestamp: buyDate)
        record.extraFee = 60
        context.insert(record)
        try HoldingDisposal.apply(record: record, grams: 2, proceeds: 300, kind: "sold", date: saleDate, context: context)
        try HoldingDisposal.apply(record: record, grams: 1, proceeds: 0, kind: "gift", date: giftDate, context: context)
        let events = HoldingCalendarLogic.events(try context.fetch(FetchDescriptor<HoldingRecord>()), filter: .init())
        let purchases = HoldingCalendarLogic.stats(HoldingCalendarLogic.select(events, period: .day, date: buyDate, calendar: calendar), quote: 200)
        #expect(purchases.purchases.count == 1)
        #expect(purchases.purchases.cost == 660)
        #expect(purchases.purchases.value == 1200)
        #expect(purchases.sales.count == 0)
        let sales = HoldingCalendarLogic.stats(HoldingCalendarLogic.select(events, period: .day, date: saleDate, calendar: calendar), quote: nil)
        #expect(sales.sales.profit == 80)
        #expect(sales.purchases.count == 0)
        let gifts = HoldingCalendarLogic.stats(HoldingCalendarLogic.select(events, period: .day, date: giftDate, calendar: calendar), quote: 200)
        #expect(gifts.gifts.cost == 110)
        #expect(gifts.gifts.value == 200)
    }
}
