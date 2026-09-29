import Foundation
import Observation

struct MarketChartPoint: Sendable, Equatable {
    let date: Date
    let price: Double
    var granularity: GoldPointGranularity = .realtime
}

protocol GoldIntradayServicing: Sendable {
    func fetchIntraday() async throws -> [MarketChartPoint]
}

protocol GoldRealtimeServicing: Sendable {
    func fetchRealtime() async throws -> [MarketChartPoint]
}

enum MarketRange: String, CaseIterable {
    case realtime = "实时"
    case month = "近一月"
    case quarter = "近三月"
    case history = "1900年至今"
}

@MainActor @Observable
final class MarketHomeViewModel {
    var range: MarketRange = .realtime { didSet { resetViewport() } }
    var selectedDate: Date?
    var priceScale: ChartPriceScale = .linear
    private var cacheGeneration: UInt = 0
    private(set) var viewport: ClosedRange<Date>?
    private var gestureViewport: ClosedRange<Date>?
    private(set) var history: [GoldHistoryPoint] = []
    private var historyFailed = false
    private(set) var historyLoading = false
    private let historyService: any GoldHistoryServicing
    private(set) var quote: GoldQuote?
    private(set) var daily: [GoldDailyPrice] = []
    private(set) var realtime: [MarketChartPoint] = []
    private(set) var loading = true
    private var quoteFailed = false
    private var dailyFailed = false
    private var realtimeFailed = false
    private let dailyService: any GoldPriceServicing
    private let quoteService: any GoldQuoteServicing
    private let realtimeService: any GoldRealtimeServicing

    init(dailyService: any GoldPriceServicing = BackendGoldPriceService(),
         quoteService: any GoldQuoteServicing = BackendGoldPriceService(),
         realtimeService: any GoldRealtimeServicing = BackendGoldPriceService(),
         historyService: any GoldHistoryServicing = BackendGoldPriceService()) {
        self.historyService = historyService
        self.dailyService = dailyService
        self.quoteService = quoteService
        self.realtimeService = realtimeService
    }

    var price: Double? {
        guard let quote, quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 else { return nil }
        return quote.cnyPerGram
    }

    var points: [MarketChartPoint] {
        if range == .realtime { return Self.realtimeWindow(realtime, now: .now) }
        guard let quote, quote.usdCNY.isFinite, quote.usdCNY > 0 else { return [] }
        let factor = quote.usdCNY / 31.1034768
        let lastDay = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        var result: [MarketChartPoint]
        if !history.isEmpty {
            result = history.filter { ChartViewport.noon($0.date) <= lastDay }.map {
                MarketChartPoint(date: ChartViewport.noon($0.date), price: $0.price * factor, granularity: $0.granularity)
            }
        } else {
            if range == .history { return [] }
            result = daily.filter { ChartViewport.noon($0.date) <= lastDay }.map {
                MarketChartPoint(date: ChartViewport.noon($0.date), price: $0.close * factor, granularity: .daily)
            }
        }
        guard !result.isEmpty else { return [] }
        result = result.filter { $0.price.isFinite && $0.price > 0 }.sorted { $0.date < $1.date }
        return result
    }

    var showsInitialLoading: Bool { loading && price == nil && points.isEmpty }

    var message: String? {
        if loading { return "正在获取行情…" }
        if quoteFailed { return quote == nil ? "行情加载失败，点击重试" : "刷新失败，显示上次行情 · 点击重试" }
        if price == nil { return "人民币报价暂不可用 · 点击重试" }
        if range == .history && historyLoading { return "正在加载百年走势…" }
        if range == .history && historyFailed { return "历史走势加载失败 · 点击重试" }
        if range == .realtime ? realtimeFailed : (range == .history ? historyFailed : dailyFailed) { return "走势刷新失败 · 点击重试" }
        if let quote, Date.now.timeIntervalSince(quote.asOf) > 180 {
            return "最近报价 \(quote.asOf.formatted(.dateTime.month().day().hour().minute()))"
        }
        if range == .realtime {
            if realtime.isEmpty { return "暂无最新走势，请稍后再试" }
            if let last = realtime.last, Date.now.timeIntervalSince(last.date) > 20 {
                return "行情更新暂停，最近更新 \(last.date.formatted(.dateTime.hour().minute().second()))"
            }
        }
        return nil
    }

