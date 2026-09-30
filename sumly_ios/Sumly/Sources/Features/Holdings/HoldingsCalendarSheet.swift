import SwiftUI
import SwiftData

struct HoldingsCalendarSheet: View {
    let initialBook: String
    let hideAmounts: Bool
    let marketBasis: GoldMarketBasis
    @Query private var records: [HoldingRecord]
    @AppStorage("holdings.books") private var savedBooks = "默认账本"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var date = Date.now
    @State private var period = HoldingCalendarPeriod.day
    @State private var filter = HoldingCalendarFilter()
    @State private var didInitialize = false
    @State private var showingFilter = false
    @State private var showingAdd = false
    @State private var sectionExpansion: [CalendarStatisticsKind: Bool] = [:]
    @State private var model: HoldingsViewModel
    init(initialBook: String, hideAmounts: Bool, marketBasis: GoldMarketBasis = .domestic) {
        self.initialBook = initialBook
        self.hideAmounts = hideAmounts
        self.marketBasis = marketBasis
        _model = State(initialValue: HoldingsDesignPreview.makeModel(basis: marketBasis))
    }

    private var events: [HoldingCalendarEvent] { HoldingCalendarLogic.events(records, filter: filter) }
    private var selected: [HoldingCalendarEvent] { HoldingCalendarLogic.select(events, period: period, date: date) }
    private var books: [String] { Array(Set(records.map(\.bookName) + savedBooks.components(separatedBy: "\n") + [initialBook])).filter { !$0.isEmpty }.sorted() }
    private var title: String {
        switch period {
        case .day: HoldingsSelection.dateText(date)
        case .month: date.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN")))
        case .year: "\(Calendar.current.component(.year, from: date))年"
        case .all: "全部记录"
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    controls
                    if period != .all { periodNavigation }
                    if period == .day { calendarGrid }
                    if period == .month { monthGrid }
                    summary
                    if selected.isEmpty {
                        ContentUnavailableView("暂无记录", systemImage: "calendar", description: Text("可以切换日期、调整筛选或添加黄金。"))
                    } else {
                        Text("记录明细").font(.headline)
                        ForEach(selected) { event in eventRow(event) }
                    }
                }.padding(16)
            }
            .background(GoldTheme.background)
            .navigationTitle("记金日历").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { showingAdd = true } label: { Label("添加黄金", systemImage: "plus").frame(minHeight: 24) }
                    .buttonStyle(GoldPrimaryButtonStyle()).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(GoldTheme.background)
            }
        }
        .tint(GoldTheme.gold).foregroundStyle(GoldTheme.text)
        .presentationBackground(GoldTheme.background)
        .onAppear { if !didInitialize { filter.book = initialBook; didInitialize = true } }
        .task(id: scenePhase) { if scenePhase == .active { await model.start() } }
        .onChange(of: date) { sectionExpansion = [:] }
        .onChange(of: period) { sectionExpansion = [:] }
        .onChange(of: filter) { sectionExpansion = [:] }
        .sheet(isPresented: $showingFilter) { HoldingCalendarFilterSheet(filter: $filter, books: books) }
        .sheet(isPresented: $showingAdd) { AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram, date: date, book: filter.book ?? initialBook, marketBasis: marketBasis) }
    }
    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(HoldingCalendarPeriod.allCases, id: \.self) { item in
                    Button { period = item } label: {
                        Text(item.rawValue).font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 42)
                            .foregroundStyle(period == item ? GoldTheme.onGold : GoldTheme.text)
                            .background(period == item ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
                    }.buttonStyle(.plain)
                }
            }.background(GoldTheme.card, in: GoldTheme.capsuleShape)
            Button { showingFilter = true } label: {
                HStack(spacing: 4) { Text("筛选"); Image(systemName: "chevron.down").font(.caption) }
                    .font(.subheadline.bold()).padding(.horizontal, 13).frame(height: 42)
                    .foregroundStyle(filter.keyword.isEmpty && filter.kind == "all" ? GoldTheme.text : GoldTheme.gold)
                    .background(GoldTheme.card, in: GoldTheme.capsuleShape)
            }
        }
    }
    private var periodNavigation: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("上一期间")
            Spacer()
            Text(period == .day ? date.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN"))) : title).font(.title3.bold())
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("下一期间")
        }.foregroundStyle(GoldTheme.text)
    }
    private func shift(_ amount: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component = period == .day ? .month : .year
        let base = calendar.dateInterval(of: component, for: date)?.start ?? date
        date = calendar.date(byAdding: component, value: amount, to: base) ?? date
    }
    private var calendarGrid: some View {
        VStack(spacing: 6) {
            HStack { ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { Text("周" + $0).font(.caption).foregroundStyle(GoldTheme.textFaint).frame(maxWidth: .infinity) } }.padding(.bottom, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 5) {
                ForEach(HoldingCalendarLogic.days(in: date), id: \.self) { day in dayCell(day) }
            }
        }.padding(12).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
    }
    private func dayCell(_ day: Date) -> some View {
        let sameMonth = Calendar.current.isDate(day, equalTo: date, toGranularity: .month)
        let isSelected = Calendar.current.isDate(day, inSameDayAs: date)
        let stats = HoldingCalendarLogic.stats(HoldingCalendarLogic.select(events, period: .day, date: day), quote: nil)
        return Button { date = day } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? GoldTheme.gold : sameMonth ? GoldTheme.text : GoldTheme.textFaint)
                if stats.purchases.grams > 0 { marker("记", stats.purchases.grams, color: GoldTheme.gold) }
                if stats.sales.grams > 0 { marker("卖", stats.sales.grams, color: GoldTheme.up) }
                if stats.gifts.grams > 0 { marker("赠", stats.gifts.grams, color: GoldTheme.textSecondary) }
                if stats.purchases.grams + stats.sales.grams + stats.gifts.grams == 0 { Text(HoldingCalendarLogic.lunar(day)).font(.system(size: 10)).foregroundStyle(GoldTheme.textFaint) }
                Spacer(minLength: 0)
            }.padding(.top, 7).frame(maxWidth: .infinity).frame(height: 68)
                .background(GoldTheme.calendarCell, in: GoldTheme.rangeShape)
                .overlay { if isSelected { GoldTheme.rangeShape.strokeBorder(GoldTheme.gold, lineWidth: 1) } }
        }.buttonStyle(.plain).accessibilityLabel(HoldingsSelection.dateText(day))
    }
    private func marker(_ text: String, _ grams: Double, color: Color) -> some View {
        Text(hideAmounts ? text + "••" : text + grams.formatted(.number.precision(.fractionLength(0...2))))
            .font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(color)
    }
    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(1...12, id: \.self) { month in
                Button {
                    var components = Calendar.current.dateComponents([.year], from: date); components.month = month; components.day = 1; components.hour = 12
                    date = Calendar.current.date(from: components) ?? date
                } label: {
                    Text("\(month)月").frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(Calendar.current.component(.month, from: date) == month ? GoldTheme.onGold : GoldTheme.text)
                        .background(Calendar.current.component(.month, from: date) == month ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.rangeShape)
                }
            }
        }
    }
    private var summary: some View {
        let stats = HoldingCalendarLogic.stats(selected, quote: model.quote?.cnyPerGram)
        return VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            valuationBasis
            statisticsCard(.purchases, stats: stats.purchases)
            statisticsCard(.sales, stats: stats.sales)
            statisticsCard(.gifts, stats: stats.gifts)
        }
    }
    private var noRecordsText: String {
        switch period {
        case .day: "当天无记录"
        case .month: "当月无记录"
        case .year: "当年无记录"
        case .all: "暂无记录"
        }
    }
    private var valuationBasis: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let quote = model.quote, quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 {
                Text(hideAmounts ? "估值基准 · \(marketBasis.title) · •••• 元/克" : "估值基准 · \(marketBasis.title) · \(quote.cnyPerGram.moneyText) 元/克")
                Text("最新可用报价 · " + quote.asOf.formatted(date: .abbreviated, time: .standard))
                    .foregroundStyle(GoldTheme.textFaint)
            } else {
                Text("\(marketBasis.title)报价暂不可用，预估金额与收益率显示为 —")
            }
        }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
    }
    private func statisticsCard(_ kind: CalendarStatisticsKind, stats: HoldingCalendarCategorySummary) -> some View {
        let expanded = sectionExpansion[kind] ?? (stats.count > 0)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { sectionExpansion[kind] = !expanded }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: kind.icon).font(.headline).foregroundStyle(GoldTheme.gold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.title).font(.headline).foregroundStyle(GoldTheme.text)
                        Text(stats.count == 0 ? noRecordsText : hideAmounts ? "•• 笔记录" : "\(stats.count) 笔 · \(stats.grams.moneyText) 克")
                            .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold()).foregroundStyle(GoldTheme.textSecondary)
                }.frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(GoldTheme.holdingsCardShape)
            }.buttonStyle(.plain)
                .accessibilityLabel(kind.title + (stats.count == 0 ? "，" + noRecordsText : ""))
                .accessibilityValue(expanded ? "已展开" : "已收起")
                .accessibilityHint("轻点以" + (expanded ? "收起" : "展开") + "统计")
            if expanded {
                if stats.count == 0 {
                    Text("当前所选范围没有" + kind.recordName + "记录，可切换日期或调整筛选。")
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary).padding(.top, 14)
                } else {
                    statisticsDetails(kind, stats: stats).padding(.top, 18)
                }
            }
        }.padding(16).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }
    @ViewBuilder private func statisticsDetails(_ kind: CalendarStatisticsKind, stats: HoldingCalendarCategorySummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                if kind == .sales {
                    metric("实收金额(元)", stats.proceeds.moneyText, prominent: true)
                    metric("已实现收益(元)", stats.profit?.signedMoneyText ?? "—", color: profitColor(stats.profit), prominent: true)
                } else {
                    metric(kind == .purchases ? "预估价值(元)" : "当前价值(元)", stats.value?.moneyText ?? "—", prominent: true)
                    metric(kind == .purchases ? "预估收益(元)" : "购入成本(元)", kind == .purchases ? stats.profit?.signedMoneyText ?? "—" : stats.cost.moneyText,
                           color: kind == .purchases ? profitColor(stats.profit) : GoldTheme.text, prominent: true)
                }
            }
            if kind != .gifts {
                HStack(spacing: 8) {
                    Text(kind == .sales ? "已实现收益率" : "预估收益率").foregroundStyle(GoldTheme.textSecondary)
                    Text(hideAmounts ? "••••" : stats.profitPercent.map { $0.signedMoneyText + "%" } ?? "—")
                        .fontWeight(.semibold).monospacedDigit().foregroundStyle(profitColor(stats.profitPercent))
                }.font(.subheadline)
            }
            GoldTheme.cardStroke.frame(height: 1)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), alignment: .leading)], alignment: .leading, spacing: 16) {
                metric(kind.recordName + "笔数", "\(stats.count)")
                metric("总重量(克)", stats.grams.moneyText)
                metric("额外费用(元)", stats.fees.moneyText)
                metric("买入均价(元/克)", stats.average.moneyText)
                if kind == .sales { metric("卖出均价(元/克)", stats.saleAverage.moneyText) }
                if kind != .gifts { metric("购入总价(元)", stats.cost.moneyText) }
            }
            Text(kind.explanation).font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }
    }
    private func profitColor(_ value: Double?) -> Color {
        guard let value else { return GoldTheme.textSecondary }
        return value > 0 ? GoldTheme.up : value < 0 ? GoldTheme.down : GoldTheme.text
    }
    private func metric(_ label: String, _ value: String, color: Color = GoldTheme.text, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Text(hideAmounts ? "••••" : value).font(prominent ? .title3.weight(.semibold) : .body.weight(.medium))
                .monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func eventRow(_ event: HoldingCalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(event.title); Spacer(); Text(event.kind == "buy" ? "购入" : event.kind == "sold" ? "卖出" : "赠出").foregroundStyle(event.kind == "sold" ? GoldTheme.up : GoldTheme.gold) }
            HStack {
                Text(hideAmounts ? "••••" : "\(event.grams.moneyText) 克 · \(event.kind == "sold" ? "实收" : "购入成本") \((event.kind == "sold" ? event.proceeds : event.cost).moneyText) 元")
                Spacer(); Text(HoldingsSelection.dateText(event.date))
            }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }.padding(16).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
    }
}

