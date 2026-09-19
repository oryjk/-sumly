import Foundation

enum HoldingFilter: String, CaseIterable { case all = "全部", profit = "盈利", loss = "亏损" }
enum HoldingSort: String, CaseIterable { case newest = "时间从新到旧", oldest = "时间从旧到新", heaviest = "重量从多到少", costliest = "购入总价从高到低" }

enum HoldingsSelection {
    static func dateText(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d.%02d.%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func records(_ records: [HoldingRecord], book: String, search: String, filter: HoldingFilter, sort: HoldingSort, quote: Double?) -> [HoldingRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            guard record.bookName == book, record.disposition == "holding" else { return false }
            guard query.isEmpty || (record.brand.isEmpty ? "未知" : record.brand).localizedCaseInsensitiveContains(query) || record.note.localizedCaseInsensitiveContains(query) else { return false }
            if filter != .all {
                guard let quote, quote.isFinite, quote > 0 else { return false }
                let profit = quote - record.unitPriceCNY
                if filter == .profit && profit < 0 { return false }
                if filter == .loss && profit >= 0 { return false }
            }
            return true
        }.sorted { a, b in
            switch sort {
            case .newest: return a.timestamp > b.timestamp
            case .oldest: return a.timestamp < b.timestamp
            case .heaviest: return a.grams == b.grams ? a.timestamp > b.timestamp : a.grams > b.grams
            case .costliest: return a.grams * a.unitPriceCNY > b.grams * b.unitPriceCNY
            }
        }
    }
}
