import WidgetKit
import SwiftUI
import HHTCore

/// Home Screen widgets (issue #47). They show the snapshot the app writes to the App Group and never start location
/// collection or inference themselves; the Stamp widget only opens the app's own stamp (phase 2).
@main
struct HHTWidgets: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        TodayWidget()
        WeekWidget()
        SimpleStatusWidget()
        TimelineTodayWidget()
        StampWidget()
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HHTStatus", provider: SnapshotProvider()) { StickerStatusView(entry: $0) }
            .configurationDisplayName("Tracking")
            .description("Whether TripLibre is recording, and when it last got a location.")
            .supportedFamilies([.systemSmall])
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HHTToday", provider: SnapshotProvider()) { StickerTodayView(entry: $0) }
            .configurationDisplayName("Today")
            .description("Trips, distance and places so far today.")
            .supportedFamilies([.systemMedium])
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HHTWeek", provider: SnapshotProvider()) { StickerWeekView(entry: $0) }
            .configurationDisplayName("Last 7 days")
            .description("Your week in trips, distance, modes and places.")
            .supportedFamilies([.systemLarge])
    }
}

struct SimpleStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HHTStatusSimple", provider: SnapshotProvider()) { SimpleStatusView(entry: $0) }
            .configurationDisplayName("Tracking (simple)")
            .description("A plain card with recording status and trips to check.")
            .supportedFamilies([.systemSmall])
    }
}

struct TimelineTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HHTTodayTimeline", provider: SnapshotProvider()) { TimelineTodayView(entry: $0) }
            .configurationDisplayName("Today's timeline")
            .description("Today as a strip of stays and trips.")
            .supportedFamilies([.systemMedium])
    }
}

#Preview("Status", as: .systemSmall) { StatusWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample())
    SnapshotEntry(date: .now, snapshot: { var s = WidgetSnapshot.sample(); s.tracking = .permissionNeeded; return s }())
    SnapshotEntry(date: .now, snapshot: nil)
}
#Preview("Today", as: .systemMedium) { TodayWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample()) }
#Preview("Week", as: .systemLarge) { WeekWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample()) }
#Preview("Timeline", as: .systemMedium) { TimelineTodayWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample()) }
