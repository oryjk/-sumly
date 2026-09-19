import Testing
import Foundation
import SwiftData
@testable import Sumly

@Test func holdingsStatsComputesTotalsAndProfit() {
    let stats = HoldingsStats.compute(
        records: [
            (grams: 1, unitPrice: 900),
            (grams: 2.5, unitPrice: 920),
        ],
        cnyPerGram: 925
    )
    #expect(stats.totalGrams == 3.5)
    #expect(stats.totalCost == 3200)
    #expect(stats.totalValue == 3237.5)
    #expect(abs(stats.profit - 37.5) < 0.0001)
    #expect(abs(stats.profitPercent - 1.171875) < 0.0001)
    #expect(stats.hasValuation)
}

@Test func holdingsStatsWithoutValuationStillCountsHoldings() {
    let stats = HoldingsStats.compute(records: [(grams: 3, unitPrice: 900)], cnyPerGram: 0)
    #expect(stats.totalGrams == 3)
    #expect(stats.totalCost == 2700)
    #expect(!stats.hasValuation)
    #expect(stats.totalValue == 0)
    #expect(stats.profit == 0)
}



@Test func holdingsStatsEmpty() {
    let stats = HoldingsStats.compute(records: [], cnyPerGram: 925)
    #expect(stats.totalGrams == 0)
    #expect(!stats.hasValuation)
}

@MainActor
@Test func holdingRecordRoundtripInMemory() throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: HoldingRecord.self, configurations: configuration)
    let context = container.mainContext

    let stamp1 = Date(timeIntervalSince1970: 1_760_000_000)
    let stamp2 = Date(timeIntervalSince1970: 1_760_086_400)
    context.insert(HoldingRecord(grams: 5.5, unitPriceCNY: 920.5, timestamp: stamp1, note: "金条"))
    context.insert(HoldingRecord(grams: 0.01, unitPriceCNY: 899.99, timestamp: stamp2))
    try context.save()

    var descriptor = FetchDescriptor<HoldingRecord>(
        sortBy: [SortDescriptor(\.timestamp, order: .forward)]
    )
    let fetched = try context.fetch(descriptor)
    #expect(fetched.count == 2)

    let first = fetched[0]
    #expect(first.grams == 5.5)
    #expect(first.unitPriceCNY == 920.5)
    #expect(first.timestamp == stamp1) // 精确时间点原样保存
    #expect(first.note == "金条")
    #expect(first.id != fetched[1].id)

    descriptor.predicate = #Predicate { $0.note == "金条" }
    #expect(try context.fetch(descriptor).count == 1)
}