    nonisolated static func realtimeWindow(_ points: [MarketChartPoint], now: Date) -> [MarketChartPoint] {
        let valid = points.filter { $0.date <= now && $0.price.isFinite && $0.price > 0 }
            .sorted { $0.date < $1.date }
        guard let latest = valid.last else { return [] }
        let cutoff = latest.date.addingTimeInterval(-1200)
        return valid.filter { $0.date >= cutoff }
    }

    /// 纵轴保留呼吸空间，以半元为刻度边界，避免每次尾点变化都拉伸整条曲线。
    nonisolated static func chartDomain(_ points: [MarketChartPoint]) -> ClosedRange<Double> {
        let low = points.map(\.price).min() ?? 0
        let high = points.map(\.price).max() ?? 1
        let center = (low + high) / 2
        let span = max((high - low) * 1.5, 1)
        return (floor((center - span / 2) * 2) / 2)...(ceil((center + span / 2) * 2) / 2)
    }

    var selectedPoint: MarketChartPoint? {
        let window = xDomain
        let values = points.filter { window.contains($0.date) }
        guard let selectedDate, window.contains(selectedDate) else { return nil }
        return values.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    func start() async {
        await refresh()
        var tick = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await loadQuote()
            tick += 1
            await loadRealtime()
            if tick % 12 == 0 { await loadDaily(); if range != .realtime { await loadHistory() } }
        }
    }

    func refresh() async {
        if quote == nil && realtime.isEmpty && daily.isEmpty { loading = true }
        async let q: Void = loadQuote()
        async let d: Void = loadDaily()
        async let i: Void = loadRealtime()
        _ = await (q, d, i)
        if range != .realtime { await loadHistory() }
        loading = false
    }

