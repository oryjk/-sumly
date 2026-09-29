import Foundation
import Testing
@testable import Sumly

@Test func visibleStatisticsUseChronologicalEndpointsAndActualExtrema() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let points = [100.0, 140, 80, 110].enumerated().map {
        MarketChartPoint(date: date.addingTimeInterval(Double($0.offset) * 86400), price: $0.element)
    }
    let stats = ChartWindowStatistics(points: points.reversed())
    #expect(stats.change == 10)
    #expect(abs(stats.percent! - 10) < 0.000001)
    #expect(stats.high?.price == 140)
    #expect(stats.low?.price == 80)
    let slice = ChartWindowStatistics(points: Array(points[1...2]))
    #expect(slice.change == -60)
    #expect(abs(slice.percent! + 42.857142857) < 0.000001)
}

@Test func visibleStatisticsHandleEmptySingleFlatAndInvalidPrices() {
    let date = Date.now
    #expect(ChartWindowStatistics(points: []).high == nil)
    let single = ChartWindowStatistics(points: [MarketChartPoint(date: date, price: 123)])
    #expect(single.change == nil)
    #expect(single.high == single.low)
    let flat = ChartWindowStatistics(points: [MarketChartPoint(date: date, price: 123), MarketChartPoint(date: date.addingTimeInterval(1), price: 123)])
    #expect(flat.change == 0)
    #expect(flat.percent == 0)
    let invalid = ChartWindowStatistics(points: [MarketChartPoint(date: date, price: .nan), MarketChartPoint(date: date, price: -1)])
    #expect(invalid.low == nil)
}

@Test func extremeLabelsStaySeparatedWhenPricesClusterNearPlotEdges() {
    for y in [0.0, 1, 100, 199, 200] {
        let high = ChartExtremaLabelLayout.y(point: y, other: y, height: 200, above: true)
        let low = ChartExtremaLabelLayout.y(point: y, other: y, height: 200, above: false)
        #expect(high >= 14)
        #expect(low <= 186)
        #expect(low - high >= 32)
    }
}