struct HoldingCalendarFilterSheet: View {
    @Binding var filter: HoldingCalendarFilter
    let books: [String]
    @State private var draft = HoldingCalendarFilter()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("关键词").foregroundStyle(GoldTheme.textSecondary)
                    TextField("购买渠道／买家／受赠人／品牌", text: $draft.keyword).padding(16).background(GoldTheme.background, in: GoldTheme.rangeShape)
                    Text("类型").foregroundStyle(GoldTheme.textSecondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        option("全部", selected: draft.kind == "all") { draft.kind = "all" }
                        option("在库", selected: draft.kind == "holding") { draft.kind = "holding" }
                        option("卖出", selected: draft.kind == "sold") { draft.kind = "sold" }
                        option("赠出", selected: draft.kind == "gift") { draft.kind = "gift" }
                    }
                    Text("账本").foregroundStyle(GoldTheme.textSecondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                        option("全部账本", selected: draft.book == nil) { draft.book = nil }
                        ForEach(books, id: \.self) { book in option(book, selected: draft.book == book) { draft.book = book } }
                    }
                }.padding(24)
            }.background(GoldTheme.card)
                .navigationTitle("选择筛选项").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) } }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 16) {
                        Button("取消") { dismiss() }.frame(maxWidth: .infinity).padding(.vertical, 16).background(GoldTheme.background, in: GoldTheme.capsuleShape)
                        Button("确定") { filter = draft; dismiss() }.buttonStyle(GoldPrimaryButtonStyle())
                    }.padding(20).background(GoldTheme.card)
                }
        }.foregroundStyle(GoldTheme.text).tint(GoldTheme.gold).presentationDetents([.large]).onAppear { draft = filter }
    }
    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 18)
                .foregroundStyle(selected ? GoldTheme.gold : GoldTheme.text)
                .background(GoldTheme.background, in: GoldTheme.rangeShape)
                .overlay { if selected { GoldTheme.rangeShape.strokeBorder(GoldTheme.gold, lineWidth: 1) } }
        }
    }
}

private enum CalendarStatisticsKind: Hashable {
    case purchases, sales, gifts
    var title: String { switch self { case .purchases: "记金统计"; case .sales: "卖出统计"; case .gifts: "赠送统计" } }
    var recordName: String { switch self { case .purchases: "购入"; case .sales: "卖出"; case .gifts: "赠送" } }
    var icon: String { switch self { case .purchases: "tray.and.arrow.down"; case .sales: "banknote"; case .gifts: "gift" } }
    var explanation: String {
        switch self {
        case .purchases: "按所选期间购入黄金和最新可用金价估算，包含已赠卖部分；购入总价包含额外费用，预估收益不代表已实现收益。"
        case .sales: "按所选期间卖出日期统计。已实现收益 = 实收金额 − 购入成本，购入成本包含分摊的额外费用。"
        case .gifts: "按所选期间赠送日期统计。购入成本包含额外费用；当前价值按最新可用金价估算，不计作投资收益。"
        }
    }
}
