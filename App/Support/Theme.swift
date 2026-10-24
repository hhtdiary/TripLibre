import SwiftUI
import HHTCore
#if os(iOS)
import UIKit
#endif

/// "Sticker" look: thick ink outlines, solid offset shadows, flat bright fills, rounded type.
enum Toon {
    static let ink = Color(hex: 0x22193A)
    static let muted = Color(hex: 0x5B5270)
    static let ground = Color(hex: 0xFFF3D6)
    static let paper = Color.white
    static let cream = Color(hex: 0xFFF8E6)
    static let accent = Color(hex: 0xFF6B4A)
    static let accentDeep = Color(hex: 0xC73D22)   // ≥ 4.5:1 on white/cream: it tints toolbar buttons and links
    static let sun = Color(hex: 0xFFC93C)
    static let lime = Color(hex: 0x8BDB5E)
    static let mint = Color(hex: 0x5FD3B0)
    static let sky = Color(hex: 0x5C9BFF)
    static let bubblegum = Color(hex: 0xFF7EB3)
    static let grape = Color(hex: 0xB596FF)
    static let orange = Color(hex: 0xFF9A4D)
    static let aqua = Color(hex: 0x6FD6E8)
    static let teal = Color(hex: 0x4FC3C9)
    static let stone = Color(hex: 0xD8D2C4)
    static let okGreen = Color(hex: 0x2E7D32)

    static let line: CGFloat = 2.5

    #if os(iOS)
    /// Rounded, chunky navigation-bar titles.
    static func configureAppearance() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let ink = UIColor(red: 0x22 / 255, green: 0x19 / 255, blue: 0x3A / 255, alpha: 1)
        let nav = UINavigationBar.appearance()
        // scaled like the system's own title fonts, so the titles follow Dynamic Type too (issue #67)
        nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: rounded(19, .heavy)), .foregroundColor: ink]
        nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: rounded(36, .heavy)), .foregroundColor: ink]
    }
    #endif
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    /// Fixed-size rounded type, for the widgets only: their canvas doesn't grow. App views use `.font(.toon(_:))`,
    /// which scales with Dynamic Type.
    static func toonFixed(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Rounded app type that scales with Dynamic Type (issue #67). `size` is the point size at the default text size;
/// it grows along the curve of the nearest system text style. Use it like a font: `.font(.toon(15, .bold))`.
struct ToonFont {
    var size: CGFloat
    var weight: Font.Weight = .heavy
    var monospaced = false

    static func toon(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> ToonFont { ToonFont(size: size, weight: weight) }

    func monospacedDigit() -> ToonFont {
        var font = self
        font.monospaced = true
        return font
    }

    /// The text style whose default size is closest, so e.g. 13 pt scales like `.footnote` and 34 pt like `.largeTitle`.
    var textStyle: Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18.5: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<31: return .title
        default: return .largeTitle
        }
    }
}

private struct ToonFontModifier: ViewModifier {
    let font: ToonFont
    @ScaledMetric private var size: CGFloat

    init(_ font: ToonFont) {
        self.font = font
        _size = ScaledMetric(wrappedValue: font.size, relativeTo: font.textStyle)
    }

    func body(content: Content) -> some View {
        let system = Font.system(size: size, weight: font.weight, design: .rounded)
        content.font(font.monospaced ? system.monospacedDigit() : system)
    }
}

extension View {
    func font(_ toon: ToonFont) -> some View { modifier(ToonFontModifier(toon)) }

    /// `lineLimit(lines)` plus `minimumScaleFactor`, except at accessibility text sizes, where the text wraps as far
    /// as it needs instead: shrinking it back down there would undo the size the person asked for.
    func toonLineLimit(_ lines: Int, minScale: CGFloat = 1) -> some View { modifier(ToonLineLimit(lines: lines, minScale: minScale)) }
}

private struct ToonLineLimit: ViewModifier {
    let lines: Int
    let minScale: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        } else {
            content.lineLimit(lines).minimumScaleFactor(minScale)
        }
    }
}

