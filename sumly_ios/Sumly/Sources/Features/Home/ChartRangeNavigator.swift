import SwiftUI

/// Overview remains at the full available range while the main chart zooms.
/// Very narrow windows get a wider manipulation frame without changing their dates.
struct ChartRangeNavigator: View {
    let points: [MarketChartPoint]
    let bounds: ClosedRange<Date>
    let window: ClosedRange<Date>
    let scale: ChartPriceScale
    let daily: Bool
    let begin: () -> Void
    let move: (ChartViewport.Part, Double) -> Void
    let end: () -> Void
    @State private var dragging = false
    @GestureState private var gestureActive = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var dragPart: ChartViewport.Part = .window

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let span = max(1, bounds.upperBound.timeIntervalSince(bounds.lowerBound))
            let actualLeft = CGFloat(window.lowerBound.timeIntervalSince(bounds.lowerBound) / span) * width
            let actualRight = CGFloat(window.upperBound.timeIntervalSince(bounds.lowerBound) / span) * width
            let boxWidth = min(width, max(72, actualRight - actualLeft))
            let left = min(max(0, (actualLeft + actualRight - boxWidth) / 2), width - boxWidth)
            ZStack(alignment: .topLeading) {
                GoldTheme.rangeShape.fill(GoldTheme.card)
                overview(width: width, height: geo.size.height)
                    .stroke(GoldTheme.goldSoft.opacity(0.55), lineWidth: 1)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                Rectangle().fill(GoldTheme.background.opacity(0.6))
                    .frame(width: max(0, left))
                    .allowsHitTesting(false)
                Rectangle().fill(GoldTheme.background.opacity(0.6))
                    .frame(width: max(0, width - left - boxWidth)).offset(x: left + boxWidth)
                    .allowsHitTesting(false)
                GoldTheme.rangeShape.fill(GoldTheme.chartFill)
                    .overlay(GoldTheme.rangeShape.strokeBorder(GoldTheme.gold, lineWidth: 1.5))
                    .frame(width: boxWidth)
                    .offset(x: left)
                    .allowsHitTesting(false)
                // Each handle has a distinct hit region even when the true range
                // covers less than one screen pixel of century-scale history.
                handle("开始", part: .start, width: width)
                    .frame(width: 24, height: geo.size.height).offset(x: left)
                handle("结束", part: .end, width: width)
                    .frame(width: 24, height: geo.size.height).offset(x: left + boxWidth - 24)
                Color.clear.contentShape(Rectangle())
                    .frame(width: max(24, boxWidth - 48), height: geo.size.height)
                    .offset(x: left + 24)
                    .highPriorityGesture(drag(.window, width: width))
                    .accessibilityElement()
                    .accessibilityLabel("移动时间区间")
                    .accessibilityValue(window.lowerBound.formatted(date: .abbreviated, time: daily ? .omitted : .shortened) + "至" + window.upperBound.formatted(date: .abbreviated, time: daily ? .omitted : .shortened))
                    .accessibilityAdjustableAction { direction in
                        begin()
                        let fraction = window.upperBound.timeIntervalSince(window.lowerBound) / span
                        move(.window, direction == .increment ? fraction : -fraction)
                        end()
                    }
                    .accessibilityIdentifier("chart.navigator.window")
            }.clipShape(GoldTheme.rangeShape)
        }
        .frame(height: 48)
        .coordinateSpace(name: "chartNavigator")
        .onChange(of: gestureActive) { _, active in
            if !active { finishDrag() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finishDrag() }
        }
        .onDisappear { finishDrag() }
    }
    private func finishDrag() {
        if dragging { dragging = false; end() }
    }
    private func handle(_ label: String, part: ChartViewport.Part, width: CGFloat) -> some View {
        ZStack {
            GoldTheme.gold.opacity(0.2)
            Capsule().fill(GoldTheme.gold).frame(width: 3, height: 24)
        }.contentShape(Rectangle())
            .highPriorityGesture(drag(part, width: width))
            .accessibilityElement().accessibilityLabel(label + "时间")
            .accessibilityAdjustableAction { direction in
                begin()
                let span = max(1, bounds.upperBound.timeIntervalSince(bounds.lowerBound))
                move(part, (direction == .increment ? 1 : -1) * (daily ? 86400 : 30) / span)
                end()
            }
            .accessibilityIdentifier(part == .start ? "chart.navigator.start" : "chart.navigator.end")
    }
    private func drag(_ part: ChartViewport.Part, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("chartNavigator"))
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                if !dragging { dragging = true; dragPart = part; begin() }
                move(dragPart, value.translation.width / width)
            }
            .onEnded { value in
                if dragging { move(dragPart, value.translation.width / width) }
                finishDrag()
            }
    }
    private func overview(width: CGFloat, height: CGFloat) -> Path {
        let domain = scale.domain(points.map(\.price))
        let span = max(1, bounds.upperBound.timeIntervalSince(bounds.lowerBound))
        let vertical = domain.upperBound - domain.lowerBound
        // Display sampling only: cache and selectable main-chart records remain intact.
        let step = max(1, points.count / 500)
        let indices = Array(stride(from: 0, to: points.count, by: step))
        return Path { path in
            for (i, index) in indices.enumerated() {
                let p = points[index]
                guard let value = scale.value(p.price) else { continue }
                let x = p.date.timeIntervalSince(bounds.lowerBound) / span * width
                let y = (1 - (value - domain.lowerBound) / vertical) * max(1, height - 16)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}
