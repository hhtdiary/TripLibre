import WidgetKit
import SwiftUI
import HHTCore

// The chosen "Sticker" style (issue #47 design A): small status, medium today, large last 7 days.

private struct InkBadge: View {
    let text: String
    let fill: Color
    var body: some View {
        Text(text)
            .font(.toonFixed(11, .black)).foregroundStyle(Toon.ink).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: 2))
    }
}

/// Number + label sticker, as on the Today and Stats screens.
private struct Sticker: View {
    let value: String
    let label: String
    let color: Color
    var tilt: Double = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.toonFixed(24, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.toonFixed(11, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Toon.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .toonCard(color, radius: 14, shadow: 3)
        .tilt(tilt)
        .accessibilityElement(children: .combine)
    }
}

private struct ReviewBadge: View {
    let count: Int
    var body: some View {
        if count > 0 {
            InkBadge(text: "\(count) to check", fill: Toon.sun)
                .accessibilityLabel("\(count) trip\(count == 1 ? "" : "s") to check")
        }
    }
}

// MARK: - Small: tracking status

struct StickerStatusView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = WTheme(scheme), info = StatusInfo.from(entry.snapshot, now: entry.date)
        let fill: Color = info.tone == .good ? Toon.lime : info.tone == .warn ? Toon.sun : Toon.stone
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                InkBadge(text: info.badge, fill: fill)
                Spacer(minLength: 4)
                if info.tone == .good { Mascot(size: 26, bob: false) }
            }
            Spacer(minLength: 4)
            Text(info.title).font(.toonFixed(20, .black)).foregroundStyle(t.text)
                .lineLimit(2).minimumScaleFactor(0.7)
            Text(info.detail).font(.toonFixed(12, .bold)).foregroundStyle(t.muted)
                .lineLimit(2).minimumScaleFactor(0.8).padding(.top, 2)
            Spacer(minLength: 6)
            if let action = info.action {
                Text(action).font(.toonFixed(12, .black)).foregroundStyle(Toon.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .toonCard(Toon.accent, radius: 12, shadow: 2)
            } else if let n = entry.snapshot?.reviewPending, n > 0 {
                Text("\(n) trip\(n == 1 ? "" : "s") to check").font(.toonFixed(12, .black)).foregroundStyle(Toon.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .toonCard(Toon.sun, radius: 12, shadow: 2)
            } else {
                Text("All checked").font(.toonFixed(12, .heavy)).foregroundStyle(t.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { DotGround(theme: t) }
        .widgetURL(info.url)
    }
}

// MARK: - Medium: today

struct StickerTodayView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = WTheme(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today · \(WFmt.dayTitle(entry.date))").font(.toonFixed(16, .black)).foregroundStyle(t.text).lineLimit(1)
                Spacer(minLength: 6)
                if let at = entry.snapshot?.diaryUpdatedAt {
                    Text("Updated \(WFmt.ago(at, now: entry.date))").font(.toonFixed(11, .bold)).foregroundStyle(t.muted).lineLimit(1)
                }
            }
            if let s = entry.snapshot, let d = s.today(at: entry.date) {
                let dist = WFmt.distance(d.distance, metric: s.usesMetric)
                HStack(spacing: 12) {
                    Sticker(value: "\(d.trips)", label: d.trips == 1 ? "trip" : "trips", color: Toon.sky, tilt: -2)
                    Sticker(value: dist.value, label: dist.unit, color: Toon.mint, tilt: 1.5)
                    Sticker(value: "\(d.places)", label: d.places == 1 ? "place" : "places", color: Toon.sun, tilt: -1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if let c = d.current { CurrentStay(stay: c, now: entry.date, theme: t) }
                    Spacer(minLength: 4)
                    if d.unconfirmedTrips > 0 {
                        InkBadge(text: "\(d.unconfirmedTrips) to check", fill: Toon.sun)
                    }
                }
            } else {
                EmptyDay(snapshot: entry.snapshot, theme: t)
            }
        }
        .containerBackground(for: .widget) { DotGround(theme: t) }
        .widgetURL(URL(string: "hht://today"))
    }
}

struct CurrentStay: View {
    let stay: WidgetSnapshot.Stay
    let now: Date
    let theme: WTheme
    var body: some View {
        let cat = stay.category.flatMap(PlaceCategory.init(rawValue:))
        HStack(spacing: 6) {
            ToonChip(symbol: cat?.symbol ?? "mappin", color: cat?.toonColor ?? Toon.paper, size: 22)
            (Text("At ") + Text(stay.name ?? (cat == .other ? nil : cat?.label) ?? "a new place") + Text(" since \(WFmt.when(stay.since, now: now))"))
                .font(.toonFixed(13, .heavy)).foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.7)
                .privacySensitive()
        }
    }
}