/// `LabeledContent` with its value in Toon.muted: the system grey is ~3.4:1 on white (issue #67). Like the system
/// style, the value moves under the label at accessibility text sizes. Forms also lay out toggles through this
/// style, so it centres vertically: a switch has no text baseline to line up with.
struct ToonLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToonRowStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            configuration.content.foregroundStyle(Toon.muted).multilineTextAlignment(.trailing)
        }
    }
}

/// A row that becomes a leading-aligned column at accessibility text sizes, so a sticker row's text gets the full
/// width instead of being squeezed beside its chips and buttons.
struct ToonRowStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}

extension PlaceCategory {
    var toonColor: Color {
        switch self {
        case .home: return Toon.sun
        case .workSchool, .library: return Toon.sky
        case .restaurant, .cafe, .bar: return Toon.orange
        case .grocery, .shopping, .convenienceStore, .gasStation: return Toon.bubblegum
        case .recreation, .entertainment, .stadium, .eventVenue, .museum, .gym: return Toon.lime
        case .airport, .railStation, .transitStation, .hotel, .parking: return Toon.grape
        case .friendFamily, .religious: return Toon.mint
        case .medical, .pharmacy, .bank, .civic: return Toon.aqua
        case .other: return Toon.paper
        }
    }
}

/// Shared with the widget extension, so mode colours match everywhere.
extension ModeGroup {
    var color: Color {
        switch self {
        case .active: return Toon.lime
        case .car: return Toon.grape
        case .transit: return Toon.sky
        case .longDistance: return Toon.bubblegum
        case .other: return Toon.stone
        }
    }
}

extension Place {
    var toonColor: Color { category?.toonColor ?? (isNamed ? Toon.paper : Toon.stone) }
}

// MARK: - Sticker surfaces

struct ToonCard: ViewModifier {
    var fill: Color = Toon.paper
    var radius: CGFloat = 20
    var shadow: CGFloat = 4
    var dashed = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Toon.ink, style: StrokeStyle(lineWidth: Toon.line, dash: dashed ? [7, 5] : [])))
            .background(shape.fill(Toon.ink).offset(x: shadow, y: shadow))
    }
}

extension View {
    func toonCard(_ fill: Color = Toon.paper, radius: CGFloat = 20, shadow: CGFloat = 4, dashed: Bool = false) -> some View {
        modifier(ToonCard(fill: fill, radius: radius, shadow: shadow, dashed: dashed))
    }

    /// Slight playful rotation for stickers.
    func tilt(_ degrees: Double) -> some View { rotationEffect(.degrees(degrees)) }

    /// List row that draws its own sticker instead of the system cell.
    func toonRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }

    /// Butter background with a faint dot grid behind lists and forms.
    func toonBackground() -> some View {
        scrollContentBackground(.hidden).background(ToonBackground())
            .labeledContentStyle(ToonLabeledContentStyle())
    }

    /// Toolbar confirm buttons ("Done", "Save") in ink: the accent tint on the Liquid Glass capsule fails the
    /// accessibility audit's contrast check (issue #67).
    func confirmTint() -> some View { tint(Toon.ink) }

    /// Form section headers and footers sit on the butter ground, where the system grey is under 4.5:1;
    /// Toon.muted is ~7:1 (issue #67).
    func toonSectionText() -> some View { foregroundStyle(Toon.muted) }
}

struct ToonBackground: View {
    var body: some View {
        Toon.ground
            .overlay(
                Canvas { ctx, size in
                    let step: CGFloat = 18
                    var y: CGFloat = step / 2
                    while y < size.height {
                        var x: CGFloat = step / 2
                        while x < size.width {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)),
                                     with: .color(Toon.ink.opacity(0.12)))
                            x += step
                        }
                        y += step
                    }
                }
            )
            .ignoresSafeArea()
    }
}

/// Pill button with an ink outline and a shadow that "presses in".
struct ToonButtonStyle: ButtonStyle {
    var fill: Color = Toon.paper
    var height: CGFloat = 36
    var fontSize: CGFloat = 13
    var shadow: CGFloat = 2.5
    var text: Color = Toon.ink

    func makeBody(configuration: Configuration) -> some View {
        ToonButtonBody(configuration: configuration, style: self)
    }
}

