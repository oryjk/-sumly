import Testing
import Foundation
@testable import Sumly

private struct MockGoldPriceService: GoldPriceServicing {
    enum Outcome: Sendable {
        case success([GoldDailyPrice])
        case failure(URLError)
    }

    let outcome: Outcome

    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        switch outcome {
        case .success(let prices): prices
        case .failure(let error): throw error
        }
    }
}

/// 按调用顺序依次返回预置结果，用于模拟“先成功后失败”的刷新场景。
private actor SequencedMockService: GoldPriceServicing {
    private var outcomes: [MockGoldPriceService.Outcome]

    init(outcomes: [MockGoldPriceService.Outcome]) {
        self.outcomes = outcomes
    }

    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        let outcome = outcomes.isEmpty
            ? .failure(URLError(.badServerResponse))
            : outcomes.removeFirst()
        switch outcome {
        case .success(let prices): return prices
        case .failure(let error): throw error
        }
    }
}

private struct MockQuoteService: GoldQuoteServicing {
    enum Outcome: Sendable {
        case success(GoldQuote)
        case failure(URLError)
    }

    let outcome: Outcome

    func fetchQuote() async throws -> GoldQuote {
        switch outcome {
        case .success(let quote): return quote
        case .failure(let error): throw error
        }
    }
}

@MainActor
@Test func viewModelLoadsSlicesAndSnapsSelection() async throws {
    let calendar = Calendar(identifier: .gregorian)
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    let fixture = [
        GoldDailyPrice(date: day(2026, 9, 14), open: 100, high: 110, low: 95, close: 1050),
        GoldDailyPrice(date: day(2026, 9, 15), open: 1050, high: 1090, low: 1040, close: 1080),
        GoldDailyPrice(date: day(2026, 9, 16), open: 1080, high: 1120, low: 1070, close: 1100),
    ]

    let model = HomeViewModel(service: MockGoldPriceService(outcome: .success(fixture)), quoteService: nil)
    await model.load()

    #expect(model.phase == .loaded)
    #expect(model.prices.count == 3)

    model.range = .all
    #expect(model.visiblePrices.count == 3)
    #expect(model.selectedPoint == nil)

    // 十字光标吸附到最近的交易日（读数为平滑线上的值：三日均值 1076.67）
    model.selectedDate = day(2026, 9, 15).addingTimeInterval(4 * 3600)
    #expect(model.selectedPoint?.date == day(2026, 9, 15))
    #expect(model.headlinePoint?.date == day(2026, 9, 15))
    #expect(abs((model.selectedPoint?.close ?? 0) - 1076.6667) < 0.001)

    // 涨跌相对前一交易日收盘：平滑值 − 昨收
    let change = try #require(model.headlineChange)
    #expect(abs(change.amount - 26.6667) < 0.001)
    #expect(abs(change.percent - 26.6667 / 1050.0 * 100) < 0.001)

    // 默认（未选中）头条 = 最新一日
    model.selectedDate = nil
    #expect(model.headlinePoint?.date == day(2026, 9, 16))
    let latestChange = try #require(model.headlineChange)
    #expect(latestChange.amount == 20)
}

@MainActor
@Test func viewModelEntersFailedStateOnEmptyLoad() async {
    let model = HomeViewModel(service: MockGoldPriceService(outcome: .failure(URLError(.badServerResponse))), quoteService: nil)
    await model.load()
    #expect(model.phase == .failed)
    #expect(model.prices.isEmpty)
}

@MainActor
@Test func viewModelKeepsDataWhenRefreshFails() async {
    let fixture = [
        GoldDailyPrice(date: Date(timeIntervalSince1970: 1_700_000_000), open: 1, high: 1, low: 1, close: 1)
    ]
    let model = HomeViewModel(
        service: SequencedMockService(outcomes: [
            .success(fixture),
            .failure(URLError(.notConnectedToInternet)),
        ]),
        quoteService: nil
    )
    await model.load()
    #expect(model.phase == .loaded)

    await model.load() // 第二次（刷新）失败
    #expect(model.phase == .loaded) // 有数据时刷新失败保持原状
    #expect(model.prices == fixture)
}

// MARK: - 实时报价轮询

@MainActor
@Test func applyQuoteUpdatesLastBarInPlace() async {
    let calendar = Calendar(identifier: .gregorian)
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    func at(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    let fixture = [
        GoldDailyPrice(date: day(2026, 9, 16), open: 1000, high: 1010, low: 990, close: 1005),
        GoldDailyPrice(date: day(2026, 9, 17), open: 1005, high: 1015, low: 1000, close: 1010),
    ]
    let model = HomeViewModel(service: MockGoldPriceService(outcome: .success(fixture)), quoteService: nil)
    await model.load()
    model.range = .all

    // 同日报价：就地更新收盘，放宽最高，不收窄最低
    model.applyQuote(
        GoldQuote(symbol: "XAUUSD", price: 1020, open: 1005, high: 1020, low: 1000, prevClose: 1005, usdCNY: 6.7, cnyPerGram: 920, asOf: at(2026, 9, 17, hour: 13, minute: 19))
    )
    #expect(model.prices.count == 2)
    #expect(model.prices.last?.close == 1020)
    #expect(model.prices.last?.high == 1020)
    #expect(model.prices.last?.low == 1000)
    #expect(model.visiblePrices.last?.close == 1020)

    // 头条 = 最新 bar（已带实时价），涨跌相对前一交易日收盘
    #expect(model.headlinePoint?.close == 1020)
    #expect(model.headlineChange?.amount == 15) // 1020 - 1005
    #expect(model.liveQuote?.price == 1020)
}

@MainActor
@Test func applyQuoteAppendsBarOnDayRollover() async {
    let calendar = Calendar(identifier: .gregorian)
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    let fixture = [
        GoldDailyPrice(date: day(2026, 9, 17), open: 1000, high: 1010, low: 990, close: 1010)
    ]
    let model = HomeViewModel(service: MockGoldPriceService(outcome: .success(fixture)), quoteService: nil)
    await model.load()
    model.range = .all

    // 次日早间的报价：追加以昨收开盘的新 bar
    let asOf = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 6, minute: 30))!
    model.applyQuote(GoldQuote(symbol: "XAUUSD", price: 1014, open: 1010, high: 1014, low: 1008, prevClose: 1010, usdCNY: 6.7, cnyPerGram: 920, asOf: asOf))

    #expect(model.prices.count == 2)
    #expect(model.prices.last?.date == day(2026, 9, 18))
    #expect(model.prices.last?.open == 1010) // 昨收开盘
    #expect(model.prices.last?.close == 1014)
    #expect(model.headlineChange?.amount == 4) // 1014 - 1010
}

@MainActor
@Test func pollQuoteFailsSilently() async {
    let calendar = Calendar(identifier: .gregorian)
    let fixture = [
        GoldDailyPrice(date: calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!, open: 1, high: 1, low: 1, close: 1010)
    ]
    let model = HomeViewModel(
        service: MockGoldPriceService(outcome: .success(fixture)),
        quoteService: MockQuoteService(outcome: .failure(URLError(.timedOut)))
    )
    await model.load()

    await model.pollQuote() // 轮询失败：静默，保留旧值
    #expect(model.liveQuote == nil)
    #expect(model.phase == .loaded)
    #expect(model.prices.last?.close == 1010)
}