struct EmptyDay: View {
    let snapshot: WidgetSnapshot?
    let theme: WTheme
    var body: some View {
        HStack(spacing: 12) {
            Mascot(size: 40, color: snapshot?.tracking == .recording ? Toon.accent : Toon.stone, bob: false)
            Text(snapshot == nil ? "Open TripLibre once and your day shows up here."
                 : snapshot?.tracking == .recording ? "A new day! It fills in as TripLibre records your trips."
                 : "Nothing recorded today. Tracking isn't running.")
                .font(.toonFixed(14, .heavy)).foregroundStyle(theme.text).lineLimit(3).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Large: last 7 days

struct StickerWeekView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = WTheme(scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // past midnight the stored week ends yesterday until the app runs again: say so instead of "Last 7 days"
                Text(entry.snapshot.map { $0.week.isCurrent(at: entry.date) ? "Last 7 days"
                        : "7 days to \($0.week.end.formatted(.dateTime.weekday(.abbreviated)))" } ?? "Last 7 days")
                    .font(.toonFixed(18, .black)).foregroundStyle(t.text).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                if let w = entry.snapshot?.week {
                    Text("\(w.start.formatted(.dateTime.day().month(.abbreviated))) – \(w.end.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.toonFixed(12, .bold)).foregroundStyle(t.muted).lineLimit(1)
                }
            }
            if let s = entry.snapshot {
                content(s, t)
            } else {
                EmptyDay(snapshot: nil, theme: t)
            }
        }
        .containerBackground(for: .widget) { DotGround(theme: t) }
        .widgetURL(URL(string: "hht://stats"))
    }

    @ViewBuilder private func content(_ s: WidgetSnapshot, _ t: WTheme) -> some View {
        let w = s.week, dist = WFmt.distance(w.distance, metric: s.usesMetric)
        HStack(spacing: 12) {
            Sticker(value: "\(w.trips)", label: "trips", color: Toon.sky, tilt: -1.5)
            Sticker(value: dist.value, label: dist.unit, color: Toon.mint, tilt: 1)
            Sticker(value: WFmt.duration(w.travelTime), label: "on the move", color: Toon.bubblegum, tilt: -0.5)
        }
        TripBars(week: w, current: w.isCurrent(at: entry.date), theme: t)
        if !w.modeDistance.isEmpty { ModeBar(shares: w.modeDistance, theme: t) }
        Spacer(minLength: 0)
        HStack(spacing: 8) {
            if let p = w.topPlace {
                let cat = p.category.flatMap(PlaceCategory.init(rawValue:))
                ToonChip(symbol: cat?.symbol ?? "mappin", color: cat?.toonColor ?? Toon.paper, size: 22)
                (Text("Most time: ") + Text(p.name ?? (cat == .other ? nil : cat?.label) ?? "an unnamed place") + Text(" · \(WFmt.hours(p.dwell))"))
                    .font(.toonFixed(13, .heavy)).foregroundStyle(t.text).lineLimit(1).minimumScaleFactor(0.7)
                    .privacySensitive()
            }
            Spacer(minLength: 4)
            ReviewBadge(count: s.reviewPending)
        }
    }
}

private struct TripBars: View {
    let week: WidgetSnapshot.Week
    /// The last bar is today; otherwise it's just the last day of a week that has rolled over.
    let current: Bool
    let theme: WTheme

    var body: some View {
        let top = max(week.tripsPerDay.max() ?? 0, 1)
        let days = (0..<week.tripsPerDay.count).map { Calendar.current.date(byAdding: .day, value: $0, to: week.start)! }
        VStack(alignment: .leading, spacing: 4) {
            Text("Trips per day").font(.toonFixed(11, .black)).foregroundStyle(Toon.muted)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(week.tripsPerDay.enumerated()), id: \.offset) { i, n in
                    VStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Text("\(n)").font(.toonFixed(10, .black)).foregroundStyle(Toon.ink).fixedSize()
                        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 6)
                            .fill(current && i == week.tripsPerDay.count - 1 ? Toon.accent : Toon.sun)
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 6)
                                .strokeBorder(Toon.ink, lineWidth: 2))
                            .frame(height: max(4, 58 * CGFloat(n) / CGFloat(top)))
                        Text(current && i == week.tripsPerDay.count - 1 ? "Today" : days[i].formatted(.dateTime.weekday(.narrow)))
                            .font(.toonFixed(9, .black)).foregroundStyle(Toon.ink).lineLimit(1).fixedSize()
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(days[i].formatted(.dateTime.weekday(.wide))): \(n) trips")
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .toonCard(Toon.paper, radius: 14, shadow: 0)
    }
}

private struct ModeBar: View {
    let shares: [WidgetSnapshot.ModeShare]
    let theme: WTheme

    /// The three biggest groups, everything else summed into Other, so the bar fills and the percentages add up.
    static func rows(_ shares: [WidgetSnapshot.ModeShare]) -> [(ModeGroup, Double)] {
        var byGroup: [(ModeGroup, Double)] = shares.map { (ModeGroup(rawValue: $0.group) ?? .other, $0.distance) }
            .sorted { $0.1 > $1.1 }
        guard byGroup.count > 3 else { return byGroup }
        let rest = byGroup[3...].reduce(0) { $0 + $1.1 }
        byGroup = Array(byGroup.prefix(3))
        if let i = byGroup.firstIndex(where: { $0.0 == .other }) { byGroup[i].1 += rest } else { byGroup.append((.other, rest)) }
        return byGroup
    }

    var body: some View {
        let total = shares.reduce(0) { $0 + $1.distance }
        let rows = Self.rows(shares).map { ($0.0, $0.1 / max(total, 1)) }
        VStack(alignment: .leading, spacing: 5) {
            Text("How you got around · by distance").font(.toonFixed(11, .black)).foregroundStyle(theme.muted)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(rows, id: \.0) { g, f in
                        Rectangle().fill(g.color).frame(width: geo.size.width * f)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Toon.ink, lineWidth: 2))
            HStack(spacing: 10) {
                ForEach(rows, id: \.0) { g, f in
                    Text("\(g.shortLabel) \(Int((f * 100).rounded()))%")
                        .font(.toonFixed(11, .heavy)).foregroundStyle(theme.text).lineLimit(1)
                }
            }
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}