/// `ToonButtonStyle`'s body: the pill's height grows with the text size, and at accessibility sizes the title wraps
/// instead of shrinking.
private struct ToonButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: ToonButtonStyle
    @ScaledMetric private var height: CGFloat

    init(configuration: ButtonStyleConfiguration, style: ToonButtonStyle) {
        self.configuration = configuration
        self.style = style
        _height = ScaledMetric(wrappedValue: style.height, relativeTo: ToonFont.toon(style.fontSize).textStyle)
    }

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.toon(style.fontSize))
            .foregroundStyle(style.text)
            .toonLineLimit(1, minScale: 0.8)
            .multilineTextAlignment(.center)
            .padding(.horizontal, height * 0.32)
            .padding(.vertical, height * 0.15)   // only matters once the title wraps
            .frame(minHeight: height)
            .modifier(ToonCard(fill: style.fill, radius: min(height / 2, 24), shadow: pressed ? 0 : style.shadow))
            .offset(x: pressed ? style.shadow : 0, y: pressed ? style.shadow : 0)
            .animation(.spring(duration: 0.15), value: pressed)
    }
}

/// Rounded-square icon chip (modes, place categories).
struct ToonChip: View {
    let symbol: String
    var color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(Toon.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(color))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).strokeBorder(Toon.ink, lineWidth: size < 32 ? 2 : Toon.line))
    }
}

/// Pills left to right, wrapping onto more lines when they don't fit (filters, period pickers): they stay readable
/// at any text size, where a fixed row would clip and a sideways scroll would hide some of them.
struct ToonFlow: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let heights: [CGFloat] = rows.map { $0.map(\.size.height).max() ?? 0 }
        // split up: as one expression this times out the type checker on slower machines (CI)
        let widths: [CGFloat] = rows.map { r -> CGFloat in
            let items: CGFloat = r.map(\.size.width).reduce(0, +)
            return items + spacing * CGFloat(max(0, r.count - 1))
        }
        let widest: CGFloat = widths.max() ?? 0
        let height: CGFloat = heights.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, widest), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(item.size.width, bounds.width), height: item.size.height))
                x += item.size.width + spacing
            }
            y += height + spacing
        }
    }
}

/// Sticker tiles two to a row, or one per row at accessibility text sizes.
struct StickerGrid<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        TileLayout(columns: typeSize.isAccessibilitySize ? 1 : 2, spacing: spacing) { content }
    }
}

/// Equal-width columns, filled row by row; each row is as tall as its tallest tile.
private struct TileLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func rowHeights(_ subviews: Subviews, columnWidth: CGFloat) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            subviews[start..<min(start + columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let heights = rowHeights(subviews, columnWidth: columnWidth(width))
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = columnWidth(bounds.width)
        var y = bounds.minY
        for (row, height) in rowHeights(subviews, columnWidth: w).enumerated() {
            for col in 0..<columns where row * columns + col < subviews.count {
                subviews[row * columns + col].place(at: CGPoint(x: bounds.minX + CGFloat(col) * (w + spacing), y: y),
                                                    proposal: ProposedViewSize(width: w, height: height))
            }
            y += height + spacing
        }
    }
}

/// Big number sticker.
struct StatSticker: View {
    let value: String
    let label: String
    var color: Color
    var tilt: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.toon(26, .bold)).monospacedDigit().toonLineLimit(1, minScale: 0.6)
            Text(label).font(.toon(12)).toonLineLimit(1, minScale: 0.8)
        }
        .foregroundStyle(Toon.ink)
        // "$4.50, spent", not a bare number. Combined before the card is added, so the element's frame is the text:
        // the contrast audit measures the whole frame and would read the outline and shadow as the text's colour.
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .toonCard(color, radius: 18, shadow: 4)
        .tilt(tilt)
    }
}

/// Small rounded badge ("check", "here now", counts).
struct ToonBadge: View {
    let text: String
    var color: Color = Toon.sun
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(text)
            .font(.toon(11, .black))
            .foregroundStyle(Toon.ink)
            .toonLineLimit(1)
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(color))
            .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: 2))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.toon(20, .bold)).foregroundStyle(Toon.ink).textCase(nil)
    }
}

