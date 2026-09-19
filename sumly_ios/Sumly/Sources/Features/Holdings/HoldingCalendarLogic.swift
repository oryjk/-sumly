import Foundation

enum HoldingCalendarPeriod: String, CaseIterable { case day = "日", month = "月", year = "年", all = "全部" }
struct HoldingCalendarFilter: Equatable {
    var keyword = ""
    var kind = "all"
    var book: String? = nil
}
struct HoldingCalendarEvent: Identifiable {
    var id: String
    var purchaseID: UUID
    var date: Date
    var kind: String
    var grams: Double
    var cost: Double
    var fees: Double
    var proceeds: Double
    var title: String
}
struct HoldingCalendarSummary {
    var count: Int
    var grams: Double
    var fees: Double
    var cost: Double
    var average: Double
    var profitPercent: Double?
    var sold: Double
    var gifted: Double
}
/// 日历按事件日期汇总；拆分持仓共享购入编号，购入件数不会因赠卖增加。
enum HoldingCalendarLogic {
    static func events(_ records: [HoldingRecord], filter: HoldingCalendarFilter) -> [HoldingCalendarEvent] {
        var result: [HoldingCalendarEvent] = []
        for r in records {
            guard filter.book == nil || r.bookName == filter.book else { continue }
            let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard keyword.isEmpty || [r.brand, r.note, r.purchaseChannel, r.counterparty].contains(where: { $0.localizedCaseInsensitiveContains(keyword) }) else { continue }
            let purchase = r.purchaseID ?? r.id
            let title = r.brand.isEmpty ? "未知" : r.brand
            if filter.kind == "all" || (filter.kind == "holding" && r.disposition == "holding") {
                result.append(.init(id: "buy-\(r.id)", purchaseID: purchase, date: r.timestamp, kind: "buy", grams: r.grams, cost: r.grams * r.unitPriceCNY + r.extraFee, fees: r.extraFee, proceeds: 0, title: title))
            }
            if r.disposition != "holding", let date = r.disposedAt, filter.kind == "all" || filter.kind == r.disposition {
                result.append(.init(id: "dispose-\(r.id)", purchaseID: purchase, date: date, kind: r.disposition, grams: r.grams, cost: r.grams * r.unitPriceCNY + r.extraFee, fees: r.extraFee, proceeds: r.disposalAmount, title: title))
            }
        }
        return result.sorted { $0.date > $1.date }
    }
    static func select(_ events: [HoldingCalendarEvent], period: HoldingCalendarPeriod, date: Date, calendar: Calendar = .current) -> [HoldingCalendarEvent] {
        guard period != .all else { return events }
        let component: Calendar.Component = period == .day ? .day : period == .month ? .month : .year
        guard let interval = calendar.dateInterval(of: component, for: date) else { return [] }
        return events.filter { $0.date >= interval.start && $0.date < interval.end }
    }
    static func days(in date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date)?.start,
              let start = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: month), to: month) else { return [] }
        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
        }
    }
    static func stats(_ events: [HoldingCalendarEvent], quote: Double?) -> HoldingCalendarSummary {
        let buys = events.filter { $0.kind == "buy" }
        let grams = buys.reduce(0) { $0 + $1.grams }
        let cost = buys.reduce(0) { $0 + $1.cost }
        let fees = buys.reduce(0) { $0 + $1.fees }
        let profit = quote.flatMap { $0.isFinite && $0 > 0 && cost > 0 ? (grams * $0 - cost) / cost * 100 : nil }
        return .init(count: Set(buys.map(\.purchaseID)).count, grams: grams, fees: fees, cost: cost, average: grams > 0 ? (cost - fees) / grams : 0, profitPercent: profit,
                     sold: events.filter { $0.kind == "sold" }.reduce(0) { $0 + $1.grams }, gifted: events.filter { $0.kind == "gift" }.reduce(0) { $0 + $1.grams })
    }
    static func lunar(_ date: Date) -> String {
        let calendar = Calendar(identifier: .chinese)
        let day = calendar.component(.day, from: date)
        if day == 1 {
            let months = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
            return (calendar.dateComponents([.isLeapMonth], from: date).isLeapMonth == true ? "闰" : "") + months[calendar.component(.month, from: date) - 1]
        }
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        if day <= 10 { return "初" + digits[day - 1] }
        if day < 20 { return "十" + digits[day - 11] }
        if day == 20 { return "二十" }
        if day < 30 { return "廿" + digits[day - 21] }
        return "三十"
    }
}
