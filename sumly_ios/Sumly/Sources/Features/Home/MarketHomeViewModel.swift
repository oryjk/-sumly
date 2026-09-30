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

struct MarketHomeDataServices {
    let daily: any GoldPriceServicing
    let quote: any GoldQuoteServicing
    let realtime: any GoldRealtimeServicing
    let history: any GoldHistoryServicing

    static func backend(for basis: GoldMarketBasis) -> MarketHomeDataServices {
        let backend = BackendGoldPriceService(instrumentID: basis.instrumentID)
        return MarketHomeDataServices(daily: backend, quote: backend, realtime: backend, history: backend)
    }
}

enum MarketRange: String, CaseIterable {
    case realtime = "实时"
    case month = "近一月"
    case quarter = "近三月"
    case yearToDate = "今年以来"
    case year = "近一年"
    case twoYears = "近两年"
    case threeYears = "近三年"
    case fiveYears = "近五年"
    case tenYears = "近十年"
    case history = "1900年至今"

    func dateBounds(now: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date>? {
        let end = ChartViewport.noon(calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)
        let start: Date
        switch self {
        case .realtime: return nil
        case .month, .quarter:
            start = calendar.date(byAdding: .month, value: self == .month ? -1 : -3, to: end)!
        case .yearToDate:
            start = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1, hour: 12))!
        case .year, .twoYears, .threeYears, .fiveYears, .tenYears:
            let years = self == .year ? 1 : self == .twoYears ? 2 : self == .threeYears ? 3 : self == .fiveYears ? 5 : 10
            start = calendar.date(byAdding: .year, value: -years, to: end)!
        case .history:
            start = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1, hour: 12))!
        }
        return start <= end ? start...end : nil
    }
}

@MainActor @Observable
final class MarketHomeViewModel {
    var range: MarketRange = .realtime { didSet { resetViewport() } }
    var selectedDate: Date?
    var priceScale: ChartPriceScale = .linear
    private var cacheGeneration: UInt = 0
    private(set) var viewport: ClosedRange<Date>?
    private var gestureViewport: ClosedRange<Date>?
    private(set) var history: [GoldHistoryPoint] = [] {
        didSet { if history != oldValue { historyRevision &+= 1 } }
    }
    private var historyFailed = false
    private(set) var historyLoading = false
    private(set) var basis: GoldMarketBasis
    private var historyService: any GoldHistoryServicing
    private(set) var quote: GoldQuote?
    private(set) var daily: [GoldDailyPrice] = [] {
        didSet { if daily != oldValue { historyRevision &+= 1 } }
    }
    private(set) var realtime: [MarketChartPoint] = []
    private var quoteLoading = true
    private var dailyLoading = true
    private var realtimeLoading = true
    private var quoteRequest: UUID?
    private var dailyRequest: UUID?
    private var realtimeRequest: UUID?
    private var historyRequest: UUID?
    var chartLoading: Bool { range == .realtime ? realtimeLoading : (dailyLoading || historyLoading) }
    var loading: Bool { (quoteLoading && quote == nil) || (chartLoading && points.isEmpty) }
    private var quoteFailed = false
    private var dailyFailed = false
    private var realtimeFailed = false
    private var dailyService: any GoldPriceServicing
    private var quoteService: any GoldQuoteServicing
    private var realtimeService: any GoldRealtimeServicing
    private let serviceFactory: (GoldMarketBasis) -> MarketHomeDataServices
    private var basisSwitchRequest: UUID?
    private(set) var isSwitchingBasis = false

    // Derived data is not observable state: filling this cache during a view read
    // must not schedule another SwiftUI render. Source properties remain observed.
    private var historyRevision: UInt = 0
    @ObservationIgnored private var preparedKey: HistoricalPointsKey?
    @ObservationIgnored private var preparedPoints: [MarketChartPoint] = []
    @ObservationIgnored private var scopedKey: HistoricalPointsKey?
    @ObservationIgnored private var scopedRange: MarketRange?
    @ObservationIgnored private var scopedPoints: [MarketChartPoint] = []
    private struct HistoricalPointsKey: Equatable {
        let revision: UInt
        let factor: Double
        let lastDay: Date
        let timeZone: TimeZone
    }

