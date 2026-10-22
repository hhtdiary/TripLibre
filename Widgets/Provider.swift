import WidgetKit
import SwiftUI
import HHTCore

/// One moment on the widget's timeline. The snapshot is read once per timeline; later entries only move "now"
/// forward so relative times ("3 min ago") and the day rollover stay right without the app running.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    static let appGroup = "group.com.zyang91.hht"

    static func load() -> WidgetSnapshot? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .flatMap { WidgetSnapshot.read(from: $0.appendingPathComponent(WidgetSnapshot.fileName)) }
    }

    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .sample()) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        // the widget gallery shows sample data until the app has written a real snapshot
        completion(SnapshotEntry(date: Date(), snapshot: Self.load() ?? (context.isPreview ? .sample() : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snap = Self.load()
        let now = Date()
        var dates = (0..<24).map { now.addingTimeInterval(Double($0) * 15 * 60) }
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime),
           midnight < dates.last! {
            dates.append(midnight)
            dates.sort()
        }
        completion(Timeline(entries: dates.map { SnapshotEntry(date: $0, snapshot: snap) }, policy: .atEnd))
    }
}

// MARK: - Reading a snapshot at an entry's time

extension WidgetSnapshot {
    /// Today's numbers, or nil once the day the snapshot summarized is over.
    func today(at date: Date) -> Day? { Calendar.current.isDate(today.start, inSameDayAs: date) ? today : nil }

    /// Gallery preview and placeholder content: generic, no real places.
    static func sample(now: Date = Date()) -> WidgetSnapshot {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        let h = { (x: Double) in day.addingTimeInterval(x * 3600) }
        let blocks: [Block] = [
            Block(kind: .visit, start: day, end: h(8.2), category: "home", confirmed: true),
            Block(kind: .trip, start: h(8.2), end: h(8.7), category: nil, confirmed: true),
            Block(kind: .visit, start: h(8.7), end: h(12.2), category: "work_school", confirmed: true),
            Block(kind: .trip, start: h(12.2), end: h(12.3), category: nil, confirmed: false),
            Block(kind: .visit, start: h(12.3), end: h(13), category: "cafe", confirmed: false),
            Block(kind: .trip, start: h(13), end: h(13.1), category: nil, confirmed: false),
            Block(kind: .visit, start: h(13.1), end: h(17.5), category: "work_school", confirmed: true),
            Block(kind: .trip, start: h(17.5), end: h(17.8), category: nil, confirmed: false),
            Block(kind: .visit, start: h(17.8), end: min(now, h(23.9)), category: "home", confirmed: false),
        ].filter { $0.start < now }
        return WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-12 * 60), tracking: .recording, lastPointAt: now.addingTimeInterval(-3 * 60),
            diaryUpdatedAt: now.addingTimeInterval(-12 * 60), reviewPending: 2, lastStampAt: h(12.4) < now ? h(12.4) : nil,
            usesMetric: Locale.current.measurementSystem == .metric,
            today: Day(start: day, trips: 4, places: 3, distance: 18_400, travelTime: 4100, unconfirmedTrips: 1,
                       current: Stay(name: "Home", category: "home", since: h(17.8)), timeline: blocks),
            week: Week(start: cal.date(byAdding: .day, value: -6, to: day)!, end: day.addingTimeInterval(86_399),
                       tripsPerDay: [4, 6, 5, 7, 3, 1, 4], trips: 30, distance: 142_000, travelTime: 22_800,
                       modeDistance: [ModeShare(group: "car", distance: 82_000), ModeShare(group: "transit", distance: 38_000),
                                      ModeShare(group: "active", distance: 22_000)],
                       topPlace: PlaceTime(name: "Work", category: "work_school", dwell: 38 * 3600)))
    }
}
