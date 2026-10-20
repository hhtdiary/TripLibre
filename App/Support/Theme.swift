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
    static let accentDeep = Color(hex: 0xD9452A)
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
        nav.titleTextAttributes = [.font: rounded(19, .heavy), .foregroundColor: ink]
        nav.largeTitleTextAttributes = [.font: rounded(36, .heavy), .foregroundColor: ink]
    }
    #endif
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    static func toon(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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
    }
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
        let pressed = configuration.isPressed
        configuration.label
            .font(.toon(fontSize))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, height * 0.32)
            .frame(minHeight: height)
            .modifier(ToonCard(fill: fill, radius: height / 2, shadow: pressed ? 0 : shadow))
            .offset(x: pressed ? shadow : 0, y: pressed ? shadow : 0)
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

/// Big number sticker.
struct StatSticker: View {
    let value: String
    let label: String
    var color: Color
    var tilt: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.toon(26, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.toon(12)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Toon.ink)
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
    var body: some View {
        Text(text)
            .font(.toon(11, .black))
            .foregroundStyle(Toon.ink)
            .lineLimit(1).fixedSize()
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
            guard bob else { return }
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
            Text(text)
                .font(.toon(15, .bold))
                .foregroundStyle(Toon.ink)
                .fixedSize(horizontal: false, vertical: true)
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
    }
}
