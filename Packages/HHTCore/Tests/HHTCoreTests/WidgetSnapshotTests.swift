import Foundation
import Testing
@testable import HHTCore

/// Widget-facing snapshot (issue #47): same day rules as Today, rollover, privacy, and the shared file.
@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    static func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    /// Yesterday 23:30 → today 00:20 trip, a morning at work (confirmed), an ongoing visit at home.
    static func seeded() throws -> TravelStore {
        let s = try TravelStore.inMemory()
        try s.upsertPlace(Place(id: "home", name: "Home", coordinate: Philly.home, category: .home, source: .manual))
        try s.upsertPlace(Place(id: "lab", name: "Lab", coordinate: Philly.penn, category: .workSchool, source: .manual))
        try s.upsertVisit(Visit(id: "v1", placeID: "lab", arrival: at(18, 20), departure: at(18, 23, 30), coordinate: Philly.penn))
        try s.upsertVisit(Visit(id: "v2", placeID: "home", arrival: at(19, 0, 20), departure: at(19, 8), coordinate: Philly.home))
        try s.upsertVisit(Visit(id: "v3", placeID: "lab", arrival: at(19, 8, 30), departure: at(19, 17), coordinate: Philly.penn,
                                userStatus: .confirmed))
        try s.upsertVisit(Visit(id: "v4", placeID: "home", arrival: at(19, 17, 30), departure: nil, coordinate: Philly.home))
        try s.upsertTrip(Trip(id: "t0", originVisitID: "v1", destinationVisitID: "v2", departure: at(18, 23, 30), arrival: at(19, 0, 20),
                              distance: 3000, modeAuto: .car, modeConfidence: 0.9))
        try s.upsertTrip(Trip(id: "t1", originVisitID: "v2", destinationVisitID: "v3", departure: at(19, 8), arrival: at(19, 8, 30),
                              distance: 2500, modeAuto: .bicycle, modeConfidence: 0.8))
        try s.upsertTrip(Trip(id: "t2", originVisitID: "v3", destinationVisitID: "v4", departure: at(19, 17), arrival: at(19, 17, 30),
                              distance: 2600, modeAuto: .unknown, modeConfidence: nil))
        return s
    }

    @Test func todayMatchesTodayScreenRules() throws {
        let snap = try WidgetSnapshot.build(store: Self.seeded(), tracking: .recording, diaryUpdatedAt: nil, usesMetric: true,
                                            now: Self.at(19, 19), calendar: Self.cal)
        // the trip across midnight counts on both days, like DayData.load
        #expect(snap.today.trips == 3)
        #expect(snap.today.places == 2)
        #expect(snap.today.distance == 8100)
        #expect(snap.today.unconfirmedTrips == 1)
        #expect(snap.today.start == Self.at(19, 0))
        #expect(snap.today.current?.name == "Home")
        #expect(snap.today.current?.since == Self.at(19, 17, 30))
        // timeline is clipped to today and to now, in order
        #expect(snap.today.timeline.first?.start == Self.at(19, 0))
        #expect(snap.today.timeline.last?.end == Self.at(19, 19))
        #expect(snap.today.timeline.map(\.start) == snap.today.timeline.map(\.start).sorted())
        #expect(snap.today.timeline.first { $0.kind == .visit && $0.category == "work_school" }?.confirmed == true)
        #expect(snap.reviewPending == 1)
    }

    @Test func weekBarsCountEachDayLikeToday() throws {
        let snap = try WidgetSnapshot.build(store: Self.seeded(), tracking: .recording, diaryUpdatedAt: nil, usesMetric: true,
                                            now: Self.at(19, 19), calendar: Self.cal)
        #expect(snap.week.tripsPerDay.count == 7)
        #expect(snap.week.tripsPerDay.suffix(2) == [1, 3])
        #expect(snap.week.trips == 3)                   // Stats counts each trip once, by departure
        #expect(snap.week.modeDistance.first?.group == ModeGroup.car.rawValue)
        #expect(snap.week.topPlace?.name == "Lab")
    }

    @Test func rolloverStartsAnEmptyDay() throws {
        let snap = try WidgetSnapshot.build(store: Self.seeded(), tracking: .recording, diaryUpdatedAt: nil, usesMetric: true,
                                            now: Self.at(20, 0, 5), calendar: Self.cal)
        #expect(snap.today.start == Self.at(20, 0))
        #expect(snap.today.trips == 0)
        #expect(snap.today.places == 1)                 // still at home since yesterday
        #expect(snap.today.current?.since == Self.at(19, 17, 30))
        #expect(snap.week.tripsPerDay.suffix(3) == [1, 3, 0])
    }

    @Test func unnamedPlacesStayUnnamed() throws {
        let s = try TravelStore.inMemory()
        try s.upsertPlace(Place(id: "p", coordinate: Philly.grocery, address: "123 Private St", source: .inferred))
        try s.upsertVisit(Visit(placeID: "p", arrival: Self.at(19, 9), departure: nil, coordinate: Philly.grocery))
        let snap = try WidgetSnapshot.build(store: s, tracking: .paused, diaryUpdatedAt: nil, usesMetric: false,
                                            now: Self.at(19, 10), calendar: Self.cal)
        #expect(snap.today.current?.name == nil)
        let json = String(decoding: try JSONEncoder().encode(snap), as: UTF8.self)
        #expect(!json.contains("Private St"))
        #expect(!json.contains("39.94"))               // no coordinates leave the app
    }

    @Test func fileRoundTripAndVersionGate() throws {
        let snap = try WidgetSnapshot.build(store: Self.seeded(), tracking: .backgroundLimited, diaryUpdatedAt: Self.at(19, 18),
                                            usesMetric: true, now: Self.at(19, 19), calendar: Self.cal)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hht-widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snap.write(to: url)
        #expect(WidgetSnapshot.read(from: url) == snap)

        var later = snap
        later.generatedAt = Self.at(19, 20)
        #expect(later.sameContent(as: snap))
        later.reviewPending += 1
        #expect(!later.sameContent(as: snap))

        var future = snap
        future.version = WidgetSnapshot.currentVersion + 1
        try future.write(to: url)
        #expect(WidgetSnapshot.read(from: url) == nil)
        #expect(WidgetSnapshot.read(from: url.appendingPathExtension("missing")) == nil)
    }
}
