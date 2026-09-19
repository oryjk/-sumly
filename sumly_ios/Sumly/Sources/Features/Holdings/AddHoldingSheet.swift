import SwiftUI
import SwiftData

// MARK: - 添加表单

struct AddHoldingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// 进入表单时的当前「元/克」价，用于预填购入单价。
    let defaultUnitPrice: Double?

    @State private var gramsText = ""
    @State private var priceText = ""
    @State private var timestamp = Date.now
    @State private var note = ""
    @State private var brand = ""
    @State private var feeText = ""
    @State private var channel = ""
    private let targetBook: String?
    @AppStorage("holdings.currentBook") private var book = "默认账本"
    @State private var errorMessage: String?
    @FocusState private var gramsFocused: Bool

    init(defaultUnitPrice: Double?, date: Date = .now, book: String? = nil) {
        targetBook = book
        _timestamp = State(initialValue: min(date, .now))
        self.defaultUnitPrice = defaultUnitPrice
        _priceText = State(
            initialValue: defaultUnitPrice.map { String(format: "%.2f", $0) } ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    fieldRow(label: "克数") {
                        TextField("例如 5.5", text: $gramsText)
                            .keyboardType(.decimalPad)
                            .focused($gramsFocused)
                    }
                    fieldRow(label: "购入单价（元/克）") {
                        TextField(defaultUnitPrice != nil ? "当前金价 \(String(format: "%.2f", defaultUnitPrice!))" : "例如 900.00", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    fieldRow(label: "持有时间") {
                        DatePicker(
                            "持有时间",
                            selection: $timestamp,
                            in: ...Date.now,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    }
                    fieldRow(label: "品牌（可选）") { TextField("例如 周生生、周大福", text: $brand) }
                    fieldRow(label: "额外费用（元，可选）") { TextField("0", text: $feeText).keyboardType(.decimalPad) }
                    fieldRow(label: "购买渠道（可选）") { TextField("例如 门店、银行", text: $channel) }
                    fieldRow(label: "备注（可选）") {
                        TextField("例如 金条、周大福", text: $note)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(GoldTheme.up)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(GoldTheme.background)
            .navigationTitle("添加黄金")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(GoldTheme.gold)
                }
            }
        }
        .presentationBackground(GoldTheme.background)
        .onAppear { gramsFocused = true }
        .task {
            guard defaultUnitPrice == nil, priceText.isEmpty,
                  let quote = try? await BackendGoldPriceService(instrumentID: "au9999").fetchQuote(), quote.cnyPerGram > 0,
                  priceText.isEmpty else { return }
            priceText = String(format: "%.2f", quote.cnyPerGram)
        }
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
            content()
                .font(.system(.body, design: .rounded))
                .foregroundStyle(GoldTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GoldTheme.card, in: GoldTheme.cardShape)
                .overlay(GoldTheme.cardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    private func save() {
        let grams = Double(gramsText.trimmingCharacters(in: .whitespaces))
        var price = Double(priceText.trimmingCharacters(in: .whitespaces))
        if price == nil, let fallback = defaultUnitPrice, fallback > 0 {
            price = fallback // 单价留空时按当前金价计
        }

        guard let grams, grams > 0, grams <= 1_000_000 else {
            errorMessage = "请输入有效的克数（大于 0）"
            return
        }
        guard let price, price > 0, price <= 1_000_000 else {
            errorMessage = "请输入有效的购入单价（元/克）"
            return
        }
        guard timestamp <= .now else {
            errorMessage = "持有时间不能晚于当前时间"
            return
        }

        let record = HoldingRecord(grams: grams, unitPriceCNY: price, timestamp: timestamp, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        record.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fee = Double(feeText.isEmpty ? "0" : feeText), fee.isFinite, fee >= 0 else {
            errorMessage = "请输入有效的额外费用"; return
        }
        record.extraFee = fee
        record.purchaseChannel = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        record.bookName = targetBook ?? book
        modelContext.insert(record)
        do { try modelContext.save() } catch {
            modelContext.rollback()
            errorMessage = "保存失败，请重试。"
            return
        }
        dismiss()
    }
}

// MARK: - 金额格式化

extension Double {
    /// 925.93
    var moneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)))
    }

    /// +24.98 / −12.30
    var signedMoneyText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(2)).sign(strategy: .always()))
    }
}
