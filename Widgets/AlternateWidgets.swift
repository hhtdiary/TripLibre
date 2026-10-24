import WidgetKit
import SwiftUI
import HHTCore

// Alternatives kept from the design round (issue #47): B's plain status card and C's trip-chain timeline.

// MARK: - Small, simple: tracking status

struct SimpleStatusView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = WTheme(scheme), info = StatusInfo.from(entry.snapshot, now: entry.date)
        let tone: (fg: Color, bg: Color) = switch info.tone {
        case .good: (t.dark ? Toon.lime : Toon.okGreen, t.dark ? Toon.okGreen.opacity(0.35) : Color(hex: 0xE6F7DC))
        case .warn: (t.dark ? Toon.sun : Color(hex: 0x8A5A00), t.dark ? Toon.sun.opacity(0.2) : Color(hex: 0xFFF1CC))
        case .off: (t.muted, t.hairline)
        }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(tone.bg)
                    if info.tone == .good { Circle().fill(tone.fg).frame(width: 10, height: 10) }
                    else { Image(systemName: info.tone == .warn ? "clock" : "pause.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(tone.fg) }
                }
                .frame(width: 26, height: 26)
                Text(info.tone == .good ? "Recording" : info.badge.capitalized)
                    .font(.toonFixed(12, .heavy)).foregroundStyle(tone.fg).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            if let last = entry.snapshot?.lastPointAt, entry.snapshot?.tracking == .recording {
                Text("Last location").font(.toonFixed(11, .bold)).foregroundStyle(t.muted)
                Text(lastValue(last)).font(.toonFixed(24, .black)).foregroundStyle(t.text).lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text(info.title).font(.toonFixed(17, .black)).foregroundStyle(t.text).lineLimit(2).minimumScaleFactor(0.7)
                Text(info.detail).font(.toonFixed(11, .bold)).foregroundStyle(t.muted).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            Rectangle().fill(t.hairline).frame(height: 1.5)
            HStack {
                if let action = info.action {
                    Text(action).font(.toonFixed(12, .heavy)).foregroundStyle(Toon.accentDeep)
                } else {
                    Text("Trips to check").font(.toonFixed(12, .heavy)).foregroundStyle(t.text)
                    Spacer()
                    let n = entry.snapshot?.reviewPending ?? 0
                    Text("\(n)").font(.toonFixed(12, .black)).foregroundStyle(Toon.ink)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(n > 0 ? Toon.accent : t.hairline))
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(t.card, for: .widget)
        .widgetURL(info.url)
    }

    /// "3 min ago" while recent; a clock time once it's been a while.
    private func lastValue(_ d: Date) -> String {
        entry.date.timeIntervalSince(d) < 3600 ? WFmt.ago(d, now: entry.date) : WFmt.when(d, now: entry.date)
    }
}

// MARK: - Medium, timeline: today as a trip chain

struct TimelineTodayView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = WTheme(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.toonFixed(18, .black)).foregroundStyle(t.text)
                Spacer(minLength: 6)
                if let s = entry.snapshot, let d = s.today(at: entry.date) {
                    let dist = WFmt.distance(d.distance, metric: s.usesMetric)
                    Text("\(WFmt.plural(d.trips, "trip")) · \(WFmt.plural(d.places, "place")) · \(dist.value) \(dist.unit)")
                        .font(.toonFixed(12, .heavy)).foregroundStyle(t.text).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if let s = entry.snapshot, let d = s.today(at: entry.date) {
                DayStrip(day: d, now: entry.date, theme: t)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    legend(Toon.paper, dashed: false, "Checked", t)
                    legend(Toon.paper, dashed: true, "Guess", t)
                    Spacer(minLength: 4)
                    if let at = s.diaryUpdatedAt {
                        Text("Updated \(WFmt.ago(at, now: entry.date))").font(.toonFixed(11, .bold)).foregroundStyle(t.muted).lineLimit(1)
                    }
                }
            } else {
                EmptyDay(snapshot: entry.snapshot, theme: t)
            }
        }
        .containerBackground(for: .widget) { t.dark ? t.ground : Toon.cream }
        .widgetURL(URL(string: "hht://today"))
    }

    private func legend(_ c: Color, dashed: Bool, _ label: String, _ t: WTheme) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Toon.ink, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : [])))
                .frame(width: 12, height: 12)
            Text(label).font(.toonFixed(11, .heavy)).foregroundStyle(t.text)
        }
    }
}

/// Midnight-to-midnight strip: visits as colored blocks, trips as ink lines, unchecked ones dashed.
private struct DayStrip: View {
    let day: WidgetSnapshot.Day
    let now: Date
    let theme: WTheme

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // 23 or 25 hours on daylight-saving days
                let length = Calendar.current.date(byAdding: .day, value: 1, to: day.start)!.timeIntervalSince(day.start)
                let x = { (d: Date) in w * CGFloat(min(max(d.timeIntervalSince(day.start) / length, 0), 1)) }
                ZStack(alignment: .leading) {
                    Path { p in p.move(to: CGPoint(x: x(now), y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2)) }
                        .stroke(theme.muted.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    ForEach(Array(day.timeline.enumerated()), id: \.offset) { _, b in
                        let bx = x(b.start), bw = max(x(b.end) - bx, b.kind == .visit ? 4 : 2)
                        if b.kind == .trip {
                            Rectangle().fill(theme.text).frame(width: bw, height: 3).offset(x: bx)
                        } else {
                            let cat = b.category.flatMap(PlaceCategory.init(rawValue:))
                            RoundedRectangle(cornerRadius: 4).fill(cat?.toonColor ?? Toon.stone)
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Toon.ink, style: StrokeStyle(lineWidth: 1.5, dash: b.confirmed ? [] : [3, 2])))
                                .frame(width: bw, height: h).offset(x: bx)
                        }
                    }
                    Capsule().fill(Toon.accent).frame(width: 3, height: h + 6).offset(x: x(now) - 1.5)
                }
            }
            .frame(height: 30)
            HStack {
                ForEach(Array([0, 6, 12, 18, 24].enumerated()), id: \.offset) { i, hour in
                    if i > 0 { Spacer(minLength: 0) }
                    Text(Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day.start)!.formatted(.dateTime.hour()))
                        .font(.toonFixed(9, .heavy)).foregroundStyle(theme.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline of today: \(day.timeline.filter { $0.kind == .visit }.count) stays and \(day.trips) trips")
    }
}
