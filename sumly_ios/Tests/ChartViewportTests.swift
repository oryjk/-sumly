import Foundation
import Testing
@testable import Sumly

@Test func pinchZoomPreservesAnchorAndClampsToAvailableDates() {
 let bounds = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1000)
 let zoom = ChartViewport.zoom(bounds, scale: 2, anchor: 0.25, bounds: bounds, minimumSpan: 10)
 #expect(zoom.lowerBound.timeIntervalSince1970 == 125)
 #expect(zoom.upperBound.timeIntervalSince1970 == 625)
 #expect(ChartViewport.zoom(zoom, scale: 0.01, anchor: 0, bounds: bounds, minimumSpan: 10) == bounds)
 let minimum = ChartViewport.zoom(bounds, scale: 10000, anchor: 1, bounds: bounds, minimumSpan: 10)
 #expect(minimum.lowerBound.timeIntervalSince1970 == 990)
 #expect(minimum.upperBound == bounds.upperBound)
 #expect(ChartViewport.zoom(bounds, scale: .nan, anchor: 0, bounds: bounds, minimumSpan: 10) == bounds)
}
@Test func panStopsAtHistoryBoundariesWithoutChangingSpan() {
 let bounds = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1000)
 let window = Date(timeIntervalSince1970: 200)...Date(timeIntervalSince1970: 400)
 let left = ChartViewport.pan(window, fraction: 5, bounds: bounds)
 #expect(left.lowerBound == bounds.lowerBound)
 #expect(left.upperBound.timeIntervalSince1970 == 200)
 let right = ChartViewport.pan(window, fraction: -5, bounds: bounds)
 #expect(right.upperBound == bounds.upperBound)
 #expect(right.lowerBound.timeIntervalSince1970 == 800)
}

@Test func dayAlignedWindowsHaveNoSubdayEndpointsAcrossDST() {
 var calendar = Calendar(identifier: .gregorian)
 calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
 func day(_ d: Int, hour: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour))! }
 let bounds = day(1)...day(20)
 let window = ChartViewport.dayAligned(day(7, hour: 23)...day(9, hour: 4), bounds: bounds, calendar: calendar)
 #expect(window == day(7)...day(9))
 let tiny = ChartViewport.dayAligned(day(8, hour: 13)...day(8, hour: 14), bounds: bounds, calendar: calendar)
 #expect(calendar.dateComponents([.day], from: tiny.lowerBound, to: tiny.upperBound).day == 1)
 #expect(calendar.component(.hour, from: tiny.lowerBound) == 12)
 #expect(calendar.component(.hour, from: tiny.upperBound) == 12)
}
@Test func navigatorMovesWholeWindowAndResizesWithoutCrossingEndpoints() {
 let base = GoldDailyPrice.parseDay("2026-01-01")!
 let bounds = base...Calendar.current.date(byAdding: .day, value: 100, to: base)!
 let window = Calendar.current.date(byAdding: .day, value: 20, to: base)!...Calendar.current.date(byAdding: .day, value: 40, to: base)!
 let moved = ChartViewport.navigate(window, part: .window, fraction: 0.1, bounds: bounds)
 #expect(Calendar.current.dateComponents([.day], from: window.lowerBound, to: moved.lowerBound).day == 10)
 #expect(moved.upperBound.timeIntervalSince(moved.lowerBound) == window.upperBound.timeIntervalSince(window.lowerBound))
 let resized = ChartViewport.navigate(window, part: .start, fraction: 0.15, bounds: bounds)
 #expect(resized.upperBound == window.upperBound)
 #expect(resized.lowerBound > window.lowerBound)
 let clamped = ChartViewport.navigate(window, part: .end, fraction: -10, bounds: bounds)
 #expect(clamped.lowerBound < clamped.upperBound)
}

@Test func realtimeNavigatorCannotResizePastVeryShortAvailableWindow() {
    let start = Date(timeIntervalSince1970: 1000)
    let bounds = start...start.addingTimeInterval(1)
    for part in [ChartViewport.Part.start, .end] {
        let result = ChartViewport.navigate(bounds, part: part, fraction: 1, bounds: bounds, daily: false)
        #expect(result.lowerBound >= bounds.lowerBound)
        #expect(result.upperBound <= bounds.upperBound)
    }
}
