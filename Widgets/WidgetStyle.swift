import SwiftUI
import HHTCore

/// Widget colors on top of the app's Toon palette. The app itself is light-only; widgets follow the Home Screen,
/// so the butter ground and text flip in dark mode while the bright stickers stay as they are.
struct WTheme {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    var ground: Color { dark ? Color(hex: 0x241C38) : Toon.ground }
    var dots: Color { dark ? Color.white.opacity(0.10) : Toon.ink.opacity(0.12) }
    var text: Color { dark ? Toon.cream : Toon.ink }
    var muted: Color { dark ? Color(hex: 0xC9C0DD) : Toon.muted }
    /// Plain card for the "simple" style.
    var card: Color { dark ? Color(hex: 0x1C1730) : .white }
    var hairline: Color { dark ? Color.white.opacity(0.12) : Color(hex: 0xEEE9F5) }
}

/// The app's dotted butter background, sized for a widget.
struct DotGround: View {
    let theme: WTheme
    var body: some View {
        theme.ground.overlay(
            Canvas { ctx, size in
                let step: CGFloat = 18
                var y = step / 2
                while y < size.height {
                    var x = step / 2
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(theme.dots))
                        x += step
                    }
                    y += step
                }
            })
    }
}

// MARK: - Formatting (the extension can't read the app's settings, so units come with the snapshot)

enum WFmt {
    static func distance(_ m: Double, metric: Bool) -> (value: String, unit: String) {
        if metric {
            if m < 1000 { return (String(format: "%.0f", m), "m") }
            return (String(format: m < 100_000 ? "%.1f" : "%.0f", m / 1000), "km")
        }
        let mi = m / 1609.344
        if mi < 0.05 { return ("0", "mi") }
        return (String(format: mi < 100 ? "%.1f" : "%.0f", mi), "mi")
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    static func hours(_ s: TimeInterval) -> String {
        s < 3600 ? "\(Int(s / 60)) min" : "\(Int((s / 3600).rounded())) h"
    }

    static func ago(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86_400 { return "\(Int(s / 3600)) hr ago" }
        return "since " + d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    /// A clock time, with the weekday when it isn't on `now`'s day.
    static func when(_ d: Date, now: Date) -> String {
        Calendar.current.isDate(d, inSameDayAs: now) ? time(d) : d.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    static func dayTitle(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
}

extension WidgetSnapshot.Week {
    /// The window still ends today; after midnight it ends yesterday until the app writes a new snapshot.
    func isCurrent(at date: Date) -> Bool { Calendar.current.isDate(end, inSameDayAs: date) }
}

extension ModeGroup {
    var shortLabel: String {
        switch self {
        case .active: return "Active"
        case .car: return "Car"
        case .transit: return "Transit"
        case .longDistance: return "Long trip"
        case .other: return "Other"
        }
    }
}

// MARK: - Tracking status, shared by both small styles

struct StatusInfo {
    enum Tone { case good, warn, off }
    var badge: String
    var title: String
    var detail: String
    var action: String?
    var tone: Tone
    var url: URL

    static func from(_ s: WidgetSnapshot?, now: Date) -> StatusInfo {
        let settings = URL(string: "hht://settings")!, today = URL(string: "hht://today")!
        guard let s else {
            return StatusInfo(badge: "SET UP", title: "Open TripLibre", detail: "The widget fills in once the app has run",
                              action: nil, tone: .off, url: today)
        }
        switch s.tracking {
        case .paused:
            return StatusInfo(badge: "PAUSED", title: "Tracking paused", detail: "Turned off in TripLibre",
                              action: "Open to resume", tone: .off, url: settings)
        case .permissionNeeded:
            return StatusInfo(badge: "NOT RECORDING", title: "Location access is off", detail: lastLine(s, now),
                              action: "Open to fix", tone: .off, url: settings)
        case .backgroundLimited:
            return StatusInfo(badge: "LIMITED", title: "Only while open", detail: "Allow Always to catch every trip",
                              action: "Open to fix", tone: .warn, url: settings)
        case .recording:
            guard let last = s.lastPointAt else {
                return StatusInfo(badge: "RECORDING", title: "Tracking on", detail: "Waiting for the first point",
                                  action: nil, tone: .good, url: today)
            }
            // the collector sleeps while you stay put, so hours without points are normal; a day is not
            if now.timeIntervalSince(last) > 12 * 3600 {
                return StatusInfo(badge: "QUIET", title: "Tracking on", detail: "No new points " + WFmt.ago(last, now: now),
                                  action: nil, tone: .warn, url: today)
            }
            return StatusInfo(badge: "RECORDING", title: "Tracking on", detail: "Last point " + WFmt.ago(last, now: now),
                              action: nil, tone: .good, url: today)
        }
    }

    private static func lastLine(_ s: WidgetSnapshot, _ now: Date) -> String {
        s.lastPointAt.map { "No data since " + WFmt.when($0, now: now) } ?? "No data yet"
    }
}