// MARK: - Pip, the map-pin mascot

struct Mascot: View {
    var size: CGFloat = 64
    var color: Color = Toon.accent
    var bob = true
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 80
            ctx.scaleBy(x: s, y: s)
            let ink = GraphicsContext.Shading.color(Toon.ink)

            ctx.fill(Path(ellipseIn: CGRect(x: 20, y: 87, width: 40, height: 8)), with: .color(Toon.ink.opacity(0.18)))
            var legs = Path()
            legs.move(to: CGPoint(x: 28, y: 80)); legs.addLine(to: CGPoint(x: 24, y: 89))
            legs.move(to: CGPoint(x: 52, y: 80)); legs.addLine(to: CGPoint(x: 56, y: 89))
            ctx.stroke(legs, with: ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))

            var body = Path()
            body.move(to: CGPoint(x: 40, y: 5))
            body.addCurve(to: CGPoint(x: 8, y: 36), control1: CGPoint(x: 21, y: 5), control2: CGPoint(x: 8, y: 18))
            body.addCurve(to: CGPoint(x: 40, y: 86), control1: CGPoint(x: 8, y: 59), control2: CGPoint(x: 40, y: 86))
            body.addCurve(to: CGPoint(x: 72, y: 36), control1: CGPoint(x: 40, y: 86), control2: CGPoint(x: 72, y: 59))
            body.addCurve(to: CGPoint(x: 40, y: 5), control1: CGPoint(x: 72, y: 18), control2: CGPoint(x: 59, y: 5))
            body.closeSubpath()
            ctx.fill(body, with: .color(color))
            ctx.stroke(body, with: ink, style: StrokeStyle(lineWidth: 4, lineJoin: .round))

            var shine = Path()
            shine.move(to: CGPoint(x: 20, y: 26))
            shine.addQuadCurve(to: CGPoint(x: 36, y: 13), control: CGPoint(x: 23, y: 15))
            ctx.stroke(shine, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            for x in [30.0, 50.0] {
                let eye = Path(ellipseIn: CGRect(x: x - 5, y: 29, width: 10, height: 12))
                ctx.fill(eye, with: .color(.white))
                ctx.stroke(eye, with: ink, lineWidth: 2.5)
                ctx.fill(Path(ellipseIn: CGRect(x: x + 1 - 2.6, y: 36.5 - 2.6, width: 5.2, height: 5.2)), with: ink)
            }
            for x in [22.0, 58.0] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 4.5, y: 42, width: 9, height: 6)), with: .color(Color(hex: 0xFF9FC3)))
            }
            var smile = Path()
            smile.move(to: CGPoint(x: 33, y: 46))
            smile.addQuadCurve(to: CGPoint(x: 47, y: 46), control: CGPoint(x: 40, y: 53))
            ctx.stroke(smile, with: ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
        .frame(width: size, height: size * 1.2)
        .offset(y: up ? -size * 0.04 : 0)
        .onAppear {
            guard bob, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { up = true }
        }
        .accessibilityHidden(true)
    }
}

/// Mascot with a speech bubble.
struct MascotSays: View {
    let text: String
    var size: CGFloat = 58

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Mascot(size: size)
            // the Text sits in its own container so its accessibility frame is the text alone, not the bubble's
            // outline and shadow (which the contrast audit would otherwise sample as the background)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.toon(15, .bold))
                    .foregroundStyle(Toon.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .toonCard(radius: 20, shadow: 3)
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Toon.paper)
                    .frame(width: 14, height: 14)
                    .overlay(alignment: .bottomLeading) {
                        ZStack(alignment: .bottomLeading) {
                            Rectangle().fill(Toon.ink).frame(width: Toon.line, height: 14)
                            Rectangle().fill(Toon.ink).frame(width: 14, height: Toon.line)
                        }
                    }
                    .rotationEffect(.degrees(45))
                    .offset(x: -7, y: 22)
            }
            .tilt(-1)
        }
        // a List row would otherwise present its one visible Text with the whole row's frame (mascot included)
        .accessibilityElement(children: .contain)
    }
}
