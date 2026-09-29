import SwiftUI
import Charts

/// 参考稿高保真布局，行情统一由 Go 服务提供。
struct HomeView: View {
    @State private var model = MarketHomeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNotice = false
    @State private var showingHistorySources = false

    var body: some View {
        Group {
            if model.showsInitialLoading {
                MarketLoadingView()
            } else {
                dashboard
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.start() }
        }
        .task(id: model.range) {
            if model.range == .history { await model.loadHistory() }
        }
        .sheet(isPresented: $showingHistorySources) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("1900–2015 · 年度均价参考").font(.headline)
                        Text("来源为 USGS Data Series 140 的名义美元金价统计，按每吨换算为每金衡盎司。1900–1967 年依据世界市场均价，1968 年起依据 Engelhard 年均报价；不是同一市场的逐日收盘序列。年度点仅用当年 7 月定位。")
                        Link("查看 USGS 原始资料", destination: URL(string: "https://www.usgs.gov/media/files/gold-historical-statistics-data-series-140")!)
                        Text("2016 年起 · 每日收盘价").font(.headline)
                        Text("来源为新浪伦敦金日线，仅展示来源已有的交易日。当天未收盘时标为实时报价。周末、休市及缺失数据不补点。")
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
            let w = geometry.size.width
            let h = geometry.size.height
            let scale = w / 430
            ZStack(alignment: .topLeading) {
                GoldTheme.background
                Text("黄金价格")
                    .font(.system(size: 22 * scale, weight: .regular))
                    .foregroundStyle(GoldTheme.gold)
                    .position(x: w / 2, y: h * 0.147)

                HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                    Text(model.price.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? "—")
                        .font(.system(size: 46 * scale, weight: .bold))
                    Text("¥")
                        .font(.system(size: 22 * scale, weight: .bold))
                }
                .foregroundStyle(GoldTheme.gold)
                .position(x: w * 0.518, y: h * 0.198)
                .accessibilityLabel("黄金价格，\(model.price.map { String(format: "%.2f", $0) } ?? "暂无报价") 元每克")

                Button { showingNotice = true } label: {
                    HStack(spacing: 3 * scale) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 15 * scale))
                        Text("订阅金价")
                            .font(.system(size: 16 * scale, weight: .bold))
                    }
                    .foregroundStyle(GoldTheme.card)
                    .frame(width: 109 * scale, height: 31 * scale)
                    .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                }
                .buttonStyle(.plain)
                .position(x: w / 2, y: h * 0.256)

                HStack(spacing: 8 * scale) {
                    ForEach(MarketRange.allCases, id: \.self) { range in
                        Button {
                            model.range = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 13 * scale))
                                .foregroundStyle(model.range == range ? GoldTheme.card : GoldTheme.serviceText)
                                .frame(width: (range == .history ? 104 : 63) * scale, height: 30 * scale)
                                .background(model.range == range ? GoldTheme.gold : GoldTheme.card,
                                            in: GoldTheme.rangeShape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.range == range ? .isSelected : [])
                    }
                }
                .position(x: w / 2, y: h * 0.416)

                VStack(spacing: 4 * scale) {
                    Text(model.range == .realtime ? "元/克 · 近20分钟走势" : "元/克 · 国际金价按最新汇率折算")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(GoldTheme.textSecondary)
                    if let message = model.message {
                        Button(message) { Task { await model.refresh() } }
                            .font(.system(size: 10 * scale))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                }
                .position(x: w / 2, y: h * 0.307)

                HStack(spacing: 12) {
                    Text("双指缩放 / 移动 · 单指查价")
                    if model.viewport != nil { Button("复位") { model.resetViewport() } }
                    if model.range == .history { Button("数据说明") { showingHistorySources = true } }
                }
                .font(.system(size: 10 * scale))
                .foregroundStyle(GoldTheme.textSecondary)
                .position(x: w / 2, y: h * 0.458)

                trendChart
                    .frame(width: w * 0.944, height: h * 0.304)
                    .position(x: w / 2, y: h * (0.474 + 0.152))
                    .accessibilityLabel("\(model.range.rawValue)黄金价格走势图，\(model.points.count)个行情点")
            }
        }
        .ignoresSafeArea()
    }

    private var trendChart: some View {
        let data = model.visiblePoints
        let domain = MarketHomeViewModel.chartDomain(data)
        let baseline = domain.lowerBound
        return ZStack {
            Chart {
                ForEach(data, id: \.date) { point in
                    AreaMark(x: .value("时间", point.date),
                             yStart: .value("基线", baseline),
                             yEnd: .value("元/克", point.price))
                        .foregroundStyle(LinearGradient(
                            colors: [GoldTheme.chartFill, GoldTheme.gold.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("时间", point.date), y: .value("元/克", point.price))
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    if data.count == 1 {
                        PointMark(x: .value("时间", point.date), y: .value("元/克", point.price))
                            .foregroundStyle(GoldTheme.gold)
                    }
                }
                if let point = model.selectedPoint {
                    RuleMark(x: .value("时间", point.date))
                        .foregroundStyle(GoldTheme.gold.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 0.6))
                    PointMark(x: .value("时间", point.date), y: .value("元/克", point.price))
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(32)
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: model.xDomain)
            .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 0))
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : (value.index == 3 ? .topTrailing : .top)) {
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
    private var axisDates: [Date] {
        let domain = model.xDomain
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        return (0...3).map { domain.lowerBound.addingTimeInterval(span * Double($0) / 3) }
    }
    private func axisLabel(_ date: Date) -> String {
        let span = model.xDomain.upperBound.timeIntervalSince(model.xDomain.lowerBound)
        if span > 730 * 86400 { return date.formatted(.dateTime.year()) }
        if span > 86400 { return date.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)) }
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