    var fullDomain: ClosedRange<Date> {
        let values = points
        if range == .realtime {
            let end = values.last?.date ?? .now
            let start = values.first?.date ?? end.addingTimeInterval(-1200)
            return start...max(end, start.addingTimeInterval(1))
        }
        let end = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        let start = history.isEmpty ? (values.first?.date ?? Calendar.current.date(byAdding: .day, value: -1, to: end)!) : GoldDailyPrice.parseDay("1900-01-01")!
        return min(start, Calendar.current.date(byAdding: .day, value: -1, to: end)!)...end
    }
    var presetDomain: ClosedRange<Date> {
        let bounds = fullDomain
        guard range == .month || range == .quarter else { return bounds }
        let start = Calendar.current.date(byAdding: .month, value: range == .month ? -1 : -3, to: bounds.upperBound)!
        return ChartViewport.dayAligned(start...bounds.upperBound, bounds: bounds)
    }
    var xDomain: ClosedRange<Date> {
        guard let viewport else { return presetDomain }
        let bounds = fullDomain
        if range == .realtime { return ChartViewport.pan(viewport, fraction: 0, bounds: bounds) }
        return ChartViewport.dayAligned(viewport, bounds: bounds)
    }
    var windowPoints: [MarketChartPoint] {
        let window = xDomain
        return points.filter { window.contains($0.date) }
    }
    var canReset: Bool { xDomain != presetDomain }
    var axisDates: [Date] {
        let window = xDomain
        if range == .realtime {
            let span = window.upperBound.timeIntervalSince(window.lowerBound)
            return (0...3).map { window.lowerBound.addingTimeInterval(span * Double($0) / 3) }
        }
        let days = Calendar.current.dateComponents([.day], from: window.lowerBound, to: window.upperBound).day ?? 1
        let offsets = Set((0...3).map { Int((Double(days) * Double($0) / 3).rounded()) })
        return offsets.sorted().map { Calendar.current.date(byAdding: .day, value: $0, to: window.lowerBound)! }
    }
    var visiblePoints: [MarketChartPoint] {
        let values = points
        let window = xDomain
        // Adjacent actual points keep a clipped line continuous without making new observations.
        let first = values.firstIndex { $0.date >= window.lowerBound } ?? values.count
        let last = values.lastIndex { $0.date <= window.upperBound } ?? -1
        let lower = max(0, first - 1)
        let upper = min(values.count, last + 2)
        guard lower < upper else { return [] }
        return Array(values[lower..<upper])
    }
    func resetViewport() { viewport = nil; gestureViewport = nil; selectedDate = nil }
    func beginChartGesture() { gestureViewport = xDomain; selectedDate = nil }
    func transformChart(scale: Double, anchor: Double, translation: Double) {
        guard let initial = gestureViewport else { return }
        let focal = initial.lowerBound.addingTimeInterval(initial.upperBound.timeIntervalSince(initial.lowerBound) * anchor)
        let minimum: TimeInterval = range == .realtime ? 30 : (focal < GoldDailyPrice.parseDay("2016-01-01")! ? 366 * 86400 : 86400)
        let zoomed = ChartViewport.zoom(initial, scale: scale, anchor: anchor, bounds: fullDomain, minimumSpan: minimum)
        let moved = ChartViewport.pan(zoomed, fraction: translation, bounds: fullDomain)
        viewport = range == .realtime ? moved : ChartViewport.dayAligned(moved, bounds: fullDomain)
        selectedDate = nil
    }
    func beginNavigatorGesture() { gestureViewport = xDomain; selectedDate = nil }
    func moveNavigator(part: ChartViewport.Part, fraction: Double) {
        guard let initial = gestureViewport else { return }
        viewport = ChartViewport.navigate(initial, part: part, fraction: fraction, bounds: fullDomain, daily: range != .realtime)
    }
    func setDateWindow(_ window: ClosedRange<Date>) {
        viewport = ChartViewport.dayAligned(window, bounds: fullDomain)
        selectedDate = nil
    }
    func endChartGesture() { gestureViewport = nil }
    func accessibleZoom(_ scale: Double) { beginChartGesture(); transformChart(scale: scale, anchor: 0.5, translation: 0); endChartGesture() }
    func selectChart(at fraction: Double) {
        guard gestureViewport == nil else { return }
        let domain = xDomain
        selectedDate = domain.lowerBound.addingTimeInterval(domain.upperBound.timeIntervalSince(domain.lowerBound) * min(1, max(0, fraction)))
    }
    func loadHistory() async {
        guard !historyLoading else { return }
        historyLoading = true
        defer { historyLoading = false }
        let generation = cacheGeneration
        if let cached = await historyService.cachedHistory(), generation == cacheGeneration { history = cached }
        guard generation == cacheGeneration, !Task.isCancelled else { return }
        do {
            let fetched = try await historyService.fetchHistory()
            guard generation == cacheGeneration, !Task.isCancelled else { return }
            history = fetched; historyFailed = false
        }
        catch { if !Task.isCancelled { historyFailed = true } }
    }

    func clearMarketCache() {
        cacheGeneration &+= 1
        daily = []; history = []; realtime = []; quote = nil; selectedDate = nil
        resetViewport()
    }

    private func loadQuote() async {
        let generation = cacheGeneration
        if quote == nil, let cached = await quoteService.cachedQuote(), generation == cacheGeneration { quote = cached }
        guard generation == cacheGeneration, !Task.isCancelled else { return }
        do {
            let fetched = try await quoteService.fetchQuote()
            guard generation == cacheGeneration, !Task.isCancelled else { return }
            quote = fetched; quoteFailed = false
        }
        catch { if !Task.isCancelled { quoteFailed = true } }
    }
    private func loadDaily() async {
        let generation = cacheGeneration
        if let cached = await dailyService.cachedDailyPrices(), generation == cacheGeneration { daily = cached }
        guard generation == cacheGeneration, !Task.isCancelled else { return }
        do {
            let fetched = try await dailyService.fetchDailyPrices()
            guard generation == cacheGeneration, !Task.isCancelled else { return }
            daily = fetched; dailyFailed = false
        }
        catch { if !Task.isCancelled { dailyFailed = true } }
    }
    private func loadRealtime() async {
        let generation = cacheGeneration
        guard generation == cacheGeneration, !Task.isCancelled else { return }
        do {
            let fetched = try await realtimeService.fetchRealtime()
            guard generation == cacheGeneration, !Task.isCancelled else { return }
            realtime = fetched; realtimeFailed = false
        }
        catch { if !Task.isCancelled { realtimeFailed = true } }
    }
}
