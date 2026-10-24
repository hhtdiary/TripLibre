import WidgetKit
import SwiftUI
import HHTCore

// Quick Stamp (issue #47, phase 2). A widget can't get a fresh fix or write the diary safely, so the tap opens HHT
// (`hht://stamp`) and the app stamps exactly as Today's "Stamp this moment" button does, with its confirmation and
// Undo. The widget itself saves nothing and never touches location.

struct StampWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HHTStamp", provider: SnapshotProvider()) { StampWidgetView(entry: $0) }
            .configurationDisplayName("Stamp")
            .description("One tap to mark a stop too short for TripLibre to notice. Opens TripLibre to save it.")
            .supportedFamilies([.systemSmall])
    }
}

struct StampWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    static let url = URL(string: "hht://stamp")!

    var body: some View {
        let t = WTheme(scheme)
        VStack(alignment: .leading, spacing: 0) {
            ToonChip(symbol: "hand.tap.fill", color: Toon.sun, size: 44)
                .accessibilityHidden(true)
            Spacer(minLength: 6)
            Text("Stamp this moment").font(.toonFixed(18, .black)).foregroundStyle(t.text)
                .lineLimit(2).minimumScaleFactor(0.7)
            Text(footer).font(.toonFixed(12, .bold)).foregroundStyle(t.muted)
                .lineLimit(2).minimumScaleFactor(0.8).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens TripLibre and records that you stopped somewhere around here, around now")
        .containerBackground(for: .widget) { DotGround(theme: t) }
        .widgetURL(Self.url)
    }

    /// The last stamp, so a tap's result shows here too; or what a tap will do.
    private var footer: String {
        guard let s = entry.snapshot else { return "Opens TripLibre to save it" }
        if let last = s.lastStampAt { return "Last stamp " + WFmt.when(last, now: entry.date) }
        switch s.tracking {
        case .recording, .backgroundLimited: return "For stops TripLibre might miss"
        // a stamp still saves without location access, but only its time; say so before the tap
        case .permissionNeeded: return "No location access: saves the time only"
        case .paused: return "Tracking paused: still saves a stamp"
        }
    }
}

#Preview("Stamp", as: .systemSmall) { StampWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .sample())
    SnapshotEntry(date: .now, snapshot: { var s = WidgetSnapshot.sample(); s.lastStampAt = nil; return s }())
    SnapshotEntry(date: .now, snapshot: nil)
}
