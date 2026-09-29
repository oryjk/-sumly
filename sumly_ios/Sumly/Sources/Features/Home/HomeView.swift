import SwiftUI
import Charts

/// 参考稿高保真布局，行情统一由 Go 服务提供。
struct HomeView: View {
    @State private var model = MarketHomeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNotice = false
    @State private var showingHistorySources = false
    @State private var showingDates = false

    var body: some View {
        Group {
            if model.showsInitialLoading {
                MarketLoadingView()
            } else {
                dashboard
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketCacheCleared)) { _ in model.clearMarketCache() }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.start() }
        }
        .task(id: model.range) {
            if model.range != .realtime { await model.loadHistory() }
        }
        .sheet(isPresented: $showingDates) {
            ChartDateRangeSheet(bounds: model.fullDomain, window: model.xDomain, apply: model.setDateWindow)
        }
        .sheet(isPresented: $showingHistorySources) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("1900–2015 · 年度均价参考").font(.headline)
                        Text("来源为 USGS Data Series 140 的名义美元金价统计，按每吨换算为每金衡盎司。1900–1967 年依据世界市场均价，1968 年起依据 Engelhard 年均报价；不是同一市场的逐日收盘序列。年度点仅用当年 7 月定位。")
                        Link("查看 USGS 原始资料", destination: URL(string: "https://www.usgs.gov/media/files/gold-historical-statistics-data-series-140")!)
                        Text("2016 年起 · 每日收盘价").font(.headline)
                        Text("来源为新浪伦敦金日线，仅展示截至昨天已有的交易日收盘数据。当天报价仅在实时走势中显示。周末、休市及缺失数据不补点。")
                        Text("图中元/克按最新美元兑人民币汇率折算，不代表当年的人民币价格，也未作通胀调整。")
                    }.padding(24)
                }.background(GoldTheme.background).foregroundStyle(GoldTheme.text)
                    .navigationTitle("历史数据说明")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingHistorySources = false } } }
            }.preferredColorScheme(.dark).tint(GoldTheme.gold)
        }
        .alert("订阅金价", isPresented: $showingNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("订阅提醒暂未开放，敬请期待。")
        }
    }

    private var dashboard: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("黄金价格").font(.headline).foregroundStyle(GoldTheme.goldSoft)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(model.price.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? "—")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                            Text("元/克").font(.subheadline)
                        }.foregroundStyle(GoldTheme.gold)
                            .accessibilityLabel("黄金价格，\(model.price.map { String(format: "%.2f", $0) } ?? "暂无报价") 元每克")
                        Button { showingNotice = true } label: {
                            Label("订阅金价", systemImage: "bell.badge").font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16).frame(minHeight: 36)
                                .foregroundStyle(GoldTheme.onGold).background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                        }.buttonStyle(.plain)
                        if let message = model.message {
                            Button(message) { Task { await model.refresh() } }
                                .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        }
                    }.padding(.top, 10)

                    VStack(spacing: 14) {
                        HStack(spacing: 6) {
                            ForEach(MarketRange.allCases, id: \.self) { range in
                                Button { model.range = range } label: {
                                    Text(range.rawValue).font(.system(size: 13, weight: .medium))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(model.range == range ? GoldTheme.onGold : GoldTheme.textSecondary)
                                        .background(model.range == range ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.rangeShape)
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(model.range == range ? .isSelected : [])
                            }
                        }
                        HStack(spacing: 12) {
                            HStack(spacing: 2) {
                                ForEach(ChartPriceScale.allCases, id: \.self) { scale in
                                    Button { model.priceScale = scale } label: {
                                        Text(scale.rawValue).font(.subheadline.weight(.semibold))
                                            .frame(width: 66, height: 44)
                                            .foregroundStyle(model.priceScale == scale ? GoldTheme.onGold : GoldTheme.textSecondary)
                                            .background(model.priceScale == scale ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.rangeShape)
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel(scale.rawValue + "价格刻度")
                                        .accessibilityAddTraits(model.priceScale == scale ? .isSelected : [])
                                        .accessibilityIdentifier(scale == .linear ? "chart.scale.linear" : "chart.scale.log")
                                }
                            }.padding(3).background(GoldTheme.card, in: GoldTheme.rangeShape)
                            Spacer(minLength: 0)
                            Button { model.resetViewport() } label: {
                                Label("复位", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline.weight(.semibold)).frame(minWidth: 82, minHeight: 44)
                                    .foregroundStyle(model.canReset ? GoldTheme.gold : GoldTheme.textFaint)
                                    .background(GoldTheme.card, in: GoldTheme.rangeShape)
                                    .overlay(GoldTheme.rangeShape.strokeBorder(model.canReset ? GoldTheme.gold : GoldTheme.cardStroke))
                            }.buttonStyle(.plain).disabled(!model.canReset).accessibilityIdentifier("chart.reset")
                        }
                        HStack {
                            Text(model.range == .realtime ? "元/克 · 最近 20 分钟" : "截至昨天 · 元/克 · 按最新汇率折算")
                            Spacer(minLength: 0)
                            Button { showingHistorySources = true } label: {
                                Image(systemName: "info.circle").foregroundStyle(GoldTheme.goldSoft)
                            }.accessibilityLabel("历史数据说明")
                        }.font(.system(size: 11)).foregroundStyle(GoldTheme.textSecondary)

                        trendChart
                            .frame(height: max(200, min(280, geometry.size.height * 0.30)))
                            .accessibilityLabel("\(model.range.rawValue)黄金价格走势图，当前区间\(model.windowPoints.count)个行情点")

                        VStack(spacing: 10) {
                            HStack(alignment: .center) {
                                if model.range == .realtime {
                                    Text(windowLabel).font(.caption.monospacedDigit()).foregroundStyle(GoldTheme.text)
                                } else {
                                    Button { showingDates = true } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "calendar")
                                            Text(windowLabel).monospacedDigit()
                                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(GoldTheme.goldSoft)
                                            .frame(minHeight: 44)
                                    }.accessibilityIdentifier("chart.dates")
                                }
                                Spacer(minLength: 2)
                                Text("\(model.windowPoints.count) 个点").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                            }
                            ChartRangeNavigator(points: model.points, bounds: model.fullDomain, window: model.xDomain,
                                                scale: model.priceScale, daily: model.range != .realtime,
                                                begin: model.beginNavigatorGesture, move: model.moveNavigator, end: model.endChartGesture)
                                .disabled(model.points.isEmpty)
                            HStack {
                                Text(overviewLabel(model.fullDomain.lowerBound))
                                Spacer()
                                Text(overviewLabel(model.fullDomain.upperBound))
                            }.font(.system(size: 10)).foregroundStyle(GoldTheme.textFaint)
                            Text("拖动选框浏览 · 拖动两端缩放 · 主图单指查价")
                                .font(.system(size: 11)).foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 110)
            }.scrollIndicators(.hidden).background(GoldTheme.background)
        }
    }
    private var windowLabel: String {
        let window = model.xDomain
        if model.range == .realtime {
            return window.lowerBound.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)) + " — " + window.upperBound.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        }
        return window.lowerBound.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " — " + window.upperBound.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    private var trendChart: some View {
        let data = model.visiblePoints
        let domain = model.priceScale.domain(data.map(\.price))
        let baseline = domain.lowerBound
        return ZStack {
            Chart {
                ForEach(data, id: \.date) { point in
                    AreaMark(x: .value("时间", point.date),
                             yStart: .value("基线", baseline),
                             yEnd: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(LinearGradient(
                            colors: [GoldTheme.chartFill, GoldTheme.gold.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    if data.count == 1 {
                        PointMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                            .foregroundStyle(GoldTheme.gold)
                    }
                }
                if let point = model.selectedPoint {
                    RuleMark(x: .value("时间", point.date))
                        .foregroundStyle(GoldTheme.gold.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 0.6))
                    PointMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(32)
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: model.xDomain)
            .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 0))
            .chartXAxis {
                AxisMarks(values: model.axisDates) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : (value.index == model.axisDates.count - 1 ? .topTrailing : .top)) {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date)).font(.system(size: 10)).foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in plot.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        ChartGestureSurface(begin: model.beginChartGesture,
                                            transform: model.transformChart,
                                            end: model.endChartGesture,
                                            select: model.selectChart,
                                            reset: model.resetViewport)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityLabel("走势图时间轴")
                            .accessibilityValue("\(axisLabel(model.xDomain.lowerBound))至\(axisLabel(model.xDomain.upperBound))")
                            .accessibilityAction(named: "放大") { model.accessibleZoom(2) }
                            .accessibilityAction(named: "缩小") { model.accessibleZoom(0.5) }
                            .accessibilityAction(named: "复位") { model.resetViewport() }
                    }
                    if let point = model.selectedPoint, let x = proxy.position(forX: point.date) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("¥ " + point.price.formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 14, weight: .semibold))
                            Text(pointLabel(point))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(GoldTheme.gold)
                        .padding(10)
                        .frame(width: 162, alignment: .leading)
                        .background(GoldTheme.card, in: GoldTheme.rangeShape)
                        .position(x: min(max(x + (proxy.plotFrame.map { geometry[$0].minX } ?? 0) + 82, 81), max(81, geometry.size.width - 81)), y: 32)
                        .allowsHitTesting(false)
                    }
                }
            }
            if data.isEmpty {
                Text(model.loading || model.historyLoading ? "正在加载走势…" : (model.range == .realtime ? "暂无最新走势" : "暂无走势数据"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
        }
    }
    private func overviewLabel(_ date: Date) -> String {
        if model.range != .realtime { return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) }
        return axisLabel(date)
    }
    private func axisLabel(_ date: Date) -> String {
        let span = model.xDomain.upperBound.timeIntervalSince(model.xDomain.lowerBound)
        if span > 730 * 86400 { return date.formatted(.dateTime.year()) }
        if model.range != .realtime { return date.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)) }
        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
    private func pointLabel(_ point: MarketChartPoint) -> String {
        switch point.granularity {
        case .annual: return point.date.formatted(.dateTime.year()) + " · 年均价参考"
        case .daily: return point.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " · 收盘"
        case .realtime: return point.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        }
    }

}
