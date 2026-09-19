import SwiftUI

// MARK: - 颜色令牌

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// iOS 端「深色 + 金」行情主题令牌。
/// 首页视觉对齐参考稿：近黑底、金黄强调、胶囊控件、大号无衬线数字。
/// 颜色/形状只允许引用本令牌，禁止在页面里散落硬编码。
enum GoldTheme {
    // 底色与卡片
    static let background = Color(hex: 0x1B1B1D)
    static let card = Color(hex: 0x282523)
    static let calendarCell = Color(hex: 0x34312F)
    static let cardStroke = Color.white.opacity(0.07)

    // 强调
    static let gold = Color(hex: 0xF2C512)
    static let goldSoft = Color(hex: 0xFFE08A)
    static let onGold = Color(hex: 0x1A1A1A)

    // 文字
    static let text = Color(hex: 0xF2F2F5)
    static let textSecondary = Color(hex: 0xA3A3A3)
    static let textFaint = Color(hex: 0x6C6C76)

    // 涨跌（国内习惯：红涨绿跌）
    static let up = Color(hex: 0xFF5D5D)
    static let down = Color(hex: 0x3DD68C)

    // 图表
    static let gridline = Color.white.opacity(0.06)

    static let holdingsCardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    static let holdingPriceShape = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0, bottomTrailingRadius: 13, topTrailingRadius: 0)
    static let capsuleShape = Capsule()
    static let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    static let rangeShape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    static let serviceText = Color(hex: 0xC4C4C4)
    static let serviceStroke = Color.white.opacity(0.035)
    static let chartFill = gold.opacity(0.13)
}

/// 底栏中间下凹，给独立的圆形添加按钮留出环形间隙。
struct GoldTabBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 430
        let c = rect.midX
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: c - 66 * s, y: 0))
        path.addCurve(to: CGPoint(x: c - 42 * s, y: 20 * s),
                      control1: CGPoint(x: c - 51 * s, y: 0),
                      control2: CGPoint(x: c - 44 * s, y: 9 * s))
        path.addCurve(to: CGPoint(x: c, y: 58 * s),
                      control1: CGPoint(x: c - 39 * s, y: 42 * s),
                      control2: CGPoint(x: c - 24 * s, y: 58 * s))
        path.addCurve(to: CGPoint(x: c + 42 * s, y: 20 * s),
                      control1: CGPoint(x: c + 24 * s, y: 58 * s),
                      control2: CGPoint(x: c + 39 * s, y: 42 * s))
        path.addCurve(to: CGPoint(x: c + 66 * s, y: 0),
                      control1: CGPoint(x: c + 44 * s, y: 9 * s),
                      control2: CGPoint(x: c + 51 * s, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 参考稿的圆钱袋轮廓，与购物袋图标区分。
struct GoldMoneyBagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.29, y: 0.04))
        p.addQuadCurve(to: CGPoint(x: 0.5, y: 0.055), control: CGPoint(x: 0.34, y: -0.01))
        p.addQuadCurve(to: CGPoint(x: 0.73, y: 0.04), control: CGPoint(x: 0.66, y: -0.015))
        p.addQuadCurve(to: CGPoint(x: 0.67, y: 0.24), control: CGPoint(x: 0.82, y: 0.16))
        p.addQuadCurve(to: CGPoint(x: 0.32, y: 0.24), control: CGPoint(x: 0.5, y: 0.29))
        p.addQuadCurve(to: CGPoint(x: 0.29, y: 0.04), control: CGPoint(x: 0.2, y: 0.14))
        p.closeSubpath()
        p.move(to: CGPoint(x: 0.32, y: 0.33))
        p.addQuadCurve(to: CGPoint(x: 0.68, y: 0.33), control: CGPoint(x: 0.5, y: 0.37))
        p.addCurve(to: CGPoint(x: 0.88, y: 0.85),
                   control1: CGPoint(x: 0.78, y: 0.47), control2: CGPoint(x: 0.96, y: 0.72))
        p.addQuadCurve(to: CGPoint(x: 0.7, y: 0.98), control: CGPoint(x: 0.86, y: 0.98))
        p.addLine(to: CGPoint(x: 0.3, y: 0.98))
        p.addQuadCurve(to: CGPoint(x: 0.12, y: 0.85), control: CGPoint(x: 0.14, y: 0.98))
        p.addCurve(to: CGPoint(x: 0.32, y: 0.33),
                   control1: CGPoint(x: 0.04, y: 0.72), control2: CGPoint(x: 0.22, y: 0.47))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
    }
}

// MARK: - 容器修饰符

extension View {
    /// 深色软卡片：近黑卡底 + 极细描边。
    func goldCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(GoldTheme.card, in: GoldTheme.cardShape)
            .overlay(GoldTheme.cardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }
}

// MARK: - 按钮样式

/// 胶囊按钮：选中态金底深字，未选中卡底灰字（对齐参考稿的分段选择器）。
struct GoldCapsuleStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, design: .rounded).weight(isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                isSelected ? AnyShapeStyle(GoldTheme.gold) : AnyShapeStyle(GoldTheme.card),
                in: GoldTheme.capsuleShape
            )
            .overlay(
                GoldTheme.capsuleShape.strokeBorder(
                    isSelected ? Color.clear : GoldTheme.cardStroke,
                    lineWidth: 1
                )
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// 主操作按钮：金底深字、整宽胶囊（如「添加黄金」）。
struct GoldPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(GoldTheme.onGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
