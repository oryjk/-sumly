import Foundation
import SwiftData
import Testing
@testable import Sumly

@MainActor struct HoldingsCalendarTests {
    let cal = Calendar(identifier: .gregorian)
    func date(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2025, month: 9, day: day, hour: 12))! }
    @Test func partialSaleIsOnePurchaseAndFeesArePreserved() throws {
        let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let record = HoldingRecord(grams: 6, unitPriceCNY: 100, timestamp: date(15))
        record.extraFee = 60
        context.insert(record)
        try HoldingDisposal.apply(record: record, grams: 2, proceeds: 300, kind: "sold", date: date(19), context: context, counterparty: "回收店")
        let records = try context.fetch(FetchDescriptor<HoldingRecord>())
        let events = HoldingCalendarLogic.events(records, filter: .init())
        let purchases = HoldingCalendarLogic.select(events, period: .day, date: date(15), calendar: cal)
        let stats = HoldingCalendarLogic.stats(purchases, quote: 200)
        #expect(stats.count == 1)
        #expect(stats.grams == 6)
        #expect(stats.fees == 60)
        #expect(stats.cost == 660)
        #expect(HoldingCalendarLogic.select(events, period: .day, date: date(19), calendar: cal).first?.grams == 2)
        #expect(record.extraFee == 40)
        #expect(HoldingsSelection.records([record], book: "默认账本", search: "", filter: .loss, sort: .newest, quote: 105).count == 1)
        #expect(record.counterparty.isEmpty)
        #expect(records.first { $0.disposition == "sold" }?.counterparty == "回收店")
        #expect(HoldingsViewModel(quoteService: nil).stats(for: records).totalCost == 440)
    }
    @Test func filtersUseBookCounterpartyAndTransactionDate() {
        let record = HoldingRecord(grams: 2, unitPriceCNY: 100, timestamp: date(15))
        record.disposition = "gift"; record.disposedAt = date(19); record.counterparty = "妈妈"; record.bookName = "家人"
        let events = HoldingCalendarLogic.events([record], filter: .init(keyword: "妈妈", kind: "gift", book: "家人"))
        #expect(events.count == 1)
        #expect(events.first?.date == date(19))
        #expect(HoldingCalendarLogic.events([record], filter: .init(book: "默认账本")).isEmpty)
    }
    @Test func monthGridAndHalfOpenIntervals() {
        let grid = HoldingCalendarLogic.days(in: date(15), calendar: cal)
        #expect(grid.count == 42)
        #expect(grid.allSatisfy { cal.component(.hour, from: $0) == 12 })
        #expect(cal.component(.weekday, from: grid[0]) == 1)
        let record = HoldingRecord(grams: 1, unitPriceCNY: 100, timestamp: cal.date(from: DateComponents(year: 2025, month: 10, day: 1))!)
        let events = HoldingCalendarLogic.events([record], filter: .init())
        #expect(HoldingCalendarLogic.select(events, period: .month, date: date(15), calendar: cal).isEmpty)
        #expect(HoldingCalendarLogic.select(events, period: .year, date: date(15), calendar: cal).count == 1)
        #expect(HoldingCalendarLogic.stats(events, quote: nil).profitPercent == nil)
    }
}
