import Foundation

/// Time-domain math shared by touch gestures and accessibility controls.
enum ChartViewport {
    static func zoom(_ window: ClosedRange<Date>, scale: Double, anchor: Double,
                     bounds: ClosedRange<Date>, minimumSpan: TimeInterval) -> ClosedRange<Date> {
        guard scale.isFinite, scale > 0, anchor.isFinite else { return window }
        let full = bounds.upperBound.timeIntervalSince(bounds.lowerBound)
        guard full > 0 else { return bounds }
        let oldSpan = window.upperBound.timeIntervalSince(window.lowerBound)
        let span = min(full, max(minimumSpan, oldSpan / scale))
        let position = min(1, max(0, anchor))
        let start = window.lowerBound.addingTimeInterval((oldSpan - span) * position)
        return clamp(start: start, span: span, bounds: bounds)
    }
    static func pan(_ window: ClosedRange<Date>, fraction: Double, bounds: ClosedRange<Date>) -> ClosedRange<Date> {
        guard fraction.isFinite else { return window }
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        return clamp(start: window.lowerBound.addingTimeInterval(-fraction * span), span: span, bounds: bounds)
    }
    private static func clamp(start: Date, span: TimeInterval, bounds: ClosedRange<Date>) -> ClosedRange<Date> {
        let width = min(max(0, span), bounds.upperBound.timeIntervalSince(bounds.lowerBound))
        let lower = min(max(start, bounds.lowerBound), bounds.upperBound.addingTimeInterval(-width))
        return lower...lower.addingTimeInterval(width)
    }
}
