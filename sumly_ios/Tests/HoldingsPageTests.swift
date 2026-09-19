import Foundation
import SwiftData
import Testing
@testable import Sumly

@Test @MainActor func holdingsFiltersRespectBookDispositionAndSearch() {
    let one = HoldingRecord(grams: 2, unitPriceCNY: 6, timestamp: .now)
    let two = HoldingRecord(grams: 6, unitPriceCNY: 800 / 6, timestamp: .now)
    two.brand = "周生生"
    let other = HoldingRecord(grams: 3, unitPriceCNY: 900, timestamp: .now)
    other.bookName = "家人"
    let sold = HoldingRecord(grams: 1, unitPriceCNY: 800, timestamp: .now)
    sold.disposition = "sold"
    let result = HoldingsSelection.records([one, two, other, sold], book: "默认账本", search: "周生", filter: .all, sort: .newest, quote: 942.27)
    #expect(result.map(\.id) == [two.id])
    #expect(HoldingsSelection.records([one,two,other,sold], book: "默认账本", search: "", filter: .all, sort: .heaviest, quote: 942.27).map(\.id) == [two.id,one.id])
}

@Test @MainActor func holdingsProfitFiltersDoNotTreatMissingValuationAsZero() {
    let item = HoldingRecord(grams: 2, unitPriceCNY: 950, timestamp: .now)
    #expect(HoldingsSelection.records([item], book: "默认账本", search: "", filter: .loss, sort: .newest, quote: nil).isEmpty)
    #expect(HoldingsSelection.records([item], book: "默认账本", search: "", filter: .loss, sort: .newest, quote: 946).count == 1)
}

@Test @MainActor func partialSaleKeepsRemainingCostAndHistory() throws {
    let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let record = HoldingRecord(grams: 6, unitPriceCNY: 800 / 6, timestamp: .now.addingTimeInterval(-100))
    record.brand = "周生生"
    context.insert(record)
    try context.save()
    try HoldingDisposal.apply(record: record, grams: 2, proceeds: 1800, kind: "sold", date: .now, context: context)
    let records = try context.fetch(FetchDescriptor<HoldingRecord>())
    #expect(records.count == 2)
    #expect(record.grams == 4)
    #expect(record.unitPriceCNY == 800.0 / 6.0)
    #expect(records.first { $0.disposition == "sold" }?.disposalAmount == 1800)
    #expect(records.reduce(0) { $0 + $1.grams } == 6)
}
