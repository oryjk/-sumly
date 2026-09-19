import Testing
import Foundation
@testable import Sumly

@Test func rangeSlicingByCutoff() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // 覆盖各区间边界：1 个月前 = 2026-08-17，3 个月 = 06-17，6 个月 = 03-17，1 年 = 2025-09-17
    let prices = [
        day(2025, 9, 1),
        day(2026, 3, 16),
        day(2026, 5, 1),
        day(2026, 8, 10),
        day(2026, 8, 20),
        day(2026, 9, 1),
        day(2026, 9, 16),
    ].map { GoldDailyPrice(date: $0, open: 1, high: 1, low: 1, close: 1) }

    #expect(PriceRange.oneMonth.slice(prices, calendar: calendar, now: now).count == 3) // 08-20 起
    #expect(PriceRange.threeMonths.slice(prices, calendar: calendar, now: now).count == 4) // 08-10 起
    #expect(PriceRange.sixMonths.slice(prices, calendar: calendar, now: now).count == 5) // 05-01 起
    #expect(PriceRange.oneYear.slice(prices, calendar: calendar, now: now).count == 6) // 2025-09-17 截止
    #expect(PriceRange.all.slice(prices, calendar: calendar, now: now).count == 7)
}

@Test func rangeSlicingOnEmptyInput() {
    #expect(PriceRange.oneYear.slice([]).isEmpty)
    #expect(PriceRange.all.slice([]).isEmpty)
}
