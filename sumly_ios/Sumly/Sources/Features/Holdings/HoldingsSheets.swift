import SwiftUI
import SwiftData

struct HoldingsCalendarSheet: View {
    let records: [HoldingRecord]
    let hideAmounts: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now
    private var daily: [HoldingRecord] { records.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: day) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DatePicker("选择日期", selection: $day, in: ...Date.now, displayedComponents: .date).datePickerStyle(.graphical).environment(\.locale, Locale(identifier: "zh_CN"))
                    HStack {
                        Text(HoldingsSelection.dateText(day)).foregroundStyle(GoldTheme.textSecondary)
                        Spacer()
                        Text(hideAmounts ? "••••" : "攒入 \(daily.reduce(0) { $0 + $1.grams }.moneyText) 克").foregroundStyle(GoldTheme.gold)
                    }.font(.subheadline)
                    if daily.isEmpty { Text("这一天没有购入记录").foregroundStyle(GoldTheme.textSecondary).padding(.vertical, 25).frame(maxWidth: .infinity) }
                    ForEach(daily) { record in HoldingRowView(record: record, profit: nil, hideAmounts: hideAmounts) }
                }.padding(16)
            }.background(GoldTheme.background).navigationTitle("攒金日历").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationBackground(GoldTheme.background)
    }
}

struct HoldingsHistorySheet: View {
    let records: [HoldingRecord]
    let hideAmounts: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if records.isEmpty { ContentUnavailableView("暂无赠卖记录", systemImage: "gift", description: Text("在持仓卡片上左滑，可记录赠送或卖出。")) }
                    ForEach(records.sorted { ($0.disposedAt ?? .distantPast) > ($1.disposedAt ?? .distantPast) }) { record in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(record.brand.isEmpty ? "未知" : record.brand); Spacer(); Text(record.disposition == "sold" ? "卖出" : "赠送").foregroundStyle(GoldTheme.gold) }
                            HStack {
                                Text(hideAmounts ? "••••" : "\(record.grams.moneyText)克" + (record.disposition == "sold" ? " · 实收 \(record.disposalAmount.moneyText)元" : ""))
                                Spacer()
                                if let date = record.disposedAt { Text(HoldingsSelection.dateText(date)) }
                            }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        }.padding(16).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
                    }
                }.padding(16)
            }.background(GoldTheme.background).navigationTitle("赠卖记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationBackground(GoldTheme.background)
    }
}

struct DisposeHoldingSheet: View {
    let record: HoldingRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var kind = "sold"
    @State private var grams = ""
    @State private var amount = ""
    @State private var date = Date.now
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("操作", selection: $kind) { Text("卖出").tag("sold"); Text("赠送").tag("gift") }.pickerStyle(.segmented)
                    LabeledContent("当前持仓", value: "\(record.grams.moneyText) 克")
                    TextField("本次克数", text: $grams).keyboardType(.decimalPad)
                    if kind == "sold" { TextField("实际收到的总金额（元）", text: $amount).keyboardType(.decimalPad) }
                    DatePicker("日期", selection: $date, in: record.timestamp...Date.now, displayedComponents: [.date, .hourAndMinute])
                } footer: { Text("可以操作部分克数，剩余黄金继续保留在本账本。") }
                if let error { Text(error).foregroundStyle(GoldTheme.up) }
            }.navigationTitle("赠卖黄金").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
                }
        }.onAppear { grams = String(record.grams) }
    }
    private func save() {
        guard let quantity = Double(grams), quantity.isFinite, quantity > 0, quantity <= record.grams else { error = "请输入有效克数，且不能超过当前持仓。"; return }
        let proceeds = kind == "gift" ? 0 : Double(amount)
        guard let proceeds, proceeds.isFinite, proceeds >= 0 else { error = "请输入有效的实收金额。"; return }
        do {
            try HoldingDisposal.apply(record: record, grams: quantity, proceeds: proceeds, kind: kind, date: date, context: context)
            dismiss()
        } catch { context.rollback(); self.error = "未能保存，请检查填写内容后重试。" }
    }
}

