import SwiftUI
import MapKit
import HHTCore

enum Fmt {
    static var usesMetric: Bool {
        if let v = UserDefaults.standard.string(forKey: "units") { return v == "metric" }
        return Locale.current.measurementSystem == .metric
    }

    static func distance(_ meters: Double) -> String {
        if usesMetric {
            return meters < 1000 ? String(format: "%.0f m", meters) : String(format: meters < 10_000 ? "%.1f km" : "%.0f km", meters / 1000)
        }
        let miles = meters / 1609.344
        return miles < 0.1 ? String(format: "%.0f ft", meters * 3.28084) : String(format: miles < 10 ? "%.1f mi" : "%.0f mi", miles)
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        if h < 48 { return r == 0 ? "\(h) h" : "\(h) h \(r) min" }
        return String(format: "%.1f d", s / 86_400)
    }

    static func hours(_ s: TimeInterval) -> String { String(format: "%.1f h", s / 3600) }

    static func time(_ d: Date, tz: String? = nil) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        if let tz, let zone = TimeZone(identifier: tz) { f.timeZone = zone }
        return f.string(from: d)
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, yyyy"
        return f.string(from: d)
    }

    static func shortDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: d)
    }

    static func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func minutesOfDay(_ m: Double?) -> String {
        guard let m else { return "–" }
        let h = Int(m) / 60, mm = Int(m) % 60
        return String(format: "%02d:%02d", h, mm)
    }

    static func percent(_ x: Double?) -> String { x.map { String(format: "%.0f%%", $0 * 100) } ?? "–" }

    static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static func parseYMD(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

extension TravelMode {
    var color: Color {
        switch self {
        case .run: return Toon.mint
        case .bicycle, .ebike, .scooter: return Toon.sun
        case .bus, .coach, .shuttle: return Toon.orange
        case .ferry: return Toon.teal
        case .airplane: return Toon.aqua
        default: return group.color
        }
    }
}

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension View {
    /// Inline navigation title on iOS; no-op elsewhere (lets the UI type-check on macOS too).
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func groupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped).toonBackground()
        #else
        self
        #endif
    }

    @ViewBuilder func decimalKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder func capsKeyboard() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }
}

/// Small labelled number used in summary strips.
struct StatPill: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.toon(17, .bold).monospacedDigit()).foregroundStyle(Toon.ink)
                .toonLineLimit(1, minScale: 0.6)
            Text(label).font(.toon(11, .bold)).foregroundStyle(Toon.muted)
                .toonLineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ModeIcon: View {
    let mode: TravelMode
    var size: CGFloat = 28
    var body: some View {
        // some symbols (e.g. subway's tram.fill.tunnel) have no built-in label, and VoiceOver would read the symbol name
        ToonChip(symbol: mode.symbol, color: mode.color, size: size)
            .accessibilityLabel(mode.label)
    }
}
