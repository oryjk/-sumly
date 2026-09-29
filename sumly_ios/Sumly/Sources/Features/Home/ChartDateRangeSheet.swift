import SwiftUI

struct ChartDateRangeSheet: View {
    let bounds: ClosedRange<Date>
    let apply: (ClosedRange<Date>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    init(bounds: ClosedRange<Date>, window: ClosedRange<Date>, apply: @escaping (ClosedRange<Date>) -> Void) {
        self.bounds = bounds; self.apply = apply
        _start = State(initialValue: window.lowerBound)
        _end = State(initialValue: window.upperBound)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("精确选择日期") {
                    DatePicker("开始日期", selection: $start,
                               in: bounds.lowerBound...Calendar.current.date(byAdding: .day, value: -1, to: end)!, displayedComponents: .date)
                    DatePicker("结束日期", selection: $end,
                               in: Calendar.current.date(byAdding: .day, value: 1, to: start)!...bounds.upperBound, displayedComponents: .date)
                }
                Section {
                    Text("非实时走势截至昨天。休市日不补点，1900–2015 年保留年度数据。")
                        .font(.footnote).foregroundStyle(GoldTheme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden).background(GoldTheme.background)
            .navigationTitle("时间区间").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") { apply(ChartViewport.noon(start)...ChartViewport.noon(end)); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }.tint(GoldTheme.gold).preferredColorScheme(.dark)
            .presentationDetents([.medium, .large])
    }
}
