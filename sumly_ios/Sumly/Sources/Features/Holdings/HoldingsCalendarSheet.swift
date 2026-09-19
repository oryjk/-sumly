import SwiftUI
import SwiftData

struct HoldingsCalendarSheet: View {
    let initialBook: String
    let hideAmounts: Bool
    @Query private var records: [HoldingRecord]
    @AppStorage("holdings.books") private var savedBooks = "默认账本"
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var period = HoldingCalendarPeriod.day
    @State private var filter = HoldingCalendarFilter()
    @State private var didInitialize = false
    @State private var showingFilter = false
    @State private var showingAdd = false
    @State private var model = HoldingsDesignPreview.makeModel()
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
            .navigationTitle("攒金日历").navigationBarTitleDisplayMode(.inline)
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
        .task { await model.start() }
        .sheet(isPresented: $showingFilter) { HoldingCalendarFilterSheet(filter: $filter, books: books) }
        .sheet(isPresented: $showingAdd) { AddHoldingSheet(defaultUnitPrice: model.quote?.cnyPerGram, date: date, book: filter.book ?? initialBook) }
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
                if stats.grams > 0 { marker("攒", stats.grams, color: GoldTheme.gold) }
                if stats.sold > 0 { marker("卖", stats.sold, color: GoldTheme.up) }
                if stats.gifted > 0 { marker("赠", stats.gifted, color: GoldTheme.textSecondary) }
                if stats.grams + stats.sold + stats.gifted == 0 { Text(HoldingCalendarLogic.lunar(day)).font(.system(size: 10)).foregroundStyle(GoldTheme.textFaint) }
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
            HStack { GoldTheme.gold.frame(width: 4, height: 18); Text("攒金统计").font(.headline); Text(title).font(.caption).foregroundStyle(GoldTheme.textSecondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 22) {
                metric("购入笔数", "\(stats.count)")
                metric("总重量(克)", stats.grams.moneyText)
                metric("额外费用(元)", stats.fees.moneyText)
                metric("预估收益率(%)", stats.profitPercent?.moneyText ?? "—", color: (stats.profitPercent ?? 0) >= 0 ? GoldTheme.up : GoldTheme.down)
                metric("平均克价(元)", stats.average.moneyText)
                metric("购入总价(元)", stats.cost.moneyText)
                metric("卖出(克)", stats.sold.moneyText)
                metric("赠出(克)", stats.gifted.moneyText)
            }.padding(.vertical, 20).padding(.horizontal, 8).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            Text("购入总价包含额外费用；预估收益率按当前国内金价估算购入黄金，不代表已实现收益。").font(.caption).foregroundStyle(GoldTheme.textFaint)
        }
    }
    private func metric(_ label: String, _ value: String, color: Color = GoldTheme.text) -> some View {
        VStack(spacing: 7) { Text(label).font(.system(size: 11)).foregroundStyle(GoldTheme.textSecondary); Text(hideAmounts ? "••••" : value).font(.system(size: 18, weight: .medium)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6) }
    }
    private func eventRow(_ event: HoldingCalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(event.title); Spacer(); Text(event.kind == "buy" ? "购入" : event.kind == "sold" ? "卖出" : "赠出").foregroundStyle(event.kind == "sold" ? GoldTheme.up : GoldTheme.gold) }
            HStack {
                Text(hideAmounts ? "••••" : "\(event.grams.moneyText) 克 · \((event.kind == "buy" ? event.cost : event.proceeds).moneyText) 元")
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