    init(basis: GoldMarketBasis = .international,
         dailyService: (any GoldPriceServicing)? = nil,
         quoteService: (any GoldQuoteServicing)? = nil,
         realtimeService: (any GoldRealtimeServicing)? = nil,
         historyService: (any GoldHistoryServicing)? = nil,
         serviceFactory: ((GoldMarketBasis) -> MarketHomeDataServices)? = nil) {
        let backend = MarketHomeDataServices.backend(for: basis)
        self.basis = basis
        self.historyService = historyService ?? backend.history
        self.dailyService = dailyService ?? backend.daily
        self.quoteService = quoteService ?? backend.quote
        self.realtimeService = realtimeService ?? backend.realtime
        self.serviceFactory = serviceFactory ?? { MarketHomeDataServices.backend(for: $0) }
    }

    var price: Double? {
        guard let quote, quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 else { return nil }
        return quote.cnyPerGram
    }

    var points: [MarketChartPoint] {
        if range == .realtime { return Self.realtimeWindow(realtime, now: .now) }
        let factor: Double
        switch basis {
        case .domestic:
            factor = 1
        case .international:
            guard let quote, quote.usdCNY.isFinite, quote.usdCNY > 0 else { return [] }
            factor = quote.usdCNY / 31.1034768
        }
        let lastDay = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        if history.isEmpty && range == .history { return [] }
        let key = HistoricalPointsKey(revision: historyRevision, factor: factor, lastDay: lastDay, timeZone: .current)
        if preparedKey == key { return pointsInSelectedRange(key: key) }
        let source = history.isEmpty
            ? daily.map { MarketChartPoint(date: $0.date, price: $0.close, granularity: .daily) }
            : history.map { MarketChartPoint(date: $0.date, price: $0.price, granularity: $0.granularity) }
        preparedPoints = source.compactMap { point in
            let date = ChartViewport.noon(point.date)
            let price = point.price * factor
            guard date <= lastDay, price.isFinite, price > 0 else { return nil }
            return MarketChartPoint(date: date, price: price, granularity: point.granularity)
        }.sorted { $0.date < $1.date }
        preparedKey = key
        return pointsInSelectedRange(key: key)
    }

    private func pointsInSelectedRange(key: HistoricalPointsKey) -> [MarketChartPoint] {
        if scopedKey == key && scopedRange == range { return scopedPoints }
        if let bounds = range.dateBounds() {
            scopedPoints = preparedPoints.filter { bounds.contains($0.date) }
        } else { scopedPoints = [] }
        scopedKey = key
        scopedRange = range
        return scopedPoints
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
        // Each stream owns its retry schedule: slow historical sync must not
        // prevent live prices recovering after a foreground/network transition.
        async let quotes: Void = poll(every: .seconds(5)) { await self.loadQuote() }
        async let realtime: Void = poll(every: .seconds(5)) { await self.loadRealtime() }
        async let history: Void = poll(every: .seconds(60)) {
            await self.loadDaily()
            if self.range != .realtime { await self.loadHistory() }
        }
        _ = await (quotes, realtime, history)
    }

