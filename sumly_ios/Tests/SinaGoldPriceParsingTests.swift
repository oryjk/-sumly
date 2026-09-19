import Testing
import Foundation
@testable import Sumly

@Test func parsesSinaJSONPArray() throws {
    let jsonp = """
    /*<script>location.href='//sina.com';</script>*/
    var t=([{"date":"2026-09-15","open":"3850.100","high":"3871.200","low":"3841.500","close":"3860.800","volume":"0","position":"0","s":"0.000"},{"date":"2026-09-16","open":"3860.800","high":"3882.400","low":"3855.100","close":"3875.250","volume":"0","position":"0","s":"0.000"}]);
    """
    let points = try SinaGoldPriceService.parse(Data(jsonp.utf8))
    #expect(points.count == 2)
    #expect(points[0].date == GoldDailyPrice.parseDay("2026-09-15"))
    #expect(points[0].open == 3850.1)
    #expect(points[0].high == 3871.2)
    #expect(points[0].low == 3841.5)
    #expect(points[0].close == 3860.8)
    #expect(points[1].close == 3875.25)
}

@Test func parseSkipsMalformedRowsAndSortsAscending() throws {
    let jsonp = """
    var t=([{"date":"2026-09-16","open":"2","high":"2","low":"2","close":"3875.250"},
    {"date":"bad-date","open":"1","high":"1","low":"1","close":"1"},
    {"date":"2026-09-15","open":"1","high":"1","low":"1","close":"3860.800"}]);
    """
    let points = try SinaGoldPriceService.parse(Data(jsonp.utf8))
    #expect(points.count == 2)
    #expect(points.map(\.close) == [3860.8, 3875.25]) // 升序
}

@Test func parseThrowsEmptyPayloadWhenNoArrayFound() {
    #expect(throws: SinaGoldPriceService.ParseError.emptyPayload) {
        try SinaGoldPriceService.parse(Data("var t=(null);".utf8))
    }
}

@Test func parseThrowsMalformedJSONP() {
    let jsonp = #"var t=([{"date":123,"open":"x"}]);"#
    #expect(throws: SinaGoldPriceService.ParseError.malformedJSONP) {
        try SinaGoldPriceService.parse(Data(jsonp.utf8))
    }
}

@Test func parseThrowsWhenAllRowsInvalid() {
    let jsonp = #"var t=([{"date":"nope","open":"a","high":"b","low":"c","close":"d"}]);"#
    #expect(throws: SinaGoldPriceService.ParseError.noValidRows) {
        try SinaGoldPriceService.parse(Data(jsonp.utf8))
    }
}

@Test func dayParsingPinsLocalNoon() throws {
    let date = try #require(GoldDailyPrice.parseDay("2026-09-16"))
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
    #expect(parts.year == 2026)
    #expect(parts.month == 9)
    #expect(parts.day == 16)
    #expect(parts.hour == 12)
}

@Test func dayParsingRejectsGarbage() {
    #expect(GoldDailyPrice.parseDay("2026/09/16") == nil)
    #expect(GoldDailyPrice.parseDay("2026-09") == nil)
    #expect(GoldDailyPrice.parseDay("") == nil)
}

@Test func dayParsingAcceptsUnpaddedParts() throws {
    // 宽松解析：月份/日期未补零也可接受
    let date = try #require(GoldDailyPrice.parseDay("2026-9-6"))
    let parts = Calendar.current.dateComponents([.month, .day], from: date)
    #expect(parts.month == 9)
    #expect(parts.day == 6)
}
