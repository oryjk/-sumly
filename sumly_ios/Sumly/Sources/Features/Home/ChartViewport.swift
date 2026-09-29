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

extension ChartViewport {
    enum Part { case window, start, end }

    static func noon(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
    }
    static func dayAligned(_ window: ClosedRange<Date>, bounds: ClosedRange<Date>,
                           minimumDays: Int = 1, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date> {
        let base = noon(bounds.lowerBound, calendar: calendar)
        let last = noon(bounds.upperBound, calendar: calendar)
        let total = max(1, calendar.dateComponents([.day], from: base, to: last).day ?? 1)
        let rawStart = calendar.dateComponents([.day], from: base, to: noon(window.lowerBound, calendar: calendar)).day ?? 0
        let rawEnd = calendar.dateComponents([.day], from: base, to: noon(window.upperBound, calendar: calendar)).day ?? total
        let width = min(total, max(minimumDays, rawEnd - rawStart))
        let start = min(max(0, rawStart), total - width)
        return calendar.date(byAdding: .day, value: start, to: base)!...calendar.date(byAdding: .day, value: start + width, to: base)!
    }
    static func navigate(_ window: ClosedRange<Date>, part: Part, fraction: Double,
                         bounds: ClosedRange<Date>, daily: Bool = true) -> ClosedRange<Date> {
        guard fraction.isFinite else { return window }
        let delta = fraction * bounds.upperBound.timeIntervalSince(bounds.lowerBound)
        let minimum: TimeInterval = min(bounds.upperBound.timeIntervalSince(bounds.lowerBound), daily ? 86400 : 30)
        let moved: ClosedRange<Date>
        switch part {
        case .window:
            moved = clamp(start: window.lowerBound.addingTimeInterval(delta), span: window.upperBound.timeIntervalSince(window.lowerBound), bounds: bounds)
        case .start:
            let limit = daily ? Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: window.upperBound)! : window.upperBound.addingTimeInterval(-minimum)
            let start = min(limit, max(bounds.lowerBound, window.lowerBound.addingTimeInterval(delta)))
            moved = start...window.upperBound
        case .end:
            let limit = daily ? Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: window.lowerBound)! : window.lowerBound.addingTimeInterval(minimum)
            let end = max(limit, min(bounds.upperBound, window.upperBound.addingTimeInterval(delta)))
            moved = window.lowerBound...end
        }
        if !daily { return moved }
        if part == .window {
            // Translate by calendar days; crossing DST must preserve the number of days.
            let calendar = Calendar(identifier: .gregorian)
            let days = max(1, calendar.dateComponents([.day], from: window.lowerBound, to: window.upperBound).day ?? 1)
            let start = noon(moved.lowerBound)
            let end = calendar.date(byAdding: .day, value: days, to: start)!
            return dayAligned(start...end, bounds: bounds)
        }
        return dayAligned(moved, bounds: bounds)
    }
}