    private func poll(every interval: Duration, operation: @MainActor () async -> Void) async {
        while !Task.isCancelled {
            await operation()
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }

    func refresh() async {
        async let q: Void = loadQuote()
        async let d: Void = loadDaily()
        async let i: Void = loadRealtime()
        _ = await (q, d, i)
        if range != .realtime { await loadHistory() }
    }

    /// 在不重建页面的情况下切换行情口径。新口径的数据准备完成前保留当前快照，
    /// 成功后在同一个 MainActor 周期内替换报价、实时走势和历史数据，避免新旧口径混用。
    @discardableResult
    func switchBasis(to newBasis: GoldMarketBasis, beforeCommit: @MainActor () -> Void = {}) async -> Bool {
        guard newBasis != basis else { return true }
        guard !isSwitchingBasis else { return false }

        let request = UUID()
        basisSwitchRequest = request
        isSwitchingBasis = true
        defer {
            if basisSwitchRequest == request {
                isSwitchingBasis = false
            }
        }

        let next = serviceFactory(newBasis)
        async let quoteFetch: GoldQuote = next.quote.fetchQuote()
        async let realtimeFetch: [MarketChartPoint] = next.realtime.fetchRealtime()
        async let dailyFetch: [GoldDailyPrice] = next.daily.fetchDailyPrices()
        async let historyFetch: [GoldHistoryPoint] = next.history.fetchHistory()

        do {
            let fetchedQuote = try await quoteFetch
            let fetchedRealtime = (try? await realtimeFetch) ?? []
            let fetchedDaily = (try? await dailyFetch) ?? []
            let fetchedHistory = (try? await historyFetch) ?? []
            guard basisSwitchRequest == request, !Task.isCancelled else { return false }

            guard fetchedQuote.cnyPerGram.isFinite, fetchedQuote.cnyPerGram > 0 else { return false }
            if range == .realtime {
                guard !Self.realtimeWindow(fetchedRealtime, now: .now).isEmpty else { return false }
            } else {
                if newBasis == .international {
                    guard fetchedQuote.usdCNY.isFinite, fetchedQuote.usdCNY > 0 else { return false }
                }
                let usableHistory = fetchedHistory.contains { $0.price.isFinite && $0.price > 0 }
                let usableDaily = fetchedDaily.contains { $0.close.isFinite && $0.close > 0 }
                guard range == .history ? usableHistory : (usableHistory || usableDaily) else { return false }
            }
            beforeCommit()
            cacheGeneration &+= 1
            preparedKey = nil; preparedPoints = []
            scopedKey = nil; scopedRange = nil; scopedPoints = []

            basis = newBasis
            dailyService = next.daily
            quoteService = next.quote
            realtimeService = next.realtime
            historyService = next.history
            quote = fetchedQuote
            realtime = fetchedRealtime
            daily = fetchedDaily
            history = fetchedHistory
            quoteFailed = false
            realtimeFailed = fetchedRealtime.isEmpty
            dailyFailed = fetchedDaily.isEmpty && fetchedHistory.isEmpty
            historyFailed = fetchedHistory.isEmpty && fetchedDaily.isEmpty
            quoteLoading = false
            realtimeLoading = false
            dailyLoading = false
            historyLoading = false
            selectedDate = nil
            gestureViewport = nil
            return true
        } catch {
            return false
        }
    }

    /// Unlock immediately even when a cancelled transport is still unwinding.
    /// The token prevents that transport from committing into a later switch.
    func cancelBasisSwitch() {
        basisSwitchRequest = nil
        isSwitchingBasis = false
    }

    /// A frozen display layer for the outgoing crossfade. It never starts tasks;
    /// arrays share storage until the live model changes them.
    func makeDisplaySnapshot() -> MarketHomeViewModel {
        let snapshot = MarketHomeViewModel(basis: basis, dailyService: dailyService,
            quoteService: quoteService, realtimeService: realtimeService,
            historyService: historyService, serviceFactory: serviceFactory)
        snapshot.range = range
        snapshot.priceScale = priceScale
        snapshot.quote = quote
        snapshot.daily = daily
        snapshot.history = history
        snapshot.realtime = realtime
        snapshot.viewport = xDomain
        snapshot.selectedDate = selectedDate
        snapshot.quoteLoading = quoteLoading
        snapshot.dailyLoading = dailyLoading
        snapshot.realtimeLoading = realtimeLoading
        snapshot.historyLoading = historyLoading
        snapshot.quoteFailed = quoteFailed
        snapshot.dailyFailed = dailyFailed
        snapshot.realtimeFailed = realtimeFailed
        snapshot.historyFailed = historyFailed
        snapshot.historyRevision = historyRevision
        snapshot.preparedKey = preparedKey; snapshot.preparedPoints = preparedPoints
        snapshot.scopedKey = scopedKey; snapshot.scopedRange = scopedRange; snapshot.scopedPoints = scopedPoints
        return snapshot
    }

    var fullDomain: ClosedRange<Date> {
        let values = points
        if range == .realtime {
            let end = values.last?.date ?? .now
            let start = values.first?.date ?? end.addingTimeInterval(-1200)
            return start...max(end, start.addingTimeInterval(1))
        }
        if range == .history, basis == .domestic, let first = values.first?.date, let last = values.last?.date {
            return first...last
        }
        // The selected range is the hard boundary, including navigator and date picker.
        // No completed YTD day exists on January 1. The UI shows an empty state;
        // its inert geometry stays inside this year, never in the previous year.
        let today = ChartViewport.noon(.now)
        return range.dateBounds() ?? today...today
    }
    var presetDomain: ClosedRange<Date> { fullDomain }
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
    var windowStatistics: ChartWindowStatistics { ChartWindowStatistics(points: windowPoints) }
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
        guard !Task.isCancelled else { return }
        let request = UUID()
        historyRequest = request
        historyLoading = true
        defer { if historyRequest == request { historyLoading = false } }
        let generation = cacheGeneration
        if let cached = await historyService.cachedHistory(), generation == cacheGeneration, historyRequest == request { history = cached }
        guard generation == cacheGeneration, historyRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await historyService.fetchHistory()
            guard generation == cacheGeneration, historyRequest == request, !Task.isCancelled else { return }
            history = fetched; historyFailed = false
        }
        catch { if generation == cacheGeneration, historyRequest == request, !Task.isCancelled { historyFailed = true } }
    }

    func clearMarketCache() {
        cancelBasisSwitch()
        historyRequest = nil; historyLoading = false
        cacheGeneration &+= 1
        preparedKey = nil; preparedPoints = []
        scopedKey = nil; scopedRange = nil; scopedPoints = []
        daily = []; history = []; realtime = []; quote = nil; selectedDate = nil
        resetViewport()
    }

    private func loadQuote() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        quoteRequest = request
        quoteLoading = true
        defer { if quoteRequest == request { quoteLoading = false } }
        let generation = cacheGeneration
        if quote == nil, let cached = await quoteService.cachedQuote(), generation == cacheGeneration, quoteRequest == request { quote = cached }
        guard generation == cacheGeneration, quoteRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await quoteService.fetchQuote()
            guard generation == cacheGeneration, quoteRequest == request, !Task.isCancelled else { return }
            quote = fetched; quoteFailed = false
        }
        catch { if generation == cacheGeneration, quoteRequest == request, !Task.isCancelled { quoteFailed = true } }
    }
    private func loadDaily() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        dailyRequest = request
        dailyLoading = true
        defer { if dailyRequest == request { dailyLoading = false } }
        let generation = cacheGeneration
        if let cached = await dailyService.cachedDailyPrices(), generation == cacheGeneration, dailyRequest == request { daily = cached }
        guard generation == cacheGeneration, dailyRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await dailyService.fetchDailyPrices()
            guard generation == cacheGeneration, dailyRequest == request, !Task.isCancelled else { return }
            daily = fetched; dailyFailed = false
        }
        catch { if generation == cacheGeneration, dailyRequest == request, !Task.isCancelled { dailyFailed = true } }
    }
    private func loadRealtime() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        realtimeRequest = request
        realtimeLoading = true
        defer { if realtimeRequest == request { realtimeLoading = false } }
        let generation = cacheGeneration
        guard generation == cacheGeneration, realtimeRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await realtimeService.fetchRealtime()
            guard generation == cacheGeneration, realtimeRequest == request, !Task.isCancelled else { return }
            // An empty/invalid refresh is not a replacement for a usable curve.
            guard !Self.realtimeWindow(fetched, now: .now).isEmpty else {
                realtimeFailed = true
                return
            }
            realtime = fetched; realtimeFailed = false
        }
        catch { if generation == cacheGeneration, realtimeRequest == request, !Task.isCancelled { realtimeFailed = true } }
    }
}
