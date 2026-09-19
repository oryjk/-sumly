import Testing
import Foundation
@testable import Sumly

@Test func decodesQuoteEnvelope() throws {
    // envelope 外层 {code,message,data} 在 get() 中剥开，这里测 data 部分
    let json = """
    {"symbol":"XAUUSD","price":4288.66,"open":4288.66,
    "high":4318.02,"low":4257.40,"prev_close":4263.94,"change":24.72,"change_percent":0.58,
    "usd_cny":6.7084,"cny_per_gram":925.93,
    "as_of":"2026-09-17T13:19:00+08:00"}
    """
    let dto = try JSONDecoder().decode(BackendGoldPriceService.QuoteDTO.self, from: Data(json.utf8))
    let quote = try BackendGoldPriceService.decodeQuote(dto)

    #expect(quote.symbol == "XAUUSD")
    #expect(quote.price == 4288.66)
    #expect(quote.prevClose == 4263.94)
    #expect(quote.usdCNY == 6.7084)
    #expect(quote.cnyPerGram == 925.93)
    #expect(abs(quote.change - 24.72) < 0.0001)
    #expect(abs(quote.changePercent - 24.72 / 4263.94 * 100) < 0.0001)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: quote.asOf)
    #expect(parts.year == 2026 && parts.month == 9 && parts.day == 17)
    #expect(parts.hour == 13 && parts.minute == 19)
}

@Test func decodesDailyEnvelope() throws {
    let json = """
    {"symbol":"XAUUSD","bars":[
    {"date":"2026-09-15","open":3850.1,"high":3871.2,"low":3841.5,"close":3860.8},
    {"date":"bad-date","open":1,"high":1,"low":1,"close":1},
    {"date":"2026-09-16","open":3860.8,"high":3882.4,"low":3855.1,"close":3875.25}]}
    """
    let dto = try JSONDecoder().decode(BackendGoldPriceService.DailyDTO.self, from: Data(json.utf8))
    let prices = try BackendGoldPriceService.decodeDailyBars(dto.bars)

    #expect(prices.count == 2)
    #expect(prices.map(\.close) == [3860.8, 3875.25]) // 升序，坏行跳过
}

@Test func emptyDailyBarsThrow() {
    #expect(throws: BackendGoldPriceService.ServiceError.emptyData) {
        try BackendGoldPriceService.decodeDailyBars([])
    }
}

@Test func malformedQuoteTimeThrows() throws {
    let dto = try JSONDecoder().decode(
        BackendGoldPriceService.QuoteDTO.self,
        from: Data(#"{"symbol":"XAUUSD","price":1,"open":1,"high":1,"low":1,"prev_close":1,"usd_cny":6.7,"cny_per_gram":920,"as_of":"not-a-date"}"#.utf8)
    )
    #expect(throws: BackendGoldPriceService.ServiceError.malformedPayload) {
        try BackendGoldPriceService.decodeQuote(dto)
    }
}
