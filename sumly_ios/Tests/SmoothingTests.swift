import Testing
import Foundation
@testable import Sumly

@MainActor
@Test func smoothingPreservesEndpointsAndDampensMiddle() {
    let calendar = Calendar(identifier: .gregorian)
    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_760_000_000))!
    }
    // 5 天：1000、1200、1000、1200、1000 —— 中部剧烈抖动
    let prices = (0..<5).map { offset in
        GoldDailyPrice(
            date: day(offset),
            open: 1, high: 1, low: 1,
            close: offset % 2 == 0 ? 1000 : 1200
        )
    }

    let smoothed = HomeViewModel.smoothed(prices, window: 5)

    #expect(smoothed.count == prices.count)
    #expect(smoothed[0].close == 1000) // 端点精确
    #expect(smoothed[4].close == 1000) // 端点精确
    // 中部被邻域平均压平：i=2 半径 2 → 全 5 点均值；i=1/3 → 三点均值
    #expect(smoothed[2].close == 1080)
    #expect(abs(smoothed[1].close - 1066.6667) < 0.001)
    #expect(abs(smoothed[3].close - 1066.6667) < 0.001)
    // 振幅从 ±100 收敛到 ±13.3
    #expect(abs(smoothed[2].close - smoothed[1].close) < 20)
}

@MainActor
@Test func smoothingSkipsTinySeries() {
    let one = [GoldDailyPrice(date: Date(timeIntervalSince1970: 0), open: 1, high: 1, low: 1, close: 1000)]
    #expect(HomeViewModel.smoothed(one, window: 7).map(\.close) == [1000])

    let two = one + [GoldDailyPrice(date: Date(timeIntervalSince1970: 86_400), open: 1, high: 1, low: 1, close: 1100)]
    #expect(HomeViewModel.smoothed(two, window: 7).map(\.close) == [1000, 1100])
}

@MainActor
@Test func smoothingKeepsDatesAndOHLC() {
    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!
    let prices = [
        GoldDailyPrice(date: date, open: 1, high: 2, low: 0.5, close: 1000),
        GoldDailyPrice(date: date.addingTimeInterval(86_400), open: 3, high: 4, low: 2.5, close: 1200),
        GoldDailyPrice(date: date.addingTimeInterval(172_800), open: 5, high: 6, low: 4.5, close: 1000),
    ]
    let smoothed = HomeViewModel.smoothed(prices, window: 5)
    #expect(smoothed[1].date == prices[1].date)
    #expect(smoothed[1].open == 3)
    #expect(smoothed[1].high == 4)
    #expect(smoothed[1].low == 2.5)
    #expect(abs(smoothed[1].close - 1066.6667) < 0.001)
}
