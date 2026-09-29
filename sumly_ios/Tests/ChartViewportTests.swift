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
